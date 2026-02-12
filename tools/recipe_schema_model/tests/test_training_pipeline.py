#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

from schema_model import LABELS


class TrainingPipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.tool_dir = self.repo_root / "tools" / "recipe_schema_model"
        self.data_dir = self.repo_root / "CauldronTests" / "Fixtures" / "RecipeSchema"

    def run_script(self, script: str, *args: str) -> subprocess.CompletedProcess[str]:
        cmd = ["python3", str(self.tool_dir / script), *args]
        return subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)

    def test_training_and_evaluation_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            out_dir = Path(temp_dir) / "artifacts"
            report = out_dir / "eval_report.json"

            train = self.run_script(
                "train_line_classifier.py",
                "--data-dir", str(self.data_dir),
                "--out-dir", str(out_dir),
            )
            self.assertEqual(train.returncode, 0, msg=train.stdout + "\n" + train.stderr)

            model_path = out_dir / "line_classifier.pkl"
            split_path = out_dir / "split.json"
            self.assertTrue(model_path.exists())
            self.assertTrue(split_path.exists())

            eval_result = self.run_script(
                "evaluate_line_classifier.py",
                "--model", str(model_path),
                "--data-dir", str(self.data_dir),
                "--split", str(split_path),
                "--report", str(report),
                "--skip-threshold-check",
            )
            self.assertEqual(eval_result.returncode, 0, msg=eval_result.stdout + "\n" + eval_result.stderr)
            self.assertTrue(report.exists())

            payload = json.loads(report.read_text(encoding="utf-8"))
            self.assertIn("macro_f1", payload)
            self.assertIn("per_class", payload)
            for label in LABELS:
                self.assertIn(label, payload["per_class"])

    def test_export_artifact_directory(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            out_dir = Path(temp_dir) / "artifacts"
            out_dir.mkdir(parents=True)
            model_path = out_dir / "line_classifier.pkl"

            # Reuse existing fixture classifier by training once.
            train = self.run_script(
                "train_line_classifier.py",
                "--data-dir", str(self.data_dir),
                "--out-dir", str(out_dir),
            )
            self.assertEqual(train.returncode, 0, msg=train.stdout + "\n" + train.stderr)

            export_path = out_dir / "RecipeLineClassifier.mlmodel"
            exported = self.run_script(
                "export_coreml.py",
                "--model", str(model_path),
                "--out", str(export_path),
            )
            self.assertEqual(exported.returncode, 0, msg=exported.stdout + "\n" + exported.stderr)

            compiled_dir = out_dir / "RecipeLineClassifier.mlmodelc"
            self.assertTrue(compiled_dir.exists())
            self.assertTrue((compiled_dir / "Manifest.json").exists())
            self.assertTrue((compiled_dir / "line_classifier.pkl").exists())
            self.assertTrue((compiled_dir / "line_classifier.json").exists())


if __name__ == "__main__":
    unittest.main()
