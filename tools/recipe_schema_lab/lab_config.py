from __future__ import annotations

import os
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8765

DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[2]
REPO_ROOT = Path(os.environ.get("CAULDRON_REPO") or DEFAULT_REPO_ROOT).resolve()
TOOLS_DIR = REPO_ROOT / "tools" / "recipe_schema_model"
ARTIFACT_MODEL = TOOLS_DIR / "artifacts" / "line_classifier.pkl"
ARTIFACT_SPLIT = TOOLS_DIR / "artifacts" / "split.json"
EXPORT_SCRIPT = TOOLS_DIR / "export_corrections.py"
EVALUATE_SCRIPT = TOOLS_DIR / "evaluate_line_classifier.py"
REGRESSION_SCRIPT = TOOLS_DIR / "regression_metrics.py"
VALIDATE_SCRIPT = TOOLS_DIR / "validate_dataset.py"
TRAIN_SCRIPT = TOOLS_DIR / "train_line_classifier.py"
EXPORT_COREML_SCRIPT = TOOLS_DIR / "export_coreml.py"
BUNDLED_MODEL_OUT = REPO_ROOT / "Cauldron" / "Resources" / "ML" / "RecipeLineClassifier.mlmodel"
DEFAULT_DATASET_DIR = REPO_ROOT / "CauldronTests" / "Fixtures" / "RecipeSchema"
DEFAULT_REGRESSION_DIR = DEFAULT_DATASET_DIR / "regression"
HOLDOUT_DOC_PREFIX = "holdout_"

LAB_TOOL_DIR = Path(__file__).resolve().parent
STATIC_DIR = LAB_TOOL_DIR / "static"
APPLE_OCR_SWIFT_SCRIPT = LAB_TOOL_DIR / "apple_vision_ocr.swift"
OCR_ENGINE = (os.environ.get("CAULDRON_LAB_OCR_ENGINE") or "apple").strip().lower()
CAULDRON_ICON_CANDIDATES = [
    REPO_ROOT / "Cauldron" / "Resources" / "SVG" / "CauldronSVG.svg",
    REPO_ROOT / "Cauldron" / "Assets.xcassets" / "BrandMarks" / "CauldronIcon.imageset" / "CauldronSVG.svg",
    REPO_ROOT / "CauldronShareExtension" / "Assets.xcassets" / "BrandMarks" / "CauldronIcon.imageset" / "CauldronSVG.svg",
]

LOCAL_ROOT = Path(
    os.environ.get("CAULDRON_QA_LOCAL_ROOT") or (Path.home() / ".codex" / "local" / "recipe_schema_lab")
)
LOCAL_CASES_DIR = LOCAL_ROOT / "cases"
LOCAL_TMP_DIR = LOCAL_ROOT / "tmp"
METRICS_HISTORY_PATH = LOCAL_ROOT / "metrics_history.json"

LABELS = ["title", "ingredient", "step", "note", "header", "junk"]

INGREDIENT_HEADER_PREFIXES = {
    "ingredient",
    "ingredients",
    "for the ingredients",
    "what you'll need",
}

STEP_HEADER_PREFIXES = {
    "instruction",
    "instructions",
    "direction",
    "directions",
    "method",
    "preparation",
    "steps",
}

NOTE_HEADER_PREFIXES = {
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

TIMER_LABEL_KEYWORDS = [
    (["rest", "resting"], "Rest"),
    (["chill", "chilling", "refrigerate", "cool", "cooling"], "Chill"),
    (["rise", "proof", "proofing", "ferment"], "Rise"),
    (["marinate", "marinating"], "Marinate"),
    (["simmer", "simmering"], "Simmer"),
    (["boil", "boiling"], "Boil"),
    (["bake", "baking"], "Bake"),
    (["roast", "roasting"], "Roast"),
    (["fry", "frying", "saute", "sauté"], "Fry"),
]

UNIT_ALIASES: dict[str, str] = {
    "t": "tsp",
    "tsp": "tsp",
    "tsps": "tsp",
    "teaspoon": "tsp",
    "teaspoons": "tsp",
    # Common typo seen in publisher data feeds.
    "teapoon": "tsp",
    "teapoons": "tsp",
    "tbsp": "tbsp",
    "tbsps": "tbsp",
    "tablespoon": "tbsp",
    "tablespoons": "tbsp",
    "c": "cup",
    "cup": "cup",
    "cups": "cup",
    "oz": "oz",
    "ounce": "oz",
    "ounces": "oz",
    "lb": "lb",
    "1b": "lb",
    "ib": "lb",
    "lbs": "lb",
    "pound": "lb",
    "pounds": "lb",
    "g": "g",
    "gram": "g",
    "grams": "g",
    "kg": "kg",
    "kgs": "kg",
    "kilogram": "kg",
    "kilograms": "kg",
    "ml": "ml",
    "mls": "ml",
    "milliliter": "ml",
    "milliliters": "ml",
    "l": "L",
    "liter": "L",
    "liters": "L",
    "pt": "pint",
    "pts": "pint",
    "pint": "pint",
    "pints": "pint",
    "qt": "quart",
    "qts": "quart",
    "quart": "quart",
    "quarts": "quart",
    "gal": "gallon",
    "gals": "gallon",
    "gallon": "gallon",
    "gallons": "gallon",
    "floz": "fl oz",
    "fl oz": "fl oz",
    "fluid ounce": "fl oz",
    "fluid ounces": "fl oz",
    "piece": "piece",
    "pieces": "piece",
    "pinch": "pinch",
    "pinches": "pinch",
    "dash": "dash",
    "dashes": "dash",
    "whole": "whole",
    "clove": "clove",
    "cloves": "clove",
    "bunch": "bunch",
    "bunches": "bunch",
    "can": "can",
    "cans": "can",
    "package": "package",
    "packages": "package",
}

UNICODE_FRACTIONS: dict[str, float] = {
    "½": 0.5,
    "¼": 0.25,
    "¾": 0.75,
    "⅓": 0.333,
    "⅔": 0.667,
    "⅛": 0.125,
    "⅜": 0.375,
    "⅝": 0.625,
    "⅞": 0.875,
}
