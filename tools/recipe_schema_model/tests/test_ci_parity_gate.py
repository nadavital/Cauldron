#!/usr/bin/env python3

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


class CIParityGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[3]
        self.tool_dir = self.repo_root / "tools" / "recipe_schema_model"

    def test_label_parity_gate(self) -> None:
        cmd = ["python3", str(self.tool_dir / "compare_swift_python_labels.py"), "--gate"]
        result = subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, msg=result.stdout + "\n" + result.stderr)

    def test_assembly_parity_gate(self) -> None:
        cmd = ["python3", str(self.tool_dir / "compare_swift_python_assembly.py"), "--gate"]
        result = subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, msg=result.stdout + "\n" + result.stderr)


if __name__ == "__main__":
    unittest.main()
