from __future__ import annotations

import base64
import json
import mimetypes
import shutil
import subprocess
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from lab_config import (
    ARTIFACT_MODEL,
    ARTIFACT_SPLIT,
    BUNDLED_MODEL_OUT,
    CAULDRON_ICON_CANDIDATES,
    DEFAULT_DATASET_DIR,
    EVALUATE_SCRIPT,
    EXPORT_COREML_SCRIPT,
    EXPORT_SCRIPT,
    HOLDOUT_DOC_PREFIX,
    LABELS,
    LOCAL_CASES_DIR,
    METRICS_HISTORY_PATH,
    LOCAL_TMP_DIR,
    REGRESSION_SCRIPT,
    STATIC_DIR,
    TRAIN_SCRIPT,
    VALIDATE_SCRIPT,
)
from lab_predictor import PREDICTOR
from lab_recipe import _assemble_app_recipe, _fetch_url_text, _normalize_lines, _run_image_ocr


# UI is served from tools/recipe_schema_lab/static.
# This keeps style/layout/behavior separated from backend request handlers.
def _json_response(handler: BaseHTTPRequestHandler, payload: dict[str, Any], status: int = 200) -> None:
    body = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def _read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    raw = handler.rfile.read(length)
    if not raw:
        return {}
    return json.loads(raw.decode("utf-8"))


def _cauldron_icon_path() -> Path | None:
    for path in CAULDRON_ICON_CANDIDATES:
        if path.exists():
            return path
    return None


def _read_index_html() -> str:
    index_path = STATIC_DIR / "index.html"
    if not index_path.exists():
        raise FileNotFoundError(f"Missing UI entrypoint: {index_path}")
    return index_path.read_text(encoding="utf-8").replace("__DATASET_DIR__", str(DEFAULT_DATASET_DIR))


def _read_json_file(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None
    if not isinstance(payload, dict):
        return None
    return payload


METRICS_HISTORY_MAX = 120
FAILURE_SOURCE_TYPES = {"ocr_failure", "parse_failure"}
HOLDOUT_SAVE_KINDS = {"holdout", "ocr_failure", "parse_failure"}


def _normalized_save_kind(raw_value: Any) -> str:
    value = str(raw_value or "train").strip().lower()
    if value in {"train", "holdout", "ocr_failure", "parse_failure"}:
        return value
    return "train"


def _effective_case_id(case_id: str, source_type: str, save_kind: str) -> str:
    normalized_id = str(case_id).strip()
    normalized_source = str(source_type).strip().lower()
    normalized_kind = _normalized_save_kind(save_kind)
    requires_holdout = normalized_source in FAILURE_SOURCE_TYPES or normalized_kind in HOLDOUT_SAVE_KINDS
    if requires_holdout and not normalized_id.startswith(HOLDOUT_DOC_PREFIX):
        return f"{HOLDOUT_DOC_PREFIX}{normalized_id}"
    return normalized_id


def _load_metrics_history() -> list[dict[str, Any]]:
    payload = _read_json_file(METRICS_HISTORY_PATH)
    if not payload:
        return []
    runs = payload.get("runs")
    if not isinstance(runs, list):
        return []
    normalized: list[dict[str, Any]] = []
    for item in runs:
        if isinstance(item, dict):
            normalized.append(item)
    return normalized


def _save_metrics_history(runs: list[dict[str, Any]]) -> None:
    METRICS_HISTORY_PATH.parent.mkdir(parents=True, exist_ok=True)
    bounded = runs[-METRICS_HISTORY_MAX:]
    METRICS_HISTORY_PATH.write_text(
        json.dumps({"runs": bounded}, indent=2) + "\n",
        encoding="utf-8",
    )


def _append_metrics_history(entry: dict[str, Any]) -> list[dict[str, Any]]:
    runs = _load_metrics_history()
    runs.append(entry)
    _save_metrics_history(runs)
    return runs


def _metrics_thresholds(
    eval_metrics: dict[str, Any] | None,
    regression_metrics: dict[str, Any] | None,
) -> dict[str, Any]:
    thresholds = {
        "macro_f1": False,
        "note_recall": False,
        "ingredient_step_confusion": False,
        "regression_note_leakage": False,
        "regression_swap": False,
    }
    if eval_metrics:
        macro_f1 = float(eval_metrics.get("macro_f1_present_labels", eval_metrics.get("macro_f1", 0.0)))
        note_metrics = ((eval_metrics.get("per_class") or {}).get("note") or {})
        note_recall = float(note_metrics.get("recall", 0.0))
        note_support = float(note_metrics.get("support", 0.0))
        confusion = float(eval_metrics.get("ingredient_step_confusion_rate", 1.0))
        thresholds["macro_f1"] = macro_f1 >= 0.88
        thresholds["note_recall"] = (note_recall >= 0.85) if note_support > 0.0 else True
        thresholds["ingredient_step_confusion"] = confusion <= 0.08
        thresholds["note_recall_applicable"] = note_support > 0.0
    if regression_metrics:
        note_leakage = float(regression_metrics.get("note_leakage_rate", 1.0))
        swap_rate = float(regression_metrics.get("ingredient_step_swap_rate", 1.0))
        thresholds["regression_note_leakage"] = note_leakage <= 0.05
        thresholds["regression_swap"] = swap_rate <= 0.08
    thresholds["overall"] = (
        thresholds["macro_f1"]
        and thresholds["note_recall"]
        and thresholds["ingredient_step_confusion"]
        and thresholds["regression_note_leakage"]
        and thresholds["regression_swap"]
    )
    return thresholds


def _line_eval_summary(metrics: dict[str, Any] | None) -> dict[str, Any]:
    if not metrics:
        return {
            "available": False,
            "macro_f1": None,
            "macro_f1_reported": None,
            "note_recall": None,
            "note_support": None,
            "note_recall_applicable": None,
            "ingredient_step_confusion_rate": None,
            "prediction_count": None,
            "present_label_count": None,
            "thresholds": {
                "macro_f1": False,
                "note_recall": False,
                "ingredient_step_confusion": False,
                "overall": False,
            },
        }
    macro_f1_reported = float(metrics.get("macro_f1", 0.0))
    per_class = metrics.get("per_class") or {}
    supported_f1: list[float] = []
    for class_metrics in per_class.values():
        if not isinstance(class_metrics, dict):
            continue
        support = float(class_metrics.get("support", 0.0))
        if support <= 0.0:
            continue
        supported_f1.append(float(class_metrics.get("f1", 0.0)))
    macro_f1 = float(metrics.get("macro_f1_present_labels", 0.0))
    if macro_f1 <= 0.0 and supported_f1:
        macro_f1 = sum(supported_f1) / len(supported_f1)
    if macro_f1 <= 0.0:
        macro_f1 = macro_f1_reported
    note_metrics = ((metrics.get("per_class") or {}).get("note") or {})
    note_recall = float(note_metrics.get("recall", 0.0))
    note_support = float(note_metrics.get("support", 0.0))
    confusion = float(metrics.get("ingredient_step_confusion_rate", 1.0))
    thresholds = {
        "macro_f1": macro_f1 >= 0.88,
        "note_recall": (note_recall >= 0.85) if note_support > 0.0 else True,
        "ingredient_step_confusion": confusion <= 0.08,
    }
    thresholds["note_recall_applicable"] = note_support > 0.0
    thresholds["overall"] = (
        thresholds["macro_f1"]
        and thresholds["note_recall"]
        and thresholds["ingredient_step_confusion"]
    )
    return {
        "available": True,
        "macro_f1": macro_f1,
        "macro_f1_reported": float(metrics.get("macro_f1")) if metrics.get("macro_f1") is not None else None,
        "note_recall": float(((metrics.get("per_class") or {}).get("note") or {}).get("recall"))
        if ((metrics.get("per_class") or {}).get("note") or {}).get("recall") is not None
        else None,
        "note_support": note_support,
        "note_recall_applicable": note_support > 0.0,
        "ingredient_step_confusion_rate": float(metrics.get("ingredient_step_confusion_rate"))
        if metrics.get("ingredient_step_confusion_rate") is not None
        else None,
        "prediction_count": int(metrics.get("prediction_count")) if metrics.get("prediction_count") is not None else None,
        "present_label_count": len(supported_f1),
        "thresholds": thresholds,
    }


def _build_metrics_summary(
    eval_metrics: dict[str, Any] | None,
    regression_metrics: dict[str, Any] | None,
    fixed_holdout_metrics: dict[str, Any] | None = None,
) -> dict[str, Any]:
    eval_summary = _line_eval_summary(eval_metrics)
    summary = {
        "macro_f1": eval_summary.get("macro_f1"),
        "macro_f1_reported": eval_summary.get("macro_f1_reported"),
        "note_recall": eval_summary.get("note_recall"),
        "note_support": eval_summary.get("note_support"),
        "note_recall_applicable": eval_summary.get("note_recall_applicable"),
        "ingredient_step_confusion_rate": eval_summary.get("ingredient_step_confusion_rate"),
        "prediction_count": eval_summary.get("prediction_count"),
        "present_label_count": eval_summary.get("present_label_count"),
        "regression_exact_match_rate": float(regression_metrics.get("exact_match_rate"))
        if regression_metrics and regression_metrics.get("exact_match_rate") is not None
        else None,
        "regression_note_leakage_rate": float(regression_metrics.get("note_leakage_rate"))
        if regression_metrics and regression_metrics.get("note_leakage_rate") is not None
        else None,
        "regression_swap_rate": float(regression_metrics.get("ingredient_step_swap_rate"))
        if regression_metrics and regression_metrics.get("ingredient_step_swap_rate") is not None
        else None,
        "regression_fixture_count": int(regression_metrics.get("fixture_count"))
        if regression_metrics and regression_metrics.get("fixture_count") is not None
        else None,
    }
    summary["thresholds"] = _metrics_thresholds(eval_metrics, regression_metrics)
    summary["fixed_holdout"] = _line_eval_summary(fixed_holdout_metrics)
    return summary


class LabHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        # Quiet default logs; UI log area is enough.
        return

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/":
            try:
                body = _read_index_html().encode("utf-8")
            except Exception as exc:  # noqa: BLE001
                _json_response(self, {"error": str(exc)}, status=500)
                return
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        if parsed.path.startswith("/static/"):
            rel = parsed.path[len("/static/") :]
            self._serve_static(rel)
            return

        if parsed.path in {"/cauldron-icon.svg", "/favicon.svg", "/favicon.ico"}:
            self._serve_cauldron_icon()
            return

        if parsed.path == "/api/local_cases":
            self._list_local_cases()
            return

        if parsed.path == "/api/local_case":
            self._get_local_case(parsed.query)
            return

        if parsed.path == "/api/dataset_cases":
            self._list_dataset_cases(parsed.query)
            return

        if parsed.path == "/api/dataset_case":
            self._get_dataset_case(parsed.query)
            return

        if parsed.path == "/api/metrics_history":
            self._get_metrics_history()
            return

        self.send_error(HTTPStatus.NOT_FOUND)

    def do_POST(self) -> None:
        if self.path == "/predict":
            self._predict()
        elif self.path == "/assemble_recipe":
            self._assemble_recipe()
        elif self.path == "/save_local":
            self._save_local()
        elif self.path == "/append_dataset":
            self._append_dataset()
        elif self.path == "/run_metrics":
            self._run_metrics()
        elif self.path == "/retrain_model":
            self._retrain_model()
        else:
            self.send_error(HTTPStatus.NOT_FOUND)

    @staticmethod
    def _doc_case_id(path: Path) -> str:
        name = path.name
        if name.endswith(".doc.json"):
            return name[: -len(".doc.json")]
        return path.stem

    @staticmethod
    def _normalize_case(lines: Any, labels: Any) -> tuple[list[str], list[str]]:
        normalized_lines: list[str] = []
        if isinstance(lines, list):
            normalized_lines = [str(item) for item in lines]

        normalized_labels: list[str] = []
        if isinstance(labels, list):
            for label in labels:
                value = str(label).strip().lower()
                normalized_labels.append(value if value in LABELS else "junk")

        if len(normalized_labels) < len(normalized_lines):
            normalized_labels.extend(["junk"] * (len(normalized_lines) - len(normalized_labels)))
        elif len(normalized_labels) > len(normalized_lines):
            normalized_labels = normalized_labels[: len(normalized_lines)]
        return normalized_lines, normalized_labels

    def _serve_static(self, rel_path: str) -> None:
        try:
            rel = Path(rel_path.strip("/"))
            if not rel.parts:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            if any(part in {"..", ""} for part in rel.parts):
                self.send_error(HTTPStatus.BAD_REQUEST)
                return

            target = (STATIC_DIR / rel).resolve()
            if not target.exists() or not target.is_file():
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            if STATIC_DIR.resolve() not in target.parents:
                self.send_error(HTTPStatus.BAD_REQUEST)
                return

            body = target.read_bytes()
            content_type, _ = mimetypes.guess_type(str(target))
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", content_type or "application/octet-stream")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except Exception:
            self.send_error(HTTPStatus.INTERNAL_SERVER_ERROR)

    def _serve_cauldron_icon(self) -> None:
        icon = _cauldron_icon_path()
        if not icon:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        body = icon.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "image/svg+xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _list_local_cases(self) -> None:
        try:
            LOCAL_CASES_DIR.mkdir(parents=True, exist_ok=True)
            rows: list[dict[str, Any]] = []
            for path in sorted(
                LOCAL_CASES_DIR.glob("*.json"),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            ):
                try:
                    payload = json.loads(path.read_text(encoding="utf-8"))
                except Exception:  # noqa: BLE001
                    continue

                lines, _ = self._normalize_case(payload.get("lines"), payload.get("labels"))
                saved_at = str(payload.get("saved_at") or "")
                if not saved_at:
                    saved_at = datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).isoformat()

                rows.append(
                    {
                        "id": str(payload.get("id") or path.stem),
                        "title": str(payload.get("title") or "Untitled"),
                        "source_type": str(payload.get("source_type") or "manual_edge"),
                        "line_count": len(lines),
                        "saved_at": saved_at,
                        "path": str(path),
                    }
                )

            _json_response(self, {"cases": rows})
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _get_local_case(self, query: str) -> None:
        try:
            params = parse_qs(query)
            case_id = str((params.get("id") or [""])[0]).strip()
            if not case_id:
                raise ValueError("id query parameter is required")
            if "/" in case_id or "\\" in case_id:
                raise ValueError("invalid id")

            path = LOCAL_CASES_DIR / f"{case_id}.json"
            if not path.exists():
                raise FileNotFoundError(f"Local case not found: {path}")

            payload = json.loads(path.read_text(encoding="utf-8"))
            lines, labels = self._normalize_case(payload.get("lines"), payload.get("labels"))

            _json_response(
                self,
                {
                    "id": str(payload.get("id") or case_id),
                    "title": str(payload.get("title") or (lines[0] if lines else "Untitled")),
                    "source_type": str(payload.get("source_type") or "manual_edge"),
                    "save_kind": str(payload.get("save_kind") or "train"),
                    "lines": lines,
                    "labels": labels,
                    "assembled_recipe": payload.get("assembled_recipe"),
                    "saved_at": str(payload.get("saved_at") or ""),
                    "path": str(path),
                },
            )
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _list_dataset_cases(self, query: str) -> None:
        try:
            params = parse_qs(query)
            dataset_dir = Path(str((params.get("dataset_dir") or [DEFAULT_DATASET_DIR])[0])).expanduser().resolve()
            docs_dir = dataset_dir / "documents"
            docs_dir.mkdir(parents=True, exist_ok=True)

            rows: list[dict[str, Any]] = []
            for path in sorted(docs_dir.glob("*.doc.json"), key=lambda p: p.stat().st_mtime, reverse=True):
                try:
                    payload = json.loads(path.read_text(encoding="utf-8"))
                except Exception:  # noqa: BLE001
                    continue

                normalized_lines = payload.get("normalized_lines")
                line_count = len(normalized_lines) if isinstance(normalized_lines, list) else 0
                recipe_target = payload.get("target_recipe") if isinstance(payload.get("target_recipe"), dict) else {}
                title = str(
                    payload.get("title")
                    or recipe_target.get("title")
                    or (normalized_lines[0] if isinstance(normalized_lines, list) and normalized_lines else "Untitled")
                )

                rows.append(
                    {
                        "id": str(payload.get("id") or self._doc_case_id(path)),
                        "title": title,
                        "source_type": str(payload.get("source_type") or "manual_edge"),
                        "line_count": line_count,
                        "updated_at": datetime.fromtimestamp(path.stat().st_mtime, tz=timezone.utc).isoformat(),
                        "document_path": str(path),
                    }
                )

            _json_response(self, {"dataset_dir": str(dataset_dir), "cases": rows})
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _get_dataset_case(self, query: str) -> None:
        try:
            params = parse_qs(query)
            case_id = str((params.get("id") or [""])[0]).strip()
            if not case_id:
                raise ValueError("id query parameter is required")
            if "/" in case_id or "\\" in case_id:
                raise ValueError("invalid id")

            dataset_dir = Path(str((params.get("dataset_dir") or [DEFAULT_DATASET_DIR])[0])).expanduser().resolve()
            doc_path = dataset_dir / "documents" / f"{case_id}.doc.json"
            if not doc_path.exists():
                raise FileNotFoundError(f"Dataset document not found: {doc_path}")

            payload = json.loads(doc_path.read_text(encoding="utf-8"))
            lines, labels = self._normalize_case(payload.get("normalized_lines"), [])
            labels_map: dict[int, str] = {}
            lines_path = dataset_dir / "lines" / f"{case_id}.lines.jsonl"
            if lines_path.exists():
                for raw in lines_path.read_text(encoding="utf-8").splitlines():
                    if not raw.strip():
                        continue
                    row = json.loads(raw)
                    idx = int(row.get("line_index", len(labels_map)))
                    label = str(row.get("label", "junk")).strip().lower()
                    labels_map[idx] = label if label in LABELS else "junk"
            labels = [labels_map.get(i, "junk") for i in range(len(lines))]

            assembled_recipe = _assemble_app_recipe(
                [{"index": idx, "text": line, "label": labels[idx]} for idx, line in enumerate(lines)],
                source_url=str(payload.get("source_url") or ""),
                source_title=str(payload.get("title") or ""),
            )

            recipe_target = payload.get("target_recipe") if isinstance(payload.get("target_recipe"), dict) else {}
            _json_response(
                self,
                {
                    "id": str(payload.get("id") or case_id),
                    "title": str(payload.get("title") or recipe_target.get("title") or (lines[0] if lines else "Untitled")),
                    "source_type": str(payload.get("source_type") or "manual_edge"),
                    "lines": lines,
                    "labels": labels,
                    "assembled_recipe": assembled_recipe,
                    "target_recipe": recipe_target,
                    "dataset_dir": str(dataset_dir),
                    "document_path": str(doc_path),
                    "lines_path": str(lines_path) if lines_path.exists() else None,
                },
            )
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _get_metrics_history(self) -> None:
        try:
            runs = _load_metrics_history()
            _json_response(
                self,
                {
                    "runs": list(reversed(runs)),
                    "run_count": len(runs),
                    "max_runs": METRICS_HISTORY_MAX,
                },
            )
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    @staticmethod
    def _run_process(command: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            check=False,
        )

    @staticmethod
    def _dataset_has_doc_prefix(dataset_dir: Path, prefix: str) -> bool:
        lines_dir = dataset_dir / "lines"
        if not lines_dir.exists():
            return False
        for path in lines_dir.glob(f"{prefix}*.lines.jsonl"):
            if path.is_file():
                return True
        return False

    def _run_metrics_pipeline(
        self,
        *,
        dataset_dir: Path,
        split_path: Path | None = None,
    ) -> dict[str, Any]:
        timestamp_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)
        eval_report_path = LOCAL_TMP_DIR / f"eval_report_{timestamp_id}.json"
        fixed_holdout_report_path = LOCAL_TMP_DIR / f"eval_report_fixed_holdout_{timestamp_id}.json"
        reg_report_path = LOCAL_TMP_DIR / f"reg_report_{timestamp_id}.json"

        eval_cmd = [
            "python3",
            str(EVALUATE_SCRIPT),
            "--model",
            str(ARTIFACT_MODEL),
            "--data-dir",
            str(dataset_dir),
            "--report",
            str(eval_report_path),
            "--exclude-doc-prefix",
            HOLDOUT_DOC_PREFIX,
        ]
        if split_path and split_path.exists():
            eval_cmd.extend(["--split", str(split_path)])

        fixed_holdout_available = self._dataset_has_doc_prefix(dataset_dir, HOLDOUT_DOC_PREFIX)
        fixed_holdout_cmd: list[str] | None = None
        if fixed_holdout_available:
            fixed_holdout_cmd = [
                "python3",
                str(EVALUATE_SCRIPT),
                "--model",
                str(ARTIFACT_MODEL),
                "--data-dir",
                str(dataset_dir),
                "--report",
                str(fixed_holdout_report_path),
                "--include-doc-prefix",
                HOLDOUT_DOC_PREFIX,
                "--skip-threshold-check",
            ]

        reg_cmd = [
            "python3",
            str(REGRESSION_SCRIPT),
            "--model",
            str(ARTIFACT_MODEL),
            "--regression-dir",
            str(dataset_dir / "regression"),
            "--report",
            str(reg_report_path),
        ]

        eval_proc = self._run_process(eval_cmd)
        if fixed_holdout_cmd:
            fixed_holdout_proc = self._run_process(fixed_holdout_cmd)
        else:
            fixed_holdout_proc = subprocess.CompletedProcess(
                args=["fixed_holdout_skipped"],
                returncode=0,
                stdout=f"No fixed holdout docs found for prefix '{HOLDOUT_DOC_PREFIX}'.",
                stderr="",
            )
        reg_proc = self._run_process(reg_cmd)

        eval_metrics = _read_json_file(eval_report_path)
        fixed_holdout_metrics = _read_json_file(fixed_holdout_report_path) if fixed_holdout_available else None
        regression_metrics = _read_json_file(reg_report_path)
        summary = _build_metrics_summary(eval_metrics, regression_metrics, fixed_holdout_metrics)
        ok = (
            eval_proc.returncode == 0
            and reg_proc.returncode == 0
            and fixed_holdout_proc.returncode == 0
            and bool(summary["thresholds"]["overall"])
        )

        return {
            "ok": ok,
            "evaluate": (eval_proc.stdout or "") + ("\n" + eval_proc.stderr if eval_proc.stderr else ""),
            "fixed_holdout_evaluate": (fixed_holdout_proc.stdout or "")
            + ("\n" + fixed_holdout_proc.stderr if fixed_holdout_proc.stderr else ""),
            "regression": (reg_proc.stdout or "") + ("\n" + reg_proc.stderr if reg_proc.stderr else ""),
            "evaluate_rc": eval_proc.returncode,
            "fixed_holdout_evaluate_rc": fixed_holdout_proc.returncode,
            "regression_rc": reg_proc.returncode,
            "metrics": eval_metrics,
            "fixed_holdout_metrics": fixed_holdout_metrics,
            "fixed_holdout_available": fixed_holdout_available,
            "regression_metrics": regression_metrics,
            "summary": summary,
            "eval_report_path": str(eval_report_path),
            "fixed_holdout_eval_report_path": str(fixed_holdout_report_path) if fixed_holdout_available else None,
            "regression_report_path": str(reg_report_path),
        }

    def _predict(self) -> None:
        try:
            payload = _read_json(self)
            mode = str(payload.get("mode", "text"))

            raw_text = ""
            source_preview = ""
            extract_method = mode
            source_url = ""
            source_title = ""
            meta: dict[str, Any] = {}

            if mode == "text":
                raw_text = str(payload.get("text", ""))
                source_preview = "text"
                extract_method = "text_input"
            elif mode == "url":
                url = str(payload.get("url", "")).strip()
                if not url:
                    raise ValueError("URL is required")
                raw_text, meta = _fetch_url_text(url)
                source_preview = url
                source_url = url
                source_title = str(meta.get("title", "")).strip()
                extract_method = str(meta.get("method", "url"))
            elif mode == "image":
                image_data_url = str(payload.get("image_data_url", ""))
                image_name = str(payload.get("image_name", "upload.png"))
                if not image_data_url:
                    raise ValueError("image_data_url is required")
                if "," in image_data_url:
                    b64 = image_data_url.split(",", 1)[1]
                else:
                    b64 = image_data_url
                image_bytes = base64.b64decode(b64)
                raw_text, extract_method = _run_image_ocr(image_bytes, image_name)
                source_preview = image_name
            else:
                raise ValueError(f"Unsupported mode: {mode}")

            lines, truncated = _normalize_lines(raw_text)
            if not lines:
                raise ValueError("No lines extracted from input")

            predictions = PREDICTOR.predict(lines)
            assembled_recipe = _assemble_app_recipe(
                [
                    {
                        "index": int(item.get("index", 0)),
                        "text": str(item.get("text", "")),
                        "label": str(item.get("label", item.get("predicted_label", "junk"))),
                    }
                    for item in predictions
                ],
                source_url=source_url,
                source_title=source_title,
            )
            _json_response(
                self,
                {
                    "lines": predictions,
                    "truncated": truncated,
                    "source_preview": source_preview,
                    "extract_method": extract_method,
                    "assembled_recipe": assembled_recipe,
                },
            )
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _assemble_recipe(self) -> None:
        try:
            payload = _read_json(self)
            rows = payload.get("lines", [])
            if not isinstance(rows, list) or not rows:
                raise ValueError("lines are required")

            normalized_rows: list[dict[str, Any]] = []
            for item in rows:
                label = str(item.get("label", "")).strip().lower()
                text = str(item.get("text", ""))
                if label not in LABELS:
                    raise ValueError(f"invalid label: {label}")
                normalized_rows.append(
                    {
                        "index": int(item.get("index", 0)),
                        "text": text,
                        "label": label,
                    }
                )

            recipe = _assemble_app_recipe(
                normalized_rows,
                source_url=str(payload.get("source_url", "")).strip(),
                source_title=str(payload.get("source_title", "")).strip(),
            )
            _json_response(self, {"recipe": recipe})
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _save_local(self) -> None:
        try:
            payload = _read_json(self)
            case_id = str(payload.get("id", "")).strip()
            if not case_id:
                raise ValueError("id is required")
            source_type = str(payload.get("source_type", "manual_edge") or "manual_edge").strip()
            save_kind = _normalized_save_kind(payload.get("save_kind"))
            case_id = _effective_case_id(case_id, source_type, save_kind)

            lines = payload.get("lines", [])
            if not isinstance(lines, list) or not lines:
                raise ValueError("lines are required")

            labels = []
            plain_lines = []
            for item in lines:
                text = str(item["text"])
                label = str(item["label"])
                if label not in LABELS:
                    raise ValueError(f"invalid label: {label}")
                plain_lines.append(text)
                labels.append(label)

            out = {
                "id": case_id,
                "source_type": source_type,
                "save_kind": save_kind,
                "title": str(payload.get("title") or plain_lines[0]),
                "lines": plain_lines,
                "labels": labels,
                "assembled_recipe": payload.get("assembled_recipe"),
                "saved_at": datetime.now(timezone.utc).isoformat(),
            }

            LOCAL_CASES_DIR.mkdir(parents=True, exist_ok=True)
            path = LOCAL_CASES_DIR / f"{case_id}.json"
            path.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")

            _json_response(self, {"id": case_id, "path": str(path)})
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _append_dataset(self) -> None:
        try:
            payload = _read_json(self)
            dataset_dir = Path(str(payload.get("dataset_dir") or DEFAULT_DATASET_DIR)).expanduser().resolve()

            case_id = str(payload.get("id", "")).strip()
            if not case_id:
                raise ValueError("id is required")
            source_type = str(payload.get("source_type", "manual_edge") or "manual_edge").strip()
            save_kind = _normalized_save_kind(payload.get("save_kind"))
            case_id = _effective_case_id(case_id, source_type, save_kind)

            lines = payload.get("lines", [])
            if not isinstance(lines, list) or not lines:
                raise ValueError("lines are required")

            correction = {
                "id": case_id,
                "source_type": source_type,
                "title": str(payload.get("title") or lines[0].get("text", "Untitled")),
                "lines": [str(item["text"]) for item in lines],
                "labels": [str(item["label"]) for item in lines],
            }

            for label in correction["labels"]:
                if label not in LABELS:
                    raise ValueError(f"invalid label: {label}")

            LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)
            tmp = LOCAL_TMP_DIR / f"{case_id}.json"
            tmp.write_text(json.dumps(correction, indent=2) + "\n", encoding="utf-8")

            proc = subprocess.run(
                [
                    "python3",
                    str(EXPORT_SCRIPT),
                    "--input",
                    str(tmp),
                    "--out-dir",
                    str(dataset_dir),
                ],
                capture_output=True,
                text=True,
                check=False,
            )

            status = 200 if proc.returncode == 0 else 400
            _json_response(
                self,
                {
                    "id": case_id,
                    "stdout": proc.stdout,
                    "stderr": proc.stderr,
                    "returncode": proc.returncode,
                },
                status=status,
            )
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _run_metrics(self) -> None:
        try:
            payload = _read_json(self)
            dataset_dir = Path(str(payload.get("dataset_dir") or DEFAULT_DATASET_DIR)).expanduser().resolve()
            pipeline = self._run_metrics_pipeline(dataset_dir=dataset_dir, split_path=ARTIFACT_SPLIT)

            run_entry = {
                "id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "action": "metrics",
                "dataset_dir": str(dataset_dir),
                "model_path": str(ARTIFACT_MODEL),
                "success": bool(pipeline["ok"]),
                "evaluate_rc": int(pipeline["evaluate_rc"]),
                "fixed_holdout_evaluate_rc": int(pipeline["fixed_holdout_evaluate_rc"]),
                "regression_rc": int(pipeline["regression_rc"]),
                "summary": pipeline["summary"],
            }
            _append_metrics_history(run_entry)

            status = 200 if pipeline["ok"] else 400
            payload_out = dict(pipeline)
            payload_out["action"] = "metrics"
            payload_out["timestamp"] = run_entry["timestamp"]
            payload_out["dataset_dir"] = str(dataset_dir)
            payload_out["history_entry"] = run_entry
            _json_response(self, payload_out, status=status)
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)

    def _retrain_model(self) -> None:
        try:
            payload = _read_json(self)
            dataset_dir = Path(str(payload.get("dataset_dir") or DEFAULT_DATASET_DIR)).expanduser().resolve()
            backup_stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
            LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)
            backup_model_path: Path | None = None
            backup_split_path: Path | None = None

            if ARTIFACT_MODEL.exists():
                backup_model_path = LOCAL_TMP_DIR / f"line_classifier_backup_{backup_stamp}.pkl"
                shutil.copy2(ARTIFACT_MODEL, backup_model_path)
            if ARTIFACT_SPLIT.exists():
                backup_split_path = LOCAL_TMP_DIR / f"split_backup_{backup_stamp}.json"
                shutil.copy2(ARTIFACT_SPLIT, backup_split_path)

            validate_proc = self._run_process(
                [
                    "python3",
                    str(VALIDATE_SCRIPT),
                    "--data-dir",
                    str(dataset_dir),
                ]
            )
            if validate_proc.returncode != 0:
                run_entry = {
                    "id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "action": "retrain",
                    "dataset_dir": str(dataset_dir),
                    "model_path": str(ARTIFACT_MODEL),
                    "success": False,
                    "validate_rc": int(validate_proc.returncode),
                    "summary": {"thresholds": {"overall": False}},
                }
                _append_metrics_history(run_entry)
                _json_response(
                    self,
                    {
                        "ok": False,
                        "validate_rc": validate_proc.returncode,
                        "validate": (validate_proc.stdout or "") + ("\n" + validate_proc.stderr if validate_proc.stderr else ""),
                        "error": "Dataset validation failed",
                        "history_entry": run_entry,
                    },
                    status=400,
                )
                return

            train_proc = self._run_process(
                [
                    "python3",
                    str(TRAIN_SCRIPT),
                    "--data-dir",
                    str(dataset_dir),
                    "--out-dir",
                    str(ARTIFACT_MODEL.parent),
                    "--exclude-doc-prefix",
                    HOLDOUT_DOC_PREFIX,
                ]
            )
            if train_proc.returncode != 0:
                run_entry = {
                    "id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "action": "retrain",
                    "dataset_dir": str(dataset_dir),
                    "model_path": str(ARTIFACT_MODEL),
                    "success": False,
                    "validate_rc": int(validate_proc.returncode),
                    "train_rc": int(train_proc.returncode),
                    "summary": {"thresholds": {"overall": False}},
                }
                _append_metrics_history(run_entry)
                _json_response(
                    self,
                    {
                        "ok": False,
                        "validate_rc": validate_proc.returncode,
                        "train_rc": train_proc.returncode,
                        "validate": (validate_proc.stdout or "") + ("\n" + validate_proc.stderr if validate_proc.stderr else ""),
                        "train": (train_proc.stdout or "") + ("\n" + train_proc.stderr if train_proc.stderr else ""),
                        "error": "Model training failed",
                        "history_entry": run_entry,
                    },
                    status=400,
                )
                return

            metrics = self._run_metrics_pipeline(dataset_dir=dataset_dir, split_path=ARTIFACT_SPLIT)
            rolled_back = False
            rollback_error = ""
            reload_error = ""
            reloaded = False

            def restore_backups() -> bool:
                nonlocal rollback_error
                restored_any = False
                try:
                    if backup_model_path and backup_model_path.exists():
                        shutil.copy2(backup_model_path, ARTIFACT_MODEL)
                        restored_any = True
                    if backup_split_path and backup_split_path.exists():
                        shutil.copy2(backup_split_path, ARTIFACT_SPLIT)
                    return restored_any
                except Exception as exc:  # noqa: BLE001
                    rollback_error = str(exc)
                    return False

            if metrics["ok"]:
                export_proc = self._run_process(
                    [
                        "python3",
                        str(EXPORT_COREML_SCRIPT),
                        "--model",
                        str(ARTIFACT_MODEL),
                        "--out",
                        str(BUNDLED_MODEL_OUT),
                    ]
                )
                if export_proc.returncode == 0:
                    try:
                        PREDICTOR.reload()
                        reloaded = True
                    except Exception as exc:  # noqa: BLE001
                        reload_error = str(exc)
                else:
                    rolled_back = restore_backups()
                    if rolled_back:
                        try:
                            PREDICTOR.reload()
                            reloaded = True
                        except Exception as exc:  # noqa: BLE001
                            reload_error = str(exc)
            else:
                export_proc = subprocess.CompletedProcess(
                    args=["export_skipped_due_to_failed_thresholds"],
                    returncode=0,
                    stdout="Skipped export because metric thresholds failed.",
                    stderr="",
                )
                rolled_back = restore_backups()
                if rolled_back:
                    try:
                        PREDICTOR.reload()
                        reloaded = True
                    except Exception as exc:  # noqa: BLE001
                        reload_error = str(exc)

            success = (
                validate_proc.returncode == 0
                and train_proc.returncode == 0
                and export_proc.returncode == 0
                and bool(metrics["ok"])
                and reloaded
                and not rolled_back
            )

            run_entry = {
                "id": datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "action": "retrain",
                "dataset_dir": str(dataset_dir),
                "model_path": str(ARTIFACT_MODEL),
                "success": success,
                "validate_rc": int(validate_proc.returncode),
                "train_rc": int(train_proc.returncode),
                "evaluate_rc": int(metrics["evaluate_rc"]),
                "fixed_holdout_evaluate_rc": int(metrics["fixed_holdout_evaluate_rc"]),
                "regression_rc": int(metrics["regression_rc"]),
                "export_rc": int(export_proc.returncode),
                "reloaded": reloaded,
                "rolled_back": rolled_back,
                "summary": metrics["summary"],
            }
            _append_metrics_history(run_entry)

            response_payload = {
                "ok": success,
                "action": "retrain",
                "timestamp": run_entry["timestamp"],
                "dataset_dir": str(dataset_dir),
                "model_path": str(ARTIFACT_MODEL),
                "bundled_model_out": str(BUNDLED_MODEL_OUT.with_suffix(".mlmodelc")),
                "validate_rc": validate_proc.returncode,
                "validate": (validate_proc.stdout or "") + ("\n" + validate_proc.stderr if validate_proc.stderr else ""),
                "train_rc": train_proc.returncode,
                "train": (train_proc.stdout or "") + ("\n" + train_proc.stderr if train_proc.stderr else ""),
                "evaluate_rc": metrics["evaluate_rc"],
                "evaluate": metrics["evaluate"],
                "fixed_holdout_evaluate_rc": metrics["fixed_holdout_evaluate_rc"],
                "fixed_holdout_evaluate": metrics["fixed_holdout_evaluate"],
                "regression_rc": metrics["regression_rc"],
                "regression": metrics["regression"],
                "metrics": metrics["metrics"],
                "fixed_holdout_metrics": metrics["fixed_holdout_metrics"],
                "fixed_holdout_available": metrics["fixed_holdout_available"],
                "regression_metrics": metrics["regression_metrics"],
                "summary": metrics["summary"],
                "eval_report_path": metrics["eval_report_path"],
                "fixed_holdout_eval_report_path": metrics["fixed_holdout_eval_report_path"],
                "regression_report_path": metrics["regression_report_path"],
                "export_rc": export_proc.returncode,
                "export": (export_proc.stdout or "") + ("\n" + export_proc.stderr if export_proc.stderr else ""),
                "reloaded": reloaded,
                "reload_error": reload_error,
                "rolled_back": rolled_back,
                "rollback_error": rollback_error,
                "history_entry": run_entry,
            }
            status = 200 if success else 400
            _json_response(self, response_payload, status=status)
        except Exception as exc:  # noqa: BLE001
            _json_response(self, {"error": str(exc)}, status=400)
