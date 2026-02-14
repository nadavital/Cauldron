#!/usr/bin/env python3
"""Compare Python lab predictor labels against Swift classifier labels."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[2]
LAB_DIR = REPO_ROOT / "tools" / "recipe_schema_lab"
if str(LAB_DIR) not in sys.path:
    sys.path.insert(0, str(LAB_DIR))

from lab_predictor import PREDICTOR  # noqa: E402

from swift_pipeline_bridge import run_swift_pipeline  # noqa: E402


def _load_lines(line_file: Path) -> list[str]:
    rows = [json.loads(line) for line in line_file.read_text(encoding="utf-8").splitlines() if line.strip()]
    rows.sort(key=lambda row: int(row.get("line_index", 0)))
    return [str(row["text"]) for row in rows]


def _compare_file(line_file: Path) -> dict[str, Any]:
    lines = _load_lines(line_file)
    py_labels = [str(item["label"]) for item in PREDICTOR.predict(lines)]
    swift = run_swift_pipeline(lines, repo_root=REPO_ROOT)
    sw_labels = [str(label) for label in swift["labels"]]

    mismatches: list[dict[str, Any]] = []
    confusions: Counter[tuple[str, str]] = Counter()
    for idx, (line, py_label, sw_label) in enumerate(zip(lines, py_labels, sw_labels)):
        if py_label == sw_label:
            continue
        confusions[(py_label, sw_label)] += 1
        mismatches.append(
            {
                "line_index": idx,
                "text": line,
                "python_label": py_label,
                "swift_label": sw_label,
            }
        )

    return {
        "fixture": line_file.name,
        "line_count": len(lines),
        "mismatch_count": len(mismatches),
        "mismatch_rate": (len(mismatches) / len(lines)) if lines else 0.0,
        "mismatches": mismatches,
        "confusions": [
            {"python_label": py_label, "swift_label": sw_label, "count": count}
            for (py_label, sw_label), count in confusions.most_common()
        ],
    }


def build_report(fixtures_dir: Path, threshold: float) -> dict[str, Any]:
    files = sorted(fixtures_dir.glob("*.lines.jsonl"))
    per_fixture = [_compare_file(path) for path in files]

    total_lines = sum(item["line_count"] for item in per_fixture)
    mismatch_lines = sum(item["mismatch_count"] for item in per_fixture)
    mismatch_rate = (mismatch_lines / total_lines) if total_lines else 0.0

    confusion_totals: Counter[tuple[str, str]] = Counter()
    for item in per_fixture:
        for confusion in item["confusions"]:
            confusion_totals[(confusion["python_label"], confusion["swift_label"])] += int(confusion["count"])

    return {
        "report_type": "swift_python_label_parity",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "fixtures_dir": str(fixtures_dir),
        "total_fixtures": len(per_fixture),
        "total_lines": total_lines,
        "mismatch_lines": mismatch_lines,
        "mismatch_rate": mismatch_rate,
        "threshold": threshold,
        "passes_threshold": mismatch_rate <= threshold,
        "top_confusions": [
            {"python_label": py, "swift_label": sw, "count": count}
            for (py, sw), count in confusion_totals.most_common(20)
        ],
        "fixtures": per_fixture,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare Swift and Python labels across fixture lines")
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=REPO_ROOT / "CauldronTests" / "Fixtures" / "RecipeSchema" / "lines",
        help="Directory containing *.lines.jsonl fixtures",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "tools" / "recipe_schema_model" / "artifacts" / "parity_labels.json",
        help="Output report path",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.005,
        help="Mismatch rate threshold used for gate mode",
    )
    parser.add_argument(
        "--gate",
        action="store_true",
        help="Exit non-zero when mismatch_rate exceeds threshold",
    )
    args = parser.parse_args()

    report = build_report(args.fixtures.resolve(), args.threshold)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        f"Label parity: {report['mismatch_lines']}/{report['total_lines']} "
        f"({report['mismatch_rate']:.4%}) threshold={report['threshold']:.4%}"
    )
    print(f"Wrote: {args.out}")

    if args.gate and not report["passes_threshold"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
