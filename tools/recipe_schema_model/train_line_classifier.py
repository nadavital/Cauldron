#!/usr/bin/env python3
"""Train baseline recipe line classifier."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from schema_model import (
    NGramNaiveBayesClassifier,
    load_line_rows,
    save_pickle,
    split_docs_for_holdout,
)


def main() -> int:
    parser = argparse.ArgumentParser(description="Train recipe line classifier")
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--holdout-ratio", type=float, default=0.25)
    parser.add_argument(
        "--include-doc-prefix",
        action="append",
        default=[],
        help="Only include docs whose id starts with this prefix (repeatable)",
    )
    parser.add_argument(
        "--exclude-doc-prefix",
        action="append",
        default=["holdout_"],
        help="Exclude docs whose id starts with this prefix (repeatable)",
    )
    args = parser.parse_args()

    rows = load_line_rows(
        args.data_dir,
        include_doc_prefixes=args.include_doc_prefix or None,
        exclude_doc_prefixes=args.exclude_doc_prefix or None,
    )
    doc_ids = {row.doc_id for row in rows}
    train_docs, holdout_docs = split_docs_for_holdout(doc_ids, holdout_ratio=args.holdout_ratio)
    train_rows = [row for row in rows if row.doc_id in train_docs]
    holdout_rows = [row for row in rows if row.doc_id in holdout_docs]

    if not train_rows:
        raise SystemExit("No training rows found after split")
    if not holdout_rows:
        raise SystemExit("No holdout rows found after split")

    model = NGramNaiveBayesClassifier().fit(train_rows)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    model_path = args.out_dir / "line_classifier.pkl"
    split_path = args.out_dir / "split.json"

    save_pickle(model_path, model)
    split_path.write_text(
        json.dumps(
            {
                "train_docs": sorted(train_docs),
                "holdout_docs": sorted(holdout_docs),
                "holdout_examples": [
                    {"doc_id": row.doc_id, "line_index": row.line_index}
                    for row in holdout_rows
                ],
                "train_rows": len(train_rows),
                "holdout_rows": len(holdout_rows),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"TRAINING COMPLETE")
    print(f"Model: {model_path}")
    print(f"Split: {split_path}")
    print(f"Train docs: {len(train_docs)} | Holdout docs: {len(holdout_docs)}")
    print(f"Train rows: {len(train_rows)} | Holdout rows: {len(holdout_rows)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
