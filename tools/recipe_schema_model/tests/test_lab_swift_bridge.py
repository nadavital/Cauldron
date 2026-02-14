#!/usr/bin/env python3

from __future__ import annotations

import json
import os
import sys
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib import request


class LabSwiftBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[3]
        cls.lab_dir = cls.repo_root / "tools" / "recipe_schema_lab"
        if str(cls.lab_dir) not in sys.path:
            sys.path.insert(0, str(cls.lab_dir))

        from lab_handler import LabHandler  # noqa: WPS433

        cls._original_fallback = os.environ.get("CAULDRON_LAB_USE_PYTHON_FALLBACK")
        os.environ["CAULDRON_LAB_USE_PYTHON_FALLBACK"] = "0"

        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), LabHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=5)
        if cls._original_fallback is None:
            os.environ.pop("CAULDRON_LAB_USE_PYTHON_FALLBACK", None)
        else:
            os.environ["CAULDRON_LAB_USE_PYTHON_FALLBACK"] = cls._original_fallback

    def _post(self, path: str, payload: dict[str, object]) -> dict[str, object]:
        body = json.dumps(payload).encode("utf-8")
        req = request.Request(
            url=f"{self.base_url}{path}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=30) as resp:  # noqa: S310
            content = resp.read()
        return json.loads(content.decode("utf-8"))

    def test_predict_endpoint_uses_swift_pipeline(self) -> None:
        payload = {
            "mode": "text",
            "text": "\n".join(
                [
                    "Chocolate Toast",
                    "Ingredients:",
                    "2 slices bread",
                    "1 tbsp butter",
                    "Instructions:",
                    "Toast bread until golden.",
                    "Spread butter over toast.",
                ]
            ),
        }
        response = self._post("/predict", payload)

        self.assertEqual(response.get("pipeline_backend"), "swift")
        self.assertIn("lines", response)
        self.assertIn("assembled_recipe", response)

        assembled = response.get("assembled_recipe")
        self.assertIsInstance(assembled, dict)
        self.assertGreaterEqual(len((assembled or {}).get("ingredients") or []), 1)
        self.assertGreaterEqual(len((assembled or {}).get("steps") or []), 1)
        self.assertIn("title", assembled)

    def test_assemble_recipe_endpoint_uses_swift_pipeline(self) -> None:
        payload = {
            "source_url": "https://example.com/recipe",
            "source_title": "Example Recipe",
            "lines": [
                {"index": 0, "text": "Ingredients:", "label": "header"},
                {"index": 1, "text": "1 cup all-purpose flour", "label": "ingredient"},
                {"index": 2, "text": "Instructions:", "label": "header"},
                {"index": 3, "text": "Mix and bake.", "label": "step"},
            ],
        }
        response = self._post("/assemble_recipe", payload)

        self.assertEqual(response.get("pipeline_backend"), "swift")
        recipe = response.get("recipe")
        self.assertIsInstance(recipe, dict)
        self.assertGreaterEqual(len((recipe or {}).get("ingredients") or []), 1)
        self.assertGreaterEqual(len((recipe or {}).get("steps") or []), 1)
        self.assertEqual((recipe or {}).get("sourceURL"), "https://example.com/recipe")
        self.assertEqual((recipe or {}).get("sourceTitle"), "Example Recipe")


if __name__ == "__main__":
    unittest.main()
