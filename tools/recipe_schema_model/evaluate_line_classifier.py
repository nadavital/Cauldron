#!/usr/bin/env python3
"""Evaluate recipe line classifier against held-out fixtures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from schema_model import LABELS, compute_metrics, load_line_rows, load_pickle, run_predictions


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate recipe line classifier")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--split", type=Path, default=None, help="Optional split.json from training")
    parser.add_argument("--report", type=Path, default=None, help="Optional output JSON report")
    parser.add_argument(
        "--include-doc-prefix",
        action="append",
        default=[],
        help="Only include docs whose id starts with this prefix (repeatable)",
    )
    parser.add_argument(
        "--exclude-doc-prefix",
        action="append",
        default=[],
        help="Exclude docs whose id starts with this prefix (repeatable)",
    )
    parser.add_argument(
        "--skip-threshold-check",
        action="store_true",
        help="Always return success if evaluation ran, even if thresholds fail",
    )
    args = parser.parse_args()

    model = load_pickle(args.model)
    rows = load_line_rows(
        args.data_dir,
        include_doc_prefixes=args.include_doc_prefix or None,
        exclude_doc_prefixes=args.exclude_doc_prefix or None,
    )
    evaluation_keys = None

    if args.split is not None and args.split.exists():
        split_payload = json.loads(args.split.read_text(encoding="utf-8"))
        holdout_examples = split_payload.get("holdout_examples", [])
        if holdout_examples:
            evaluation_keys = {(item["doc_id"], int(item["line_index"])) for item in holdout_examples}
        else:
            holdout_docs = set(split_payload.get("holdout_docs", []))
            rows = [row for row in rows if row.doc_id in holdout_docs]

    if not rows:
        raise SystemExit("No evaluation rows found")

    predictions = run_predictions(model, rows)
    if evaluation_keys is not None:
        predictions = [
            prediction
            for prediction in predictions
            if (prediction.doc_id, prediction.line_index) in evaluation_keys
        ]
    metrics = compute_metrics(predictions)

    print("EVALUATION REPORT")
    print(f"Prediction count: {metrics['prediction_count']}")
    print(f"Macro F1: {metrics['macro_f1']:.4f}")
    if metrics.get("macro_f1_present_labels") is not None:
        print(f"Macro F1 (present labels): {float(metrics['macro_f1_present_labels']):.4f}")
    print(f"Ingredient-vs-step confusion: {metrics['ingredient_step_confusion_rate']:.4%}")

    for label in LABELS:
        class_metrics = metrics["per_class"][label]
        print(
            f"Class {label:>10}: "
            f"P={class_metrics['precision']:.3f} "
            f"R={class_metrics['recall']:.3f} "
            f"F1={class_metrics['f1']:.3f} "
            f"support={int(class_metrics['support'])}"
        )

    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf-8")
        print(f"Report JSON: {args.report}")

    macro_value = float(metrics.get("macro_f1_present_labels", metrics["macro_f1"]))
    note_metrics = metrics["per_class"]["note"]
    note_support = float(note_metrics.get("support", 0.0))
    note_recall = float(note_metrics.get("recall", 0.0))
    macro_ok = macro_value >= 0.88
    note_recall_ok = (note_recall >= 0.85) if note_support > 0.0 else True
    confusion_ok = metrics["ingredient_step_confusion_rate"] <= 0.08

    print("Thresholds:")
    print(f"  macro_f1>=0.88: {'PASS' if macro_ok else 'FAIL'}")
    if note_support > 0.0:
        print(f"  note_recall>=0.85: {'PASS' if note_recall_ok else 'FAIL'}")
    else:
        print("  note_recall>=0.85: N/A (support=0)")
    print(f"  ingredient_step_confusion<=0.08: {'PASS' if confusion_ok else 'FAIL'}")

    if args.skip_threshold_check:
        print("Threshold enforcement: SKIPPED")
        return 0
    return 0 if (macro_ok and note_recall_ok and confusion_ok) else 1


if __name__ == "__main__":
    raise SystemExit(main())
