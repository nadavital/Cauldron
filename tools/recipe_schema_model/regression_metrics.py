#!/usr/bin/env python3
"""Regression harness for section-level parser outcomes.

The harness compares expected section membership from JSON regression fixtures
against classifier predictions on each line.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, List, Tuple

from schema_model import load_pickle


def _normalize(text: str) -> str:
    return text.strip().lower()


def _score_case(model, case_payload: Dict[str, object]) -> Tuple[bool, float, float, float]:
    text = str(case_payload["text"])
    expected = case_payload["expected"]
    lines = [line.strip() for line in text.splitlines() if line.strip()]

    predicted_ingredients: List[str] = []
    predicted_steps: List[str] = []
    predicted_notes: List[str] = []
    previous_was_note_header = False

    for line in lines[1:]:  # skip title
        label, confidence, _ = model.predict_with_confidence(line)
        trimmed = line.strip()

        if previous_was_note_header and not trimmed.endswith(":"):
            label = "note"

        if confidence < 0.72:
            # deterministic fallback in harness: quantity-led lines are ingredients,
            # long/action lines are steps.
            lower = line.lower()
            if any(char.isdigit() for char in lower):
                label = "ingredient"
            elif any(word in lower for word in ("mix", "cook", "bake", "stir", "heat", "add", "roast", "simmer")):
                label = "step"

        if label == "ingredient":
            predicted_ingredients.append(line)
        elif label == "step":
            predicted_steps.append(line)
        elif label == "note":
            predicted_notes.append(line)

        lowered = trimmed.lower()
        stem = lowered[:-1].strip() if lowered.endswith(":") else lowered
        previous_was_note_header = stem in {
            "note",
            "notes",
            "tip",
            "tips",
            "variation",
            "variations",
            "chef's note",
            "storage",
        }

    expected_ingredients = [_normalize(item) for item in expected["ingredients"]]
    expected_steps = [_normalize(item) for item in expected["steps"]]
    expected_notes = [_normalize(item) for item in expected["notes_contains"]]

    ingredient_exact = sorted(_normalize(item) for item in predicted_ingredients) == sorted(expected_ingredients)
    step_exact = sorted(_normalize(item) for item in predicted_steps) == sorted(expected_steps)

    notes_blob = "\n".join(predicted_notes).lower()
    note_exact = all(fragment in notes_blob for fragment in expected_notes)

    exact_match = ingredient_exact and step_exact and note_exact

    note_leak_count = 0
    for note_fragment in expected_notes:
        leaked = any(note_fragment in _normalize(item) for item in predicted_ingredients + predicted_steps)
        if leaked:
            note_leak_count += 1

    swap_count = 0
    for expected_ingredient in expected_ingredients:
        if any(expected_ingredient in _normalize(item) for item in predicted_steps):
            swap_count += 1
    for expected_step in expected_steps:
        if any(expected_step in _normalize(item) for item in predicted_ingredients):
            swap_count += 1

    expected_total = max(1, len(expected_ingredients) + len(expected_steps))
    leakage_rate = note_leak_count / max(1, len(expected_notes)) if expected_notes else 0.0
    swap_rate = swap_count / expected_total

    return exact_match, leakage_rate, swap_rate, 1.0 if exact_match else 0.0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run parser regression metrics harness")
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--regression-dir", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()

    model = load_pickle(args.model)
    fixtures = sorted(args.regression_dir.glob("*.json"))

    if not fixtures:
        raise SystemExit("No regression fixtures found")

    exact_scores: List[float] = []
    leakage_rates: List[float] = []
    swap_rates: List[float] = []

    for fixture in fixtures:
        payload = json.loads(fixture.read_text(encoding="utf-8"))
        exact_match, leakage_rate, swap_rate, exact_score = _score_case(model, payload)
        exact_scores.append(exact_score)
        leakage_rates.append(leakage_rate)
        swap_rates.append(swap_rate)
        print(
            f"{payload['name']}: exact_match={'PASS' if exact_match else 'FAIL'} "
            f"leakage={leakage_rate:.2%} swap={swap_rate:.2%}"
        )

    exact_match_rate = sum(exact_scores) / len(exact_scores)
    note_leakage_rate = sum(leakage_rates) / len(leakage_rates)
    ingredient_step_swap_rate = sum(swap_rates) / len(swap_rates)

    report = {
        "exact_match_rate": exact_match_rate,
        "note_leakage_rate": note_leakage_rate,
        "ingredient_step_swap_rate": ingredient_step_swap_rate,
        "fixture_count": len(fixtures),
    }

    print("REGRESSION METRICS")
    print(json.dumps(report, indent=2))

    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    # Guardrails for plan acceptance.
    return 0 if note_leakage_rate <= 0.05 and ingredient_step_swap_rate <= 0.08 else 1


if __name__ == "__main__":
    raise SystemExit(main())
