#!/usr/bin/env python3
"""Compare Python lab assembled recipe shape against Swift pipeline shape."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True

REPO_ROOT = Path(__file__).resolve().parents[2]
LAB_DIR = REPO_ROOT / "tools" / "recipe_schema_lab"
if str(LAB_DIR) not in sys.path:
    sys.path.insert(0, str(LAB_DIR))

from lab_predictor import PREDICTOR  # noqa: E402
from lab_recipe import _assemble_app_recipe  # noqa: E402

from swift_pipeline_bridge import run_swift_pipeline  # noqa: E402


def _note_count(value: Any) -> int:
    if value is None:
        return 0
    if isinstance(value, str):
        return len([line for line in value.splitlines() if line.strip()])
    if isinstance(value, list):
        return len([line for line in value if str(line).strip()])
    return 0


def _load_document(doc_file: Path) -> list[str]:
    payload = json.loads(doc_file.read_text(encoding="utf-8"))
    lines = payload.get("normalized_lines") or []
    return [str(line) for line in lines]


def _compare_file(doc_file: Path) -> dict[str, Any]:
    lines = _load_document(doc_file)

    py_rows = PREDICTOR.predict(lines)
    py_recipe = _assemble_app_recipe(
        [
            {
                "index": int(item.get("index", 0)),
                "text": str(item.get("text", "")),
                "label": str(item.get("label", item.get("predicted_label", "junk"))),
            }
            for item in py_rows
        ]
    )

    swift = run_swift_pipeline(lines, repo_root=REPO_ROOT)

    py_counts = {
        "ingredients": len(py_recipe.get("ingredients") or []),
        "steps": len(py_recipe.get("steps") or []),
        "notes": _note_count(py_recipe.get("notes")),
    }
    sw_counts = {
        "ingredients": len(swift.get("ingredients") or []),
        "steps": len(swift.get("steps") or []),
        "notes": len(swift.get("notes") or []),
    }

    deltas = {
        "ingredients": py_counts["ingredients"] - sw_counts["ingredients"],
        "steps": py_counts["steps"] - sw_counts["steps"],
        "notes": py_counts["notes"] - sw_counts["notes"],
    }

    return {
        "fixture": doc_file.name,
        "line_count": len(lines),
        "python_counts": py_counts,
        "swift_counts": sw_counts,
        "count_deltas": deltas,
        "has_count_mismatch": any(value != 0 for value in deltas.values()),
    }


def build_report(fixtures_dir: Path, max_mismatch_docs: int) -> dict[str, Any]:
    files = sorted(fixtures_dir.glob("*.doc.json"))
    per_fixture = [_compare_file(path) for path in files]

    mismatch_docs = [item for item in per_fixture if item["has_count_mismatch"]]
    ingredient_mismatch_docs = [item for item in per_fixture if item["count_deltas"]["ingredients"] != 0]
    step_mismatch_docs = [item for item in per_fixture if item["count_deltas"]["steps"] != 0]
    note_mismatch_docs = [item for item in per_fixture if item["count_deltas"]["notes"] != 0]

    return {
        "report_type": "swift_python_assembly_parity",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "fixtures_dir": str(fixtures_dir),
        "total_fixtures": len(per_fixture),
        "mismatch_docs": len(mismatch_docs),
        "ingredient_mismatch_docs": len(ingredient_mismatch_docs),
        "step_mismatch_docs": len(step_mismatch_docs),
        "note_mismatch_docs": len(note_mismatch_docs),
        "max_mismatch_docs": max_mismatch_docs,
        "passes_threshold": len(mismatch_docs) <= max_mismatch_docs,
        "fixtures": per_fixture,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Compare Swift and Python assembly shape across doc fixtures")
    parser.add_argument(
        "--fixtures",
        type=Path,
        default=REPO_ROOT / "CauldronTests" / "Fixtures" / "RecipeSchema" / "documents",
        help="Directory containing *.doc.json fixtures",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=REPO_ROOT / "tools" / "recipe_schema_model" / "artifacts" / "parity_assembly.json",
        help="Output report path",
    )
    parser.add_argument(
        "--max-mismatch-docs",
        type=int,
        default=2,
        help="Maximum docs with count mismatch allowed in gate mode",
    )
    parser.add_argument(
        "--gate",
        action="store_true",
        help="Exit non-zero when mismatch_docs exceeds threshold",
    )
    args = parser.parse_args()

    report = build_report(args.fixtures.resolve(), args.max_mismatch_docs)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    print(
        f"Assembly parity: {report['mismatch_docs']}/{report['total_fixtures']} docs "
        f"(ingredient={report['ingredient_mismatch_docs']}, "
        f"step={report['step_mismatch_docs']}, note={report['note_mismatch_docs']})"
    )
    print(f"Wrote: {args.out}")

    if args.gate and not report["passes_threshold"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
