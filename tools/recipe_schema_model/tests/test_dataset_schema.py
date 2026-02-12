#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

from schema_model import LABELS, validate_dataset


class DatasetSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.data_dir = self.repo_root / "CauldronTests" / "Fixtures" / "RecipeSchema"

    def test_dataset_is_valid(self) -> None:
        result = validate_dataset(self.data_dir)
        self.assertTrue(result.is_valid, msg="\n".join(result.errors))
        for label in LABELS:
            self.assertIn(label, result.label_counts)

    def test_validator_fails_on_invalid_label(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            shutil.copytree(self.data_dir, temp_path / "RecipeSchema")
            copied_dir = temp_path / "RecipeSchema"

            line_file = copied_dir / "lines" / "avocado_toast.lines.jsonl"
            lines = line_file.read_text(encoding="utf-8").splitlines()
            payload = json.loads(lines[1])
            payload["label"] = "bad_label"
            lines[1] = json.dumps(payload)
            line_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

            result = validate_dataset(copied_dir)
            self.assertFalse(result.is_valid)
            self.assertTrue(any("Invalid label" in error for error in result.errors))

    def test_validator_fails_on_line_count_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            shutil.copytree(self.data_dir, temp_path / "RecipeSchema")
            copied_dir = temp_path / "RecipeSchema"

            doc_file = copied_dir / "documents" / "garlic_shrimp.doc.json"
            payload = json.loads(doc_file.read_text(encoding="utf-8"))
            payload["normalized_lines"] = payload["normalized_lines"][:-1]
            doc_file.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")

            result = validate_dataset(copied_dir)
            self.assertFalse(result.is_valid)
            self.assertTrue(any("normalized_lines" in error for error in result.errors))


if __name__ == "__main__":
    unittest.main()
