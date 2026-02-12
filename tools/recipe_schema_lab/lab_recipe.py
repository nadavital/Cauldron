from __future__ import annotations

import json
import re
import subprocess
import tempfile
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any
from urllib import request as urllib_request
from urllib.parse import urlparse

from lab_config import (
    APPLE_OCR_SWIFT_SCRIPT,
    INGREDIENT_HEADER_PREFIXES,
    LABELS,
    LOCAL_TMP_DIR,
    NOTE_HEADER_PREFIXES,
    OCR_ENGINE,
    STEP_HEADER_PREFIXES,
    TIMER_LABEL_KEYWORDS,
    UNICODE_FRACTIONS,
    UNIT_ALIASES,
)


class _VisibleTextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._chunks: list[str] = []
        self._skip_depth = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in {"script", "style", "noscript"}:
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag in {"script", "style", "noscript"} and self._skip_depth > 0:
            self._skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth == 0:
            self._chunks.append(data)

    def text(self) -> str:
        raw = unescape("\n".join(self._chunks))
        raw = re.sub(r"\s+", " ", raw)
        return raw


def _clean_text(value: str) -> str:
    return re.sub(r"\s+", " ", unescape(value)).strip()


def _normalize_ingredient_source_text(value: str) -> str:
    text = _clean_text(value)
    if not text:
        return ""

    # Some publishers emit malformed parenthetical ingredient hints such as:
    # "5 cloves garlic ((finely minced))" or "(, minced)".
    text = re.sub(r"\(\s*,\s*", "(", text)
    text = re.sub(r"\(\s*;\s*", "(", text)

    previous = None
    while text != previous:
        previous = text
        text = re.sub(r"\(\(\s*([^()]*)\s*\)\)", r"(\1)", text)
        text = text.replace("((", "(").replace("))", ")")

    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    depth = 0
    balanced: list[str] = []
    for char in text:
        if char == "(":
            depth += 1
            balanced.append(char)
            continue
        if char == ")":
            if depth == 0:
                continue
            depth -= 1
            balanced.append(char)
            continue
        balanced.append(char)
    if depth > 0:
        balanced.extend(")" * depth)
    text = "".join(balanced)
    return _clean_text(text)


def _jsonld_blocks(html: str) -> list[str]:
    return re.findall(
        r"<script[^>]*type\s*=\s*(?:[\"']?application/ld\+json[\"']?)[^>]*>(.*?)</script>",
        html,
        flags=re.IGNORECASE | re.DOTALL,
    )


def _escape_control_chars_in_json_strings(raw: str) -> str:
    out: list[str] = []
    in_string = False
    escaped = False
    for ch in raw:
        if in_string:
            if escaped:
                out.append(ch)
                escaped = False
                continue
            if ch == "\\":
                out.append(ch)
                escaped = True
                continue
            if ch == '"':
                out.append(ch)
                in_string = False
                continue
            if ch == "\n":
                out.append("\\n")
                continue
            if ch == "\r":
                out.append("\\r")
                continue
            if ch == "\t":
                out.append("\\t")
                continue
            out.append(ch)
            continue
        out.append(ch)
        if ch == '"':
            in_string = True
            escaped = False
    return "".join(out)


def _decode_multiple_json_values(raw: str) -> list[Any]:
    decoder = json.JSONDecoder()
    values: list[Any] = []
    idx = 0
    size = len(raw)

    while idx < size:
        while idx < size and raw[idx].isspace():
            idx += 1
        if idx >= size:
            break
        try:
            value, end = decoder.raw_decode(raw, idx)
        except json.JSONDecodeError:
            return []
        values.append(value)
        idx = end

    return values


def _parse_jsonld_payloads(raw: str) -> list[Any]:
    base = raw.strip().replace("\ufeff", "")
    base = re.sub(r"^\s*<!--\s*|\s*-->\s*$", "", base)
    if not base:
        return []

    variants = [
        base,
        _escape_control_chars_in_json_strings(base),
    ]
    variants.extend([re.sub(r",\s*([}\]])", r"\1", value) for value in variants])

    seen: set[str] = set()
    for variant in variants:
        if not variant:
            continue
        if variant in seen:
            continue
        seen.add(variant)

        try:
            return [json.loads(variant)]
        except Exception:
            pass

        decoded = _decode_multiple_json_values(variant)
        if decoded:
            return decoded

    return []


def _is_recipe_type(type_value: Any) -> bool:
    if isinstance(type_value, str):
        return type_value.lower().split("/")[-1] == "recipe"
    if isinstance(type_value, list):
        return any(_is_recipe_type(item) for item in type_value)
    return False


def _collect_recipe_nodes(node: Any, out: list[dict[str, Any]]) -> None:
    if isinstance(node, dict):
        if _is_recipe_type(node.get("@type")):
            out.append(node)
        for value in node.values():
            _collect_recipe_nodes(value, out)
        return
    if isinstance(node, list):
        for item in node:
            _collect_recipe_nodes(item, out)


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _unique_preserve(items: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for item in items:
        key = item.casefold()
        if key in seen:
            continue
        seen.add(key)
        out.append(item)
    return out


def _extract_ingredients(recipe: dict[str, Any]) -> list[str]:
    items = recipe.get("recipeIngredient") or recipe.get("ingredients") or []
    out: list[str] = []
    for item in _as_list(items):
        if isinstance(item, str):
            text = _normalize_ingredient_source_text(item)
            if text:
                out.append(text)
        elif isinstance(item, dict):
            text = _normalize_ingredient_source_text(str(item.get("text", "")).strip())
            if text:
                out.append(text)
    return _unique_preserve(out)


def _extract_instruction_lines(recipe: dict[str, Any]) -> list[str]:
    out: list[str] = []

    def walk(node: Any) -> None:
        if isinstance(node, str):
            text = _clean_text(node)
            if text:
                out.extend(_split_numbered_steps(text))
            return

        if isinstance(node, list):
            for item in node:
                walk(item)
            return

        if isinstance(node, dict):
            section_name = _clean_text(str(node.get("name", "")))
            if section_name and len(section_name.split()) <= 7 and node.get("itemListElement"):
                out.append(f"{section_name}:")

            text = node.get("text")
            if isinstance(text, str):
                t = _clean_text(text)
                if t:
                    out.extend(_split_numbered_steps(t))

            if "itemListElement" in node:
                walk(node.get("itemListElement"))
                return

            for key in ("steps", "instructions", "recipeInstructions"):
                if key in node:
                    walk(node[key])

    walk(recipe.get("recipeInstructions") or recipe.get("instructions") or [])
    return _unique_preserve(out)


def _split_numbered_steps(text: str) -> list[str]:
    cleaned = _clean_text(text)
    if not cleaned:
        return []

    # Some sources collapse all numbered instructions into a single string:
    # "1. ...2. ...3. ...". Split those into separate lines.
    matches = list(re.finditer(r"(?<!\d)(\d{1,2})\.\s+", cleaned))
    if len(matches) < 2 or matches[0].start() != 0:
        return [cleaned]

    parts: list[str] = []
    for idx, match in enumerate(matches):
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(cleaned)
        part = _clean_text(cleaned[start:end])
        if part:
            parts.append(part)

    return parts or [cleaned]


def _strip_step_number_prefix(text: str) -> str:
    cleaned = _clean_text(text)
    if not cleaned:
        return ""
    # App handles instruction numbering; store plain step text.
    cleaned = re.sub(r"^\s*[•·▪◦●]+\s*", "", cleaned).strip()
    cleaned = re.sub(r"^\s*\d{1,2}\s*[.)]\s*", "", cleaned).strip()
    cleaned = re.sub(r"^\s*[•·▪◦●]+\s*", "", cleaned).strip()
    return cleaned


def _extract_title_from_html(html: str) -> str:
    patterns = [
        r"<meta[^>]+property=[\"']og:title[\"'][^>]+content=[\"']([^\"']+)[\"']",
        r"<meta[^>]+content=[\"']([^\"']+)[\"'][^>]+property=[\"']og:title[\"']",
        r"<h1[^>]*>(.*?)</h1>",
        r"<title[^>]*>(.*?)</title>",
    ]
    for pattern in patterns:
        match = re.search(pattern, html, flags=re.IGNORECASE | re.DOTALL)
        if not match:
            continue
        raw = re.sub(r"<[^>]+>", " ", match.group(1))
        title = _clean_text(unescape(raw))
        if title:
            return title
    return ""


def _extract_recipe_from_jsonld(html: str) -> tuple[list[str], dict[str, Any]] | None:
    recipes: list[dict[str, Any]] = []
    for block in _jsonld_blocks(html):
        raw = block.strip()
        if not raw:
            continue

        # Parse raw JSON-LD first. Some sites encode entities like "&quot;"
        # inside JSON strings, and eagerly unescaping before JSON decode can
        # invalidate the payload.
        variants = [raw]
        decoded = unescape(raw).strip()
        if decoded and decoded != raw:
            variants.append(decoded)

        for variant in variants:
            for payload in _parse_jsonld_payloads(variant):
                _collect_recipe_nodes(payload, recipes)

    if not recipes:
        return None

    def score(recipe: dict[str, Any]) -> int:
        title = 3 if _clean_text(str(recipe.get("name", ""))) else 0
        ingredients = len(_extract_ingredients(recipe))
        steps = len(_extract_instruction_lines(recipe))
        return title + ingredients + (steps * 2)

    recipe = max(recipes, key=score)
    title = _clean_text(str(recipe.get("name", "")))
    ingredients = _extract_ingredients(recipe)
    instructions = _extract_instruction_lines(recipe)

    lines: list[str] = []
    if title:
        lines.append(title)
    if ingredients:
        lines.append("Ingredients")
        lines.extend(ingredients)
    if instructions:
        lines.append("Instructions")
        lines.extend(instructions)

    if not lines:
        return None

    return (
        lines,
        {
            "method": "jsonld_recipe",
            "title": title,
            "ingredient_count": len(ingredients),
            "instruction_count": len(instructions),
        },
    )


def _extract_main_html_fragment(html: str) -> str:
    candidates = []
    for pattern in (r"<article[^>]*>(.*?)</article>", r"<main[^>]*>(.*?)</main>"):
        for match in re.finditer(pattern, html, flags=re.IGNORECASE | re.DOTALL):
            fragment = match.group(1)
            candidates.append(fragment)
    if not candidates:
        return html
    return max(candidates, key=len)


def _header_key(line: str) -> str:
    lowered = line.strip().lower()
    lowered = re.sub(r"^[\W_]+|[\W_]+$", "", lowered)
    if lowered.endswith(":"):
        lowered = lowered[:-1].strip()
    return lowered


def _header_section_type(line: str) -> str | None:
    key = _header_key(line)
    if key in INGREDIENT_HEADER_PREFIXES:
        return "ingredients"
    if key in STEP_HEADER_PREFIXES:
        return "steps"
    if key in NOTE_HEADER_PREFIXES:
        return "notes"
    return None


def _looks_like_subsection_header(line: str) -> bool:
    text = line.strip()
    if not text.endswith(":"):
        return False
    words = text[:-1].strip().split()
    if not (0 < len(words) <= 7):
        return False
    if len(text) > 90:
        return False
    if any(char.isdigit() for char in text):
        return False
    return True


_INSTRUCTION_KEYWORDS = {
    "add",
    "bake",
    "beat",
    "blend",
    "boil",
    "combine",
    "cook",
    "cool",
    "drain",
    "fold",
    "fry",
    "grill",
    "heat",
    "knead",
    "let",
    "marinate",
    "mix",
    "place",
    "pour",
    "preheat",
    "reduce",
    "rest",
    "roast",
    "saute",
    "season",
    "serve",
    "simmer",
    "stir",
    "transfer",
    "whisk",
}


def _looks_like_ingredient_line(line: str) -> bool:
    return re.match(r"^[\d\s½¼¾⅓⅔⅛⅜⅝⅞/\.-]+", line) is not None


def _looks_like_headerless_instruction(line: str) -> bool:
    if _looks_like_ingredient_line(line):
        return False
    if _split_numbered_steps(line) != [line]:
        return True

    words = [part for part in re.split(r"\s+", line.lower()) if part]
    if not words:
        return False

    tokens = [token for token in re.split(r"[^a-z0-9]+", line.lower()) if token]
    first = words[0]
    if first in _INSTRUCTION_KEYWORDS:
        return True
    if first in {"in", "on", "to", "then", "meanwhile"} and any(token in _INSTRUCTION_KEYWORDS for token in tokens):
        return True
    return False


def _is_ocr_artifact_line(text: str) -> bool:
    cleaned = _clean_text(text)
    if not cleaned:
        return True
    lowered = cleaned.lower()

    if "templatelab" in lowered or "created by" in lowered or lowered == "reated b":
        return True
    if re.match(r"^\s*(?:prep(?:ping)?|preparation|cook(?:ing)?|total)\s*tim(?:e)?\b", lowered):
        return True
    if re.fullmatch(r"[\W_]+", cleaned):
        return True

    alpha_count = len(re.findall(r"[A-Za-z]", cleaned))
    if alpha_count <= 1:
        return True

    if re.fullmatch(r"[A-Za-z]{1,6}", cleaned):
        keep = {"salt", "zest", "oil", "rice", "egg", "eggs"}
        if cleaned.lower() not in keep:
            return True

    return False


def _extract_tips_remainder(text: str) -> str | None:
    cleaned = _clean_text(text)
    if not cleaned:
        return None
    match = re.search(
        r"\btips?\s*(?:and|&)\s*variations?\b[:\-\s]*(.*)$",
        cleaned,
        flags=re.IGNORECASE,
    )
    if not match:
        if re.fullmatch(r"tips?(?:\s*(?:and|&)\s*variations?)?", cleaned, flags=re.IGNORECASE):
            return ""
        return None
    return _clean_text(match.group(1))


def _normalize_note_text(text: str) -> str:
    cleaned = _clean_text(text)
    cleaned = re.sub(r"^[,;:\-•\s]+", "", cleaned)
    return _clean_text(cleaned)


def _looks_like_note_fragment(text: str) -> bool:
    cleaned = _clean_text(text)
    if not cleaned:
        return False
    if _looks_like_ingredient_line(cleaned):
        return False
    if _looks_like_headerless_instruction(cleaned):
        return False

    lowered = cleaned.lower()
    if cleaned[0] in {",", ";", ":"}:
        return len(cleaned.split()) >= 2

    first_token_match = re.match(r"([A-Za-z]+)", cleaned)
    first_token = first_token_match.group(1).lower() if first_token_match else ""
    if first_token in {"for", "feel", "use", "optional", "tip", "tips", "variation", "variations", "extra"}:
        return True

    if re.search(r"\b(?:flavor|nutrition|twist|optional|variation|tip|wine)\b", lowered):
        return True
    return False


def _looks_like_step_fragment(text: str) -> bool:
    cleaned = _clean_text(text)
    if not cleaned:
        return False
    if _is_ocr_artifact_line(cleaned):
        return False
    if _extract_tips_remainder(cleaned) is not None:
        return False
    if _looks_like_ingredient_line(cleaned):
        return False
    if _looks_like_note_fragment(cleaned):
        return False
    if _looks_like_headerless_instruction(cleaned):
        return True

    lowered = cleaned.lower()
    if re.search(
        r"\b(?:add|cook|drain|heat|mix|preheat|prepare|remove|rest|return|serve|simmer|sprinkle|stir|toss)\b",
        lowered,
    ):
        return True
    if re.search(r"\b(?:bowl|broth|minutes?|oven|pot|sauce|set aside|skillet)\b", lowered):
        return True
    if cleaned.endswith(".") and len(cleaned.split()) >= 4:
        return True
    return False


def _sanitize_ingredient_name(name: str) -> str:
    cleaned = _clean_text(name)
    if not cleaned:
        return ""

    lowered = cleaned.lower()
    if "package and" in lowered:
        cleaned = re.sub(r"\bpackage and\b", "and", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bpackage\b", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bto\s+taste\s+salt(?:\s+and)?\b.*$", "to taste", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bto\s+taste\b.*$", "to taste", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bfor serving\b.*$", "for serving", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\band\s+red\b(?:\s+[A-Za-z]{1,4})?\s*$", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bsauce\b.*$", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bchopped\s+immediat\w*\b.*$", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\blemon\s+z[e3](?:st)?\s+(?=fresh parsley\b)", "", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\bto\s+taste\s+and\s*$", "to taste", cleaned, flags=re.IGNORECASE)

    if re.search(r"\b(?:package instructions?|set aside|minutes?|minute)\b", lowered):
        cleaned = re.sub(r"\bpackage instructions?\b.*$", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\bset aside\b.*$", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\bminutes?\b.*$", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\babout\s+\d+\b.*$", "", cleaned, flags=re.IGNORECASE)

    cleaned = re.sub(r"\s+", " ", cleaned).strip(" ,;:-")
    cleaned = re.sub(r"\b[A-Za-z]$", "", cleaned).strip(" ,;:-")
    return _clean_text(cleaned)


def _should_drop_ingredient_entry(name: str, quantity: dict[str, Any] | None) -> bool:
    cleaned = _clean_text(name)
    if not cleaned:
        return True
    if _is_ocr_artifact_line(cleaned):
        return True
    if _extract_tips_remainder(cleaned) is not None:
        return True

    lowered = cleaned.lower()
    if quantity is None:
        if _looks_like_headerless_instruction(cleaned):
            return True
        if re.search(r"\b(?:skillet|prepare|serve|sprinkle|immediately|return the|set aside|minutes?)\b", lowered):
            return True
        if re.fullmatch(r"[A-Za-z]+\s+\d+", cleaned):
            return True

    return False


def _parse_time_string_minutes(text: str) -> int | None:
    cleaned = text.strip().lower()
    if not cleaned:
        return None

    colon_match = re.search(r"\b(\d+):(\d+)\b", cleaned)
    if colon_match:
        return int(colon_match.group(1)) * 60 + int(colon_match.group(2))

    hours = 0
    minutes = 0
    found = False

    hour_match = re.search(r"\b(\d+)\s*(?:hours?|hrs?|h)\b", cleaned)
    if hour_match:
        hours = int(hour_match.group(1))
        found = True

    minute_match = re.search(r"\b(\d+)\s*(?:minutes?|mins?|m)\b", cleaned)
    if minute_match:
        minutes = int(minute_match.group(1))
        found = True

    if found:
        return hours * 60 + minutes

    bare = re.search(r"\b(\d+)\b", cleaned)
    if bare:
        return int(bare.group(1))

    return None


def _extract_minutes_by_pattern(text: str, pattern: str) -> int | None:
    match = re.search(pattern, text, flags=re.IGNORECASE)
    if not match:
        return None
    tail = _clean_text(match.group(1))
    if not tail:
        return None
    return _parse_time_string_minutes(tail)


def _extract_yield_line(text: str) -> str | None:
    lowered = text.strip().lower()
    prefixes = ("serves", "serving", "servings", "yield", "yields", "makes", "portion", "portions")
    if not any(lowered == key or lowered.startswith(f"{key} ") or lowered.startswith(f"{key}:") for key in prefixes):
        return None

    number_match = re.search(r"(\d+(?:\s*(?:-|–|to)\s*\d+)?)", text, flags=re.IGNORECASE)
    if not number_match:
        return None
    number = number_match.group(1).replace(" to ", "-").replace("–", "-")
    number = re.sub(r"\s+", " ", number).strip()
    return f"{number} servings"


def _extract_metadata_line(text: str) -> dict[str, Any] | None:
    if not text:
        return None

    out: dict[str, Any] = {}
    yield_value = _extract_yield_line(text)
    if yield_value:
        out["yields"] = yield_value

    total = _extract_minutes_by_pattern(text, r"^\s*(?:total\s*time|total|ready\s*in)\s*:?\s*(.+)$")
    if total is None:
        total = _extract_minutes_by_pattern(text, r"^\s*time\s*:\s*(.+)$")
    if total is not None:
        out["total_minutes"] = total
    prep = _extract_minutes_by_pattern(text, r"^\s*(?:prep\s*time|prepping\s*time|preparation\s*time)\s*:?\s*(.+)$")
    if prep is not None:
        out["prep_minutes"] = prep
    cook = _extract_minutes_by_pattern(text, r"^\s*(?:cook\s*time|cooking\s*time|bake\s*time|roast\s*time)\s*:?\s*(.+)$")
    if cook is not None:
        out["cook_minutes"] = cook

    return out or None


def _default_source_title(source_url: str) -> str | None:
    if not source_url:
        return None
    parsed = urlparse(source_url)
    if not parsed.netloc:
        return None
    return parsed.netloc


def _infer_timer_label(lowered_text: str, start: int, end: int, index: int, total: int) -> str:
    context_before = lowered_text[max(0, start - 60) : start]
    context_after = lowered_text[end : min(len(lowered_text), end + 24)]

    for keywords, label in TIMER_LABEL_KEYWORDS:
        if any(keyword in context_before for keyword in keywords):
            return label

    for keywords, label in TIMER_LABEL_KEYWORDS:
        if any(keyword in context_after for keyword in keywords):
            return label

    if total > 1 and index == total - 1 and ("then" in context_before or "after" in context_before):
        return "Rest"
    return "Cook"


def _extract_timers(step_text: str) -> list[dict[str, Any]]:
    lowered = step_text.lower()
    raw_matches: list[tuple[int, int, int, str]] = []

    patterns = [
        (r"(\d+)\s*(seconds?|secs?)\b", "seconds"),
        (r"(\d+)\s*(minutes?|mins?)\b", "minutes"),
        (r"(\d+)\s*(hours?|hrs?)\b", "hours"),
    ]

    for pattern, unit in patterns:
        for match in re.finditer(pattern, lowered):
            value = int(match.group(1))
            raw_matches.append((match.start(), match.end(), value, unit))

    raw_matches.sort(key=lambda item: item[0])
    timers: list[dict[str, Any]] = []
    for idx, (start, end, value, unit) in enumerate(raw_matches):
        if unit == "seconds":
            seconds = value
        elif unit == "minutes":
            seconds = value * 60
        else:
            seconds = value * 3600
        timers.append(
            {
                "seconds": seconds,
                "label": _infer_timer_label(lowered, start, end, idx, len(raw_matches)),
            }
        )
    return timers


def _normalize_quantity_text(text: str) -> str:
    cleaned = text.strip()
    cleaned = cleaned.replace("–", "-").replace("—", "-")
    replacements: list[tuple[str, str]] = [
        (r"(?<![A-Za-z])[oO](?=\d)", "0"),
        (r"(?<=\d)[oO](?=\d|/|\b)", "0"),
        (r"(?<![A-Za-z])[Il](?=\d|/|\.|\b)", "1"),
        (r"(?<=\d)[Il](?=\d|/|\.|\b)", "1"),
        (r"(?<=\d),(?=\d)", "."),
    ]
    for pattern, replacement in replacements:
        cleaned = re.sub(pattern, replacement, cleaned)
    # OCR occasionally appends stray digits to unicode fractions ("2¼4").
    cleaned = re.sub(r"([½¼¾⅓⅔⅛⅜⅝⅞])\d+\b", r"\1", cleaned)
    # OCR occasionally prefixes fractions with an extra slash ("/½", "/1/2").
    cleaned = re.sub(r"^/\s*(?=\d+\s*/\s*\d+|[½¼¾⅓⅔⅛⅜⅝⅞])", "", cleaned)
    # Keep mixed numbers parseable when unicode fractions are attached (e.g. "2½")
    cleaned = re.sub(r"(\d)([½¼¾⅓⅔⅛⅜⅝⅞])", r"\1 \2", cleaned)
    for symbol, value in UNICODE_FRACTIONS.items():
        cleaned = cleaned.replace(symbol, str(value))
    return cleaned


def _parse_quantity_value(text: str) -> float | None:
    cleaned = _normalize_quantity_text(text)
    if not cleaned:
        return None

    merged_fraction_match = re.fullmatch(r"([1-9])([1-9])/(\d{1,2})", cleaned)
    if merged_fraction_match:
        whole = int(merged_fraction_match.group(1))
        numerator = int(merged_fraction_match.group(2))
        denominator = int(merged_fraction_match.group(3))
        # OCR often collapses "1 1/2" to "11/2". Treat common culinary
        # fractions as mixed numbers when the denominator is plausible.
        if denominator in {2, 3, 4, 8, 16} and numerator < denominator:
            return whole + (numerator / denominator)

    if "-" in cleaned:
        parts = [part.strip() for part in cleaned.split("-", 1)]
        if len(parts) == 2:
            first = _parse_quantity_value(parts[0])
            second = _parse_quantity_value(parts[1])
            if first is not None and second is not None:
                return (first + second) / 2.0

    if "/" in cleaned:
        parts = [part.strip() for part in cleaned.split("/", 1)]
        if len(parts) == 2:
            try:
                numerator = float(parts[0])
                denominator = float(parts[1])
                if denominator != 0:
                    return numerator / denominator
            except ValueError:
                pass

    parts = [part for part in cleaned.split() if part]
    if len(parts) == 2:
        try:
            whole = float(parts[0])
        except ValueError:
            whole = None
        if whole is not None:
            frac = _parse_quantity_value(parts[1])
            if frac is not None:
                return whole + frac

    try:
        return float(cleaned)
    except ValueError:
        return None


def _parse_unit_token(unit_text: str) -> str | None:
    token = unit_text.strip()
    token = token.replace("$", "s").replace("5", "s").replace("0", "o")
    token = re.sub(r"^[^A-Za-z0-9]+|[^A-Za-z0-9]+$", "", token)
    if token == "T":
        return "tbsp"
    normalized = token.lower()
    normalized = normalized.replace("1b", "lb").replace("ib", "lb")
    normalized = normalized.replace("tb5p", "tbsp").replace("t5p", "tsp")
    return UNIT_ALIASES.get(normalized)


_QUANTITY_EXPR = r"[\d\s½¼¾⅓⅔⅛⅜⅝⅞/\.-]+"


def _normalize_quantity_unit_spacing(text: str) -> str:
    normalized = text
    # Normalize compact forms like "800g", "12oz", and "1lb12oz".
    normalized = re.sub(r"(?<=\d)(?=[A-Za-z])", " ", normalized)
    normalized = re.sub(r"(?<=[A-Za-z])(?=\d)", " ", normalized)
    # Normalize slash alternatives like "800g/1lb" while keeping "1/2" fractions intact.
    normalized = re.sub(r"(?<=[A-Za-z])\s*/\s*(?=\d)", " / ", normalized)
    normalized = re.sub(r"\s+", " ", normalized).strip()
    return normalized


def _normalize_ocr_ingredient_text(text: str) -> str:
    normalized = text
    replacements: list[tuple[str, str]] = [
        (r"^\s*[•·▪◦●\-–—]+\s*", ""),
        (r"^\s*/+\s*(?=(?:\d+\s*/\s*\d+|[½¼¾⅓⅔⅛⅜⅝⅞]))", ""),
        (r"(?<![A-Za-z])[Il](?=\s*/\s*\d)", "1"),
        (r"(?<![A-Za-z])[oO](?=\s*[.,]?\d)", "0"),
        (r"\btb\s*5\s*p\b", "tbsp"),
        (r"\bt\s*5\s*p\b", "tsp"),
        (r"\b[1iI]b\b", "lb"),
    ]
    for pattern, replacement in replacements:
        normalized = re.sub(pattern, replacement, normalized)
    return normalized


def _is_quantity_prefix_token(token: str) -> bool:
    stripped = token.strip()
    if not stripped:
        return False
    if stripped == "/":
        return True
    cleaned = re.sub(r"^[^A-Za-z0-9½¼¾⅓⅔⅛⅜⅝⅞/.-]+|[^A-Za-z0-9½¼¾⅓⅔⅛⅜⅝⅞/.-]+$", "", stripped)
    if not cleaned:
        return False
    if _parse_quantity_value(cleaned) is not None:
        return True
    return _parse_unit_token(cleaned) is not None


def _parse_quantity_segment(segment_text: str) -> list[dict[str, Any]]:
    tokens = [token for token in segment_text.split() if token]
    quantities: list[dict[str, Any]] = []
    idx = 0

    while idx < len(tokens):
        value: float | None = None
        consumed = 0

        if idx + 1 < len(tokens):
            second_token = tokens[idx + 1]
            if _parse_unit_token(second_token) is None:
                mixed_candidate = f"{tokens[idx]} {second_token}"
                mixed_value = _parse_quantity_value(mixed_candidate)
                if mixed_value is not None:
                    value = mixed_value
                    consumed = 2

        if value is None:
            single_value = _parse_quantity_value(tokens[idx])
            if single_value is None:
                break
            value = single_value
            consumed = 1

        idx += consumed

        unit = "whole"
        if idx < len(tokens):
            parsed_unit = _parse_unit_token(tokens[idx])
            if parsed_unit is not None:
                unit = parsed_unit
                idx += 1

        quantities.append(
            {
                "value": round(float(value), 4),
                "upperValue": None,
                "unit": unit,
            }
        )

    return quantities


def _parse_slash_quantity_ingredient(
    cleaned: str,
) -> tuple[str, dict[str, Any] | None, list[dict[str, Any]], str | None] | None:
    if "/" not in cleaned:
        return None

    tokens = [token for token in cleaned.split() if token]
    if len(tokens) < 4:
        return None

    prefix_tokens: list[str] = []
    split_at = 0
    for idx, token in enumerate(tokens):
        if _is_quantity_prefix_token(token):
            prefix_tokens.append(token)
            split_at = idx + 1
            continue
        break

    if not prefix_tokens or "/" not in prefix_tokens:
        return None
    if split_at >= len(tokens):
        return None

    ingredient_name = _clean_text(" ".join(tokens[split_at:]))
    if not ingredient_name:
        return None

    prefix_text = " ".join(prefix_tokens)
    segments = [segment.strip() for segment in prefix_text.split("/") if segment.strip()]
    if len(segments) < 2:
        return None

    quantities: list[dict[str, Any]] = []
    for segment in segments:
        segment_quantities = _parse_quantity_segment(segment)
        if not segment_quantities:
            return None
        quantities.extend(segment_quantities)

    if not quantities:
        return None
    return ingredient_name, quantities[0], quantities[1:], None


def _parse_range_ingredient(
    cleaned: str,
) -> tuple[str, dict[str, Any] | None, list[dict[str, Any]], str | None] | None:
    match = re.match(
        rf"^({_QUANTITY_EXPR})\s*(?:to|-|–|—)\s*({_QUANTITY_EXPR})\s+([A-Za-z]+[\.,]?)\s+(.*)$",
        cleaned,
        flags=re.IGNORECASE,
    )
    if not match:
        return None

    lower_text = match.group(1).strip()
    upper_text = match.group(2).strip()
    unit_text = match.group(3).strip()
    remaining = _clean_text(match.group(4))

    lower_value = _parse_quantity_value(lower_text)
    upper_value = _parse_quantity_value(upper_text)
    if lower_value is None or upper_value is None:
        return None
    if not remaining:
        return None

    parsed_unit = _parse_unit_token(unit_text)
    name = remaining
    if parsed_unit is None:
        # Handle forms like "3 to 4 garlic cloves" where the unit is the next token.
        next_match = re.match(r"^([A-Za-z]+[\.,]?)(?:\s+(.*))?$", remaining)
        if next_match:
            next_unit_text = next_match.group(1).strip()
            next_unit = _parse_unit_token(next_unit_text)
            if next_unit is not None:
                rest_after_next = _clean_text(next_match.group(2) or "")
                name = _clean_text(f"{unit_text} {rest_after_next}")
                parsed_unit = next_unit
            else:
                name = _clean_text(f"{unit_text} {remaining}")
        else:
            name = _clean_text(f"{unit_text} {remaining}")
    if parsed_unit is None:
        parsed_unit = "whole"

    lower = min(lower_value, upper_value)
    upper = max(lower_value, upper_value)
    return (
        name,
        {
            "value": round(float(lower), 4),
            "upperValue": round(float(upper), 4),
            "unit": parsed_unit,
        },
        [],
        None,
    )


def _parse_mixed_unit_ingredient(
    cleaned: str,
) -> tuple[str, dict[str, Any] | None, list[dict[str, Any]], str | None] | None:
    match = re.match(
        rf"^({_QUANTITY_EXPR})\s+([A-Za-z]+[\.,]?)\s*(plus|and|&|\+)\s*({_QUANTITY_EXPR})\s+([A-Za-z]+[\.,]?)\s+(.*)$",
        cleaned,
        flags=re.IGNORECASE,
    )
    if not match:
        return None

    first_qty = match.group(1).strip()
    first_unit = match.group(2).strip()
    connector = match.group(3).strip()
    second_qty = match.group(4).strip()
    second_unit = match.group(5).strip()
    remaining = _clean_text(match.group(6))

    if not remaining:
        return None
    if _parse_quantity_value(first_qty) is None or _parse_quantity_value(second_qty) is None:
        return None
    if _parse_unit_token(first_unit) is None or _parse_unit_token(second_unit) is None:
        return None

    first_value = _parse_quantity_value(first_qty)
    second_value = _parse_quantity_value(second_qty)
    normalized_first = _parse_unit_token(first_unit)
    normalized_second = _parse_unit_token(second_unit)
    if first_value is None or second_value is None or normalized_first is None or normalized_second is None:
        return None

    primary = {
        "value": round(float(first_value), 4),
        "upperValue": None,
        "unit": normalized_first,
    }
    additional = [
        {
            "value": round(float(second_value), 4),
            "upperValue": None,
            "unit": normalized_second,
        }
    ]
    return remaining, primary, additional, None


def _parse_ingredient_text(raw: str) -> tuple[str, dict[str, Any] | None, list[dict[str, Any]], str | None]:
    cleaned = _normalize_quantity_unit_spacing(_normalize_ocr_ingredient_text(_clean_text(raw)))

    # Guard against mis-labeled numbered instructions showing up as ingredients.
    if re.match(r"^\d+\s*[.)]\s+[A-Za-z]", cleaned):
        return cleaned, None, [], None

    ranged = _parse_range_ingredient(cleaned)
    if ranged is not None:
        return ranged

    mixed = _parse_mixed_unit_ingredient(cleaned)
    if mixed is not None:
        return mixed

    slash_alt = _parse_slash_quantity_ingredient(cleaned)
    if slash_alt is not None:
        return slash_alt

    # Approximate app regex: quantity + optional unit + rest of ingredient line.
    match = re.match(r"^([\d\s½¼¾⅓⅔⅛⅜⅝⅞/\.-]+)\s*([A-Za-z]+[\.,]?)?\s+(.*)$", cleaned)
    if not match:
        return cleaned, None, [], None

    qty_text = match.group(1).strip()
    unit_text = (match.group(2) or "").strip()
    remaining = match.group(3).strip()

    value = _parse_quantity_value(qty_text)
    if value is None:
        return cleaned, None, [], None

    parsed_unit = _parse_unit_token(unit_text) if unit_text else None
    if parsed_unit is None:
        # If the token after the quantity is not a recognized unit
        # (e.g., "3 garlic cloves"), try parsing the next token as unit.
        next_match = re.match(r"^([A-Za-z]+[\.,]?)(?:\s+(.*))?$", remaining)
        if unit_text and next_match:
            next_unit_text = next_match.group(1).strip()
            next_unit = _parse_unit_token(next_unit_text)
            if next_unit is not None:
                rest_after_next = _clean_text(next_match.group(2) or "")
                name = _clean_text(f"{unit_text} {rest_after_next}")
                unit = next_unit
            else:
                name = _clean_text(f"{unit_text} {remaining}")
                unit = "whole"
        elif unit_text:
            name = _clean_text(f"{unit_text} {remaining}")
            unit = "whole"
        else:
            name = remaining if remaining else cleaned
            unit = "whole"
    else:
        unit = parsed_unit
        name = remaining if remaining else cleaned
    quantity_payload = {
        "value": round(float(value), 4),
        "upperValue": None,
        "unit": unit,
    }
    return name, quantity_payload, [], None


def _infer_sauce_section_split(ingredients: list[dict[str, Any]], steps: list[dict[str, Any]]) -> None:
    if len(ingredients) < 6:
        return
    if any((item.get("section") or None) is not None for item in ingredients):
        return

    step_text = " ".join(str(item.get("text", "")).lower() for item in steps)
    # Require "sauce" as a standalone word; avoid false positives like "saucepan".
    if re.search(r"\bsauce\b", step_text) is None:
        return

    split_index: int | None = None
    split_name = "Sauce"
    for idx, item in enumerate(ingredients[:-2]):
        name = _clean_text(str(item.get("name", "")).lower())
        if not name:
            continue
        # Only treat short marker-only lines as split signals.
        marker = re.sub(r"\([^)]*\)", "", name)
        marker = re.sub(r"\s+", " ", marker).strip(" :;,-")
        if not marker:
            continue
        if re.fullmatch(r"(?:for (?:the )?sauce|sauce)", marker):
            split_index = idx + 1
            split_name = "Sauce"
            break
        if re.fullmatch(r"(?:for serving|to serve|for garnish)", marker):
            split_index = idx + 1
            split_name = "For Serving"
            break

    if split_index is None:
        return
    if split_index < 2 or (len(ingredients) - split_index) < 2:
        return

    for idx, item in enumerate(ingredients):
        item["section"] = None if idx < split_index else split_name


def _looks_like_recipe_title(text: str) -> bool:
    cleaned = _clean_text(text)
    if not cleaned:
        return False

    if _extract_tips_remainder(cleaned) is not None:
        return False

    if _looks_like_ingredient_line(cleaned):
        return False

    if _extract_metadata_line(cleaned) is not None:
        return False
    if re.search(r"\b(?:prep(?:ping)?|preparation|cook(?:ing)?|total)\s*tim(?:e)?\b", cleaned, flags=re.IGNORECASE):
        return False

    if _header_section_type(cleaned) is not None:
        return False

    if re.match(r"^\s*[-•*]\s+", cleaned):
        return False

    if cleaned.endswith("."):
        return False

    if re.match(r"^(?:for|feel|use)\b", cleaned, flags=re.IGNORECASE):
        return False

    if "," in cleaned and len(cleaned.split()) > 8:
        return False

    if re.match(
        r"^(?:preheat|mix|add|bake|cook|stir|whisk|combine|toss|rest|serve|simmer|boil)\b",
        cleaned,
        flags=re.IGNORECASE,
    ):
        return False

    words = re.findall(r"[A-Za-z][A-Za-z'&-]*", cleaned)
    if len(words) < 2 or len(words) > 16:
        return False

    return True


def _looks_like_step_continuation(previous_text: str, current_text: str) -> bool:
    prev = _clean_text(previous_text)
    curr = _clean_text(current_text)
    if not prev or not curr:
        return False

    if re.match(r"^\d+\s*[.)]\s+", curr):
        return False

    if _looks_like_subsection_header(curr):
        return False

    if prev.endswith((".", "!", "?")):
        return False

    if prev.endswith((",", ";", "-", "–", "—", "/")):
        return True

    if prev.count("(") > prev.count(")"):
        return True

    if re.match(r"^(?:and|or|then|plus|also)\b", curr, flags=re.IGNORECASE):
        return True

    if re.match(r"^[a-z(\\[\"'/-]", curr):
        return True

    return False


def _merge_wrapped_steps(steps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for item in steps:
        text = _clean_text(str(item.get("text", "")))
        if not text:
            continue
        section = item.get("section")

        if merged:
            previous = merged[-1]
            if previous.get("section") == section and _looks_like_step_continuation(str(previous.get("text", "")), text):
                previous_text = _clean_text(str(previous.get("text", "")))
                previous["text"] = _clean_text(f"{previous_text} {text}")
                previous["timers"] = _extract_timers(str(previous["text"]))
                continue

        merged.append(
            {
                "index": len(merged),
                "text": text,
                "timers": _extract_timers(text),
                "section": section,
            }
        )

    for idx, item in enumerate(merged):
        item["index"] = idx
    return merged


def _looks_like_ingredient_continuation(previous: dict[str, Any], current: dict[str, Any]) -> bool:
    if previous.get("section") != current.get("section"):
        return False

    if current.get("quantity") is not None:
        return False

    if current.get("additionalQuantities"):
        return False

    prev_name = _clean_text(str(previous.get("name", "")))
    curr_name = _clean_text(str(current.get("name", "")))
    if not prev_name or not curr_name:
        return False

    if prev_name.endswith((",", ";", "-", "(", "/")):
        return True

    if re.match(r"^(?:and|or|to|for|of|with|plus)\b", curr_name, flags=re.IGNORECASE):
        return True

    if re.match(r"^\d+-[A-Za-z]", curr_name):
        return True

    if curr_name[0].islower():
        return True

    return False


def _merge_wrapped_ingredients(ingredients: list[dict[str, Any]]) -> list[dict[str, Any]]:
    merged: list[dict[str, Any]] = []
    for item in ingredients:
        name = _clean_text(str(item.get("name", "")))
        if not name:
            continue

        normalized = dict(item)
        normalized["name"] = name

        if merged and _looks_like_ingredient_continuation(merged[-1], normalized):
            previous = merged[-1]
            previous_name = _clean_text(str(previous.get("name", "")))
            previous["name"] = _clean_text(f"{previous_name} {name}")
            continue

        merged.append(normalized)

    return merged


def _assemble_app_recipe(
    rows: list[dict[str, Any]],
    *,
    source_url: str = "",
    source_title: str = "",
) -> dict[str, Any]:
    title = ""
    current_section = "unknown"
    current_ingredient_section: str | None = None
    current_step_section: str | None = None

    ingredients: list[dict[str, Any]] = []
    steps: list[dict[str, Any]] = []
    notes: list[str] = []

    ingredient_sections: dict[str, list[str]] = {}
    step_sections: dict[str, list[str]] = {}
    ingredient_section_order: list[str] = []
    step_section_order: list[str] = []
    parsed_ingredient_count = 0
    extracted_yields: str | None = None
    prep_minutes: int | None = None
    cook_minutes: int | None = None
    total_minutes: int | None = None

    def section_key(name: str | None) -> str:
        return name if name else "Main"

    def add_ingredient(text: str, section_name: str | None) -> None:
        nonlocal parsed_ingredient_count
        name, quantity, additional_quantities, note = _parse_ingredient_text(text)
        name = _sanitize_ingredient_name(name)
        if _should_drop_ingredient_entry(name, quantity):
            return
        ingredient_entry = {
            "name": name,
            "quantity": quantity,
            "additionalQuantities": additional_quantities,
            "note": note,
            "section": section_name,
        }
        ingredients.append(ingredient_entry)
        if quantity is not None:
            parsed_ingredient_count += 1
        parsed_ingredient_count += len(additional_quantities)
        key = section_key(section_name)
        if key not in ingredient_sections:
            ingredient_sections[key] = []
            ingredient_section_order.append(key)
        ingredient_sections[key].append(name)

    def add_step(text: str, section_name: str | None) -> None:
        step_text = _strip_step_number_prefix(text)
        if not step_text:
            return
        if _is_ocr_artifact_line(step_text):
            return
        timers = _extract_timers(step_text)
        steps.append(
            {
                "index": len(steps),
                "text": step_text,
                "timers": timers,
                "section": section_name,
            }
        )
        key = section_key(section_name)
        if key not in step_sections:
            step_sections[key] = []
            step_section_order.append(key)
        step_sections[key].append(step_text)

    for row in rows:
        text = _clean_text(str(row.get("text", "")))
        label = str(row.get("label", "")).strip().lower()
        if not text or label not in LABELS:
            continue

        metadata = _extract_metadata_line(text)
        if metadata is not None:
            if metadata.get("yields"):
                extracted_yields = str(metadata["yields"])
            if metadata.get("total_minutes") is not None:
                total_minutes = int(metadata["total_minutes"])
            if metadata.get("prep_minutes") is not None:
                prep_minutes = int(metadata["prep_minutes"])
            if metadata.get("cook_minutes") is not None:
                cook_minutes = int(metadata["cook_minutes"])
            continue

        if _is_ocr_artifact_line(text):
            continue

        tips_remainder = _extract_tips_remainder(text)
        if tips_remainder is not None:
            current_section = "notes"
            note_line = _normalize_note_text(tips_remainder)
            if note_line:
                notes.append(note_line)
            continue

        if current_section == "notes" and label in {"ingredient", "step", "note"} and _looks_like_note_fragment(text):
            current_section = "notes"
            note_line = _normalize_note_text(text)
            if note_line:
                notes.append(note_line)
            continue

        if label == "title" and not title:
            if _looks_like_recipe_title(text):
                title = text
            else:
                notes.append(text)
            continue

        if label == "header":
            section_type = _header_section_type(text)
            if section_type == "ingredients":
                current_section = "ingredients"
                current_ingredient_section = None
                continue
            if section_type == "steps":
                current_section = "steps"
                current_step_section = None
                continue
            if section_type == "notes":
                current_section = "notes"
                continue

            if _looks_like_subsection_header(text):
                subsection = _clean_text(text.rstrip(":"))
                if current_section == "steps":
                    current_step_section = subsection
                elif current_section == "notes":
                    notes.append(text)
                else:
                    current_section = "ingredients"
                    current_ingredient_section = subsection
                continue

            # Recovery path: model occasionally labels plain ingredient lines as headers
            # (e.g., "Butter and sugar, for the pan"). Keep these in ingredient context.
            if current_section == "ingredients":
                if _looks_like_headerless_instruction(text):
                    current_section = "steps"
                    add_step(text, current_step_section)
                else:
                    add_ingredient(text, current_ingredient_section)
                continue

            continue

        if label == "ingredient":
            if current_section == "notes" and _looks_like_note_fragment(text):
                note_line = _normalize_note_text(text)
                if note_line:
                    notes.append(note_line)
                continue
            if current_section == "notes" and _looks_like_step_fragment(text):
                current_section = "steps"
                add_step(text, current_step_section)
                continue
            if current_section == "ingredients" and _looks_like_headerless_instruction(text):
                current_section = "steps"
                add_step(text, current_step_section)
            elif current_section == "steps" and not _looks_like_ingredient_line(text):
                current_section = "steps"
                add_step(text, current_step_section)
            else:
                current_section = "ingredients"
                add_ingredient(text, current_ingredient_section)
            continue

        if label == "step":
            if current_section == "notes" and _looks_like_note_fragment(text):
                note_line = _normalize_note_text(text)
                if note_line:
                    notes.append(note_line)
                continue
            current_section = "steps"
            for step_text in _split_numbered_steps(text):
                add_step(step_text, current_step_section)
            continue

        if label == "note":
            if _looks_like_step_fragment(text):
                current_section = "steps"
                add_step(text, current_step_section)
                continue
            current_section = "notes"
            note_line = _normalize_note_text(text)
            if note_line:
                notes.append(note_line)
            continue

        if not title and label != "junk":
            if _looks_like_recipe_title(text):
                title = text

    if not title or not _looks_like_recipe_title(title):
        for row in rows:
            text = _clean_text(str(row.get("text", "")))
            label = str(row.get("label", "")).strip().lower()
            if label not in LABELS or not text:
                continue
            if _looks_like_recipe_title(text):
                title = text
                break

    if not title or not _looks_like_recipe_title(title):
        for idx, note in enumerate(notes):
            if _looks_like_recipe_title(note):
                title = _clean_text(note)
                notes.pop(idx)
                break

    if not title:
        title = "Untitled Recipe"

    ingredients = _merge_wrapped_ingredients(ingredients)
    steps = _merge_wrapped_steps(steps)
    _infer_sauce_section_split(ingredients, steps)

    ingredient_sections.clear()
    ingredient_section_order.clear()
    for item in ingredients:
        key = section_key(item.get("section"))
        if key not in ingredient_sections:
            ingredient_sections[key] = []
            ingredient_section_order.append(key)
        ingredient_sections[key].append(str(item.get("name", "")).strip())

    step_sections.clear()
    step_section_order.clear()
    for item in steps:
        key = section_key(item.get("section"))
        if key not in step_sections:
            step_sections[key] = []
            step_section_order.append(key)
        step_sections[key].append(str(item.get("text", "")).strip())

    ingredient_sections_out = [
        {"name": None if key == "Main" else key, "items": ingredient_sections[key]}
        for key in ingredient_section_order
    ]
    step_sections_out = [
        {"name": None if key == "Main" else key, "items": step_sections[key]}
        for key in step_section_order
    ]

    if title:
        normalized_title = _clean_text(title).casefold()
        notes = [note for note in notes if _clean_text(note).casefold() != normalized_title]

    notes_text = "\n".join(notes).strip()
    resolved_source_title = source_title or _default_source_title(source_url)
    resolved_total_minutes = total_minutes
    if resolved_total_minutes is None:
        if prep_minutes is not None and cook_minutes is not None:
            resolved_total_minutes = prep_minutes + cook_minutes
        elif cook_minutes is not None:
            resolved_total_minutes = cook_minutes
        elif prep_minutes is not None:
            resolved_total_minutes = prep_minutes

    return {
        "title": title or "Untitled Recipe",
        "sourceURL": source_url or None,
        "sourceTitle": resolved_source_title,
        "yields": extracted_yields or "4 servings",
        "totalMinutes": resolved_total_minutes,
        "ingredients": ingredients,
        "steps": steps,
        "notes": notes_text or None,
        "ingredientSections": ingredient_sections_out,
        "stepSections": step_sections_out,
        "stats": {
            "ingredient_count": len(ingredients),
            "ingredient_parsed_quantity_count": parsed_ingredient_count,
            "step_count": len(steps),
            "note_count": len(notes),
            "ingredient_section_count": len(ingredient_sections_out),
            "step_section_count": len(step_sections_out),
        },
    }


def _normalize_lines(text: str, max_lines: int = 400) -> tuple[list[str], bool]:
    lines = [line.strip() for line in text.splitlines()]
    lines = [line for line in lines if line]
    truncated = False
    if len(lines) > max_lines:
        lines = lines[:max_lines]
        truncated = True
    return lines, truncated


def _fetch_url_text(url: str) -> tuple[str, dict[str, Any]]:
    req = urllib_request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
        },
    )
    with urllib_request.urlopen(req, timeout=20) as resp:
        body = resp.read().decode("utf-8", errors="replace")

    extracted = _extract_recipe_from_jsonld(body)
    if extracted:
        lines, meta = extracted
        return ("\n".join(lines), meta)

    fragment = _extract_main_html_fragment(body)
    parser = _VisibleTextExtractor()
    parser.feed(fragment)
    parsed = parser.text()
    parsed = parsed.replace(". ", ".\n")

    title = _extract_title_from_html(body)
    if title:
        parsed = title + "\n" + parsed
    return (
        parsed,
        {
            "method": "html_visible_text",
            "title": title,
        },
    )


def _run_apple_vision_ocr(image_bytes: bytes, image_name: str) -> str:
    if not APPLE_OCR_SWIFT_SCRIPT.exists():
        raise RuntimeError(f"Missing Apple OCR script: {APPLE_OCR_SWIFT_SCRIPT}")

    suffix = Path(image_name or "upload.png").suffix or ".png"
    LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=suffix, dir=LOCAL_TMP_DIR, delete=False) as tmp:
        tmp.write(image_bytes)
        tmp_path = Path(tmp.name)

    try:
        proc = subprocess.run(
            ["xcrun", "swift", str(APPLE_OCR_SWIFT_SCRIPT), str(tmp_path)],
            capture_output=True,
            text=True,
            timeout=45,
            check=False,
        )
        if proc.returncode != 0:
            stderr = proc.stderr.strip() or proc.stdout.strip() or "Unknown Apple Vision OCR error"
            raise RuntimeError(stderr)
        text = proc.stdout or ""
        if not text.strip():
            raise RuntimeError("Apple Vision OCR returned no text")
        return text
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass


def _run_tesseract(image_bytes: bytes, image_name: str) -> str:
    suffix = Path(image_name or "upload.png").suffix or ".png"
    LOCAL_TMP_DIR.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=suffix, dir=LOCAL_TMP_DIR, delete=False) as tmp:
        tmp.write(image_bytes)
        tmp_path = Path(tmp.name)

    def _ocr_score(text: str) -> float:
        lines = [line.strip() for line in str(text).splitlines() if line.strip()]
        if not lines:
            return 0.0

        ingredient_like = sum(1 for line in lines if _looks_like_ingredient_line(line))
        action_like = sum(
            1
            for line in lines
            if re.match(
                r"^(?:\d+\s*[.)]\s*)?(?:preheat|add|mix|stir|bake|cook|whisk|combine|simmer|serve)\b",
                line.strip(),
                flags=re.IGNORECASE,
            )
        )
        noisy = sum(1 for line in lines if re.search(r"[{}<>_=]{2,}", line))

        return (ingredient_like * 1.6) + (action_like * 1.2) + (len(lines) * 0.3) - (noisy * 2.0)

    try:
        candidates: list[tuple[float, str, str]] = []
        base_args = ["--oem", "1", "-l", "eng", "-c", "preserve_interword_spaces=1"]
        configs = [
            ("psm4", ["--psm", "4"]),
            ("psm6", ["--psm", "6"]),
            ("psm3", ["--psm", "3"]),
            ("psm11", ["--psm", "11"]),
            ("psm12", ["--psm", "12"]),
        ]

        for tag, args in configs:
            proc = subprocess.run(
                ["tesseract", str(tmp_path), "stdout", *base_args, *args],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            if proc.returncode != 0:
                continue
            text = proc.stdout or ""
            score = _ocr_score(text)
            candidates.append((score, tag, text))

        if not candidates:
            proc = subprocess.run(
                ["tesseract", str(tmp_path), "stdout", *base_args, "--psm", "6"],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            stderr = proc.stderr.strip() or "Unknown OCR error"
            raise RuntimeError(f"tesseract failed: {stderr}")

        candidates.sort(key=lambda item: item[0], reverse=True)
        return candidates[0][2]
    finally:
        try:
            tmp_path.unlink(missing_ok=True)
        except OSError:
            pass


def _run_image_ocr(image_bytes: bytes, image_name: str) -> tuple[str, str]:
    engine = OCR_ENGINE if OCR_ENGINE in {"apple", "tesseract", "auto"} else "apple"
    apple_error: str | None = None

    if engine in {"apple", "auto"}:
        try:
            return _run_apple_vision_ocr(image_bytes, image_name), "ocr_apple_vision"
        except Exception as exc:  # noqa: BLE001
            apple_error = str(exc)
            if engine == "auto":
                pass
            else:
                # Explicit apple mode still falls back so image mode remains usable locally.
                pass

    try:
        method = "ocr_tesseract" if apple_error is None else "ocr_tesseract_fallback"
        return _run_tesseract(image_bytes, image_name), method
    except Exception as tesseract_exc:  # noqa: BLE001
        if apple_error is not None:
            raise RuntimeError(f"Apple OCR failed: {apple_error} | Tesseract failed: {tesseract_exc}") from tesseract_exc
        raise
