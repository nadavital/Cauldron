#!/usr/bin/env python3
"""Build materialized training table from fixture files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from schema_model import extract_features, load_line_rows, normalize_for_features


def main() -> int:
    parser = argparse.ArgumentParser(description="Build recipe schema model training table")
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="Output JSONL file")
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
    args.out.parent.mkdir(parents=True, exist_ok=True)

    with args.out.open("w", encoding="utf-8") as handle:
        for row in rows:
            features = extract_features(row.text)
            payload = {
                "doc_id": row.doc_id,
                "line_index": row.line_index,
                "text": row.text,
                "normalized_text": normalize_for_features(row.text),
                "label": row.label,
                "feature_count": sum(features.values()),
                "feature_preview": sorted(features.keys())[:40],
            }
            handle.write(json.dumps(payload, ensure_ascii=True) + "\n")

    print(f"WROTE TRAINING TABLE: {args.out}")
    print(f"Rows: {len(rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
