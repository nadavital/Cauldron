#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class SwiftPythonParityReportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.tool_dir = self.repo_root / "tools" / "recipe_schema_model"
        self.lines_dir = self.repo_root / "CauldronTests" / "Fixtures" / "RecipeSchema" / "lines"
        self.docs_dir = self.repo_root / "CauldronTests" / "Fixtures" / "RecipeSchema" / "documents"

    def run_script(self, script: str, *args: str) -> subprocess.CompletedProcess[str]:
        cmd = ["python3", str(self.tool_dir / script), *args]
        return subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)

    def test_label_parity_report_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            out_path = Path(temp_dir) / "parity_labels.json"
            result = self.run_script(
                "compare_swift_python_labels.py",
                "--fixtures",
                str(self.lines_dir),
                "--out",
                str(out_path),
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + "\n" + result.stderr)
            self.assertTrue(out_path.exists())

            payload = json.loads(out_path.read_text(encoding="utf-8"))
            for key in [
                "report_type",
                "generated_at_utc",
                "fixtures_dir",
                "total_fixtures",
                "total_lines",
                "mismatch_lines",
                "mismatch_rate",
                "threshold",
                "passes_threshold",
                "top_confusions",
                "fixtures",
            ]:
                self.assertIn(key, payload)

            self.assertEqual(payload["report_type"], "swift_python_label_parity")
            self.assertGreater(payload["total_fixtures"], 0)
            self.assertGreater(payload["total_lines"], 0)
            self.assertIsInstance(payload["fixtures"], list)

    def test_assembly_parity_report_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            out_path = Path(temp_dir) / "parity_assembly.json"
            result = self.run_script(
                "compare_swift_python_assembly.py",
                "--fixtures",
                str(self.docs_dir),
                "--out",
                str(out_path),
            )
            self.assertEqual(result.returncode, 0, msg=result.stdout + "\n" + result.stderr)
            self.assertTrue(out_path.exists())

            payload = json.loads(out_path.read_text(encoding="utf-8"))
            for key in [
                "report_type",
                "generated_at_utc",
                "fixtures_dir",
                "total_fixtures",
                "mismatch_docs",
                "ingredient_mismatch_docs",
                "step_mismatch_docs",
                "note_mismatch_docs",
                "max_mismatch_docs",
                "passes_threshold",
                "fixtures",
            ]:
                self.assertIn(key, payload)

            self.assertEqual(payload["report_type"], "swift_python_assembly_parity")
            self.assertGreater(payload["total_fixtures"], 0)
            self.assertIsInstance(payload["fixtures"], list)


if __name__ == "__main__":
    unittest.main()
