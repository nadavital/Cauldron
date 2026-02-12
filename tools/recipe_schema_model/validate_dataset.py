#!/usr/bin/env python3
"""Validate recipe schema training dataset fixtures."""

from __future__ import annotations

import argparse
from pathlib import Path

from schema_model import LABELS, validate_dataset


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate recipe schema model dataset")
    parser.add_argument("--data-dir", type=Path, required=True, help="Path to RecipeSchema fixture root")
    args = parser.parse_args()

    result = validate_dataset(args.data_dir)

    print("DATASET VALIDATION REPORT")
    print(f"Data dir: {args.data_dir}")
    print("Per-label counts:")
    for label in LABELS:
        print(f"  {label}: {result.label_counts.get(label, 0)}")

    print("Source counts:")
    for source_type, count in result.source_counts.items():
        print(f"  {source_type}: {count}")

    if result.is_valid:
        print("VALIDATION PASSED")
        return 0

    print("VALIDATION FAILED")
    for error in result.errors:
        print(f"  - {error}")

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
