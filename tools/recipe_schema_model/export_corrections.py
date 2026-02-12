#!/usr/bin/env python3
"""Convert parser correction notes into training examples.

Input format (JSON):
{
  "id": "case_name",
  "source_type": "ocr_failure",
  "title": "Recipe Title",
  "lines": ["..."],
  "labels": ["title", "ingredient", "..."]
}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from schema_model import LABELS


def main() -> int:
    parser = argparse.ArgumentParser(description="Export correction payload to dataset fixture files")
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    payload = json.loads(args.input.read_text(encoding="utf-8"))

    case_id = str(payload["id"])
    source_type = str(payload.get("source_type", "manual_edge"))
    lines = list(payload["lines"])
    labels = list(payload["labels"])

    if len(lines) != len(labels):
        raise SystemExit("lines and labels must have equal length")

    invalid = [label for label in labels if label not in LABELS]
    if invalid:
        raise SystemExit(f"invalid labels: {invalid}")

    docs_dir = args.out_dir / "documents"
    lines_dir = args.out_dir / "lines"
    docs_dir.mkdir(parents=True, exist_ok=True)
    lines_dir.mkdir(parents=True, exist_ok=True)

    document_payload = {
        "id": case_id,
        "source_type": source_type,
        "normalized_lines": lines,
        "target_recipe": {
            "title": payload.get("title", lines[0] if lines else "Untitled"),
            "ingredients": [line for line, label in zip(lines, labels) if label == "ingredient"],
            "steps": [line for line, label in zip(lines, labels) if label == "step"],
            "notes": [line for line, label in zip(lines, labels) if label == "note"],
        },
    }

    doc_path = docs_dir / f"{case_id}.doc.json"
    lines_path = lines_dir / f"{case_id}.lines.jsonl"

    doc_path.write_text(json.dumps(document_payload, indent=2) + "\n", encoding="utf-8")

    with lines_path.open("w", encoding="utf-8") as handle:
        for index, (line, label) in enumerate(zip(lines, labels)):
            handle.write(
                json.dumps(
                    {
                        "line_index": index,
                        "text": line,
                        "label": label,
                    },
                    ensure_ascii=True,
                )
                + "\n"
            )

    print(f"WROTE {doc_path}")
    print(f"WROTE {lines_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
