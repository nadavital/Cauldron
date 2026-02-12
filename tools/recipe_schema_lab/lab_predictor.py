from __future__ import annotations

import re
import sys
from typing import Any

from lab_config import ARTIFACT_MODEL, TOOLS_DIR


class Predictor:
    def __init__(self) -> None:
        if str(TOOLS_DIR) not in sys.path:
            sys.path.insert(0, str(TOOLS_DIR))

        self.model = None
        self.reload()

        self.note_header_prefixes = {
            "note",
            "notes",
            "tip",
            "tips",
            "variation",
            "variations",
            "chef's note",
            "storage",
            "substitution",
            "substitutions",
        }

        self.ingredient_header_prefixes = {
            "ingredient",
            "ingredients",
            "for the ingredients",
            "what you'll need",
        }

        self.step_header_prefixes = {
            "instruction",
            "instructions",
            "direction",
            "directions",
            "method",
            "preparation",
            "steps",
        }

    def _is_note_header(self, line: str) -> bool:
        lowered = line.strip().lower()
        if lowered.endswith(":"):
            lowered = lowered[:-1].strip()
        return lowered in self.note_header_prefixes

    def _header_key(self, line: str) -> str:
        lowered = line.strip().lower()
        lowered = re.sub(r"^[\W_]+|[\W_]+$", "", lowered)
        if lowered.endswith(":"):
            lowered = lowered[:-1].strip()
        return lowered

    def _header_section(self, line: str) -> str | None:
        key = self._header_key(line)
        if key in self.ingredient_header_prefixes:
            return "ingredient"
        if key in self.step_header_prefixes:
            return "step"
        if key in self.note_header_prefixes:
            return "note"
        return None

    def _looks_like_header(self, line: str) -> bool:
        text = line.strip()
        if not text.endswith(":"):
            return False
        words = text[:-1].strip().split()
        return 0 < len(words) <= 7 and len(text) <= 90

    def _looks_like_title_line(self, line: str, idx: int) -> bool:
        if idx != 0:
            return False
        text = line.strip()
        if not text or text.endswith(":"):
            return False
        if len(text) > 110:
            return False
        words = text.split()
        if not (1 <= len(words) <= 14):
            return False
        lowered = text.lower()
        for token in ("ingredient", "instruction", "direction", "method", "step"):
            if token in lowered:
                return False
        if text.count(".") > 0:
            return False
        return True

    def predict(self, lines: list[str]) -> list[dict[str, Any]]:
        results: list[dict[str, Any]] = []
        active_section: str | None = None

        for idx, line in enumerate(lines):
            label, confidence, _ = self.model.predict_with_confidence(line)
            header_section = self._header_section(line)
            looks_like_header = self._looks_like_header(line)

            if self._looks_like_title_line(line, idx):
                label = "title"
                confidence = max(confidence, 0.96)

            if header_section:
                label = "header"
                confidence = max(confidence, 0.98)
                active_section = header_section
            elif looks_like_header:
                label = "header"
                confidence = max(confidence, 0.93)
            elif active_section == "note" and label != "header":
                label = "note"
                confidence = max(confidence, 0.90)
            elif active_section == "ingredient" and label not in {"header", "title"}:
                label = "ingredient"
                confidence = max(confidence, 0.90)
            elif active_section == "step" and label != "header":
                label = "step"
                confidence = max(confidence, 0.90)

            results.append(
                {
                    "index": idx,
                    "text": line,
                    "predicted_label": label,
                    "label": label,
                    "confidence": round(float(confidence), 4),
                }
            )

        return results

    def reload(self) -> None:
        from schema_model import load_pickle

        if not ARTIFACT_MODEL.exists():
            raise FileNotFoundError(f"Missing model artifact: {ARTIFACT_MODEL}")
        self.model = load_pickle(ARTIFACT_MODEL)


PREDICTOR = Predictor()
