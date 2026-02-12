#!/usr/bin/env python3
"""Shared dataset and modeling utilities for recipe line classification."""

from __future__ import annotations

import hashlib
import json
import math
import pickle
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

LABELS: Tuple[str, ...] = ("title", "ingredient", "step", "note", "header", "junk")
REQUIRED_RECIPE_FIELDS: Tuple[str, ...] = ("title", "ingredients", "steps", "notes")


@dataclass(frozen=True)
class LineRow:
    doc_id: str
    line_index: int
    text: str
    label: str


@dataclass(frozen=True)
class DatasetDocument:
    doc_id: str
    source_type: str
    normalized_lines: List[str]
    target_recipe: Dict[str, Any]


@dataclass
class ValidationResult:
    is_valid: bool
    errors: List[str]
    label_counts: Dict[str, int]
    source_counts: Dict[str, int]


def _sorted_json_files(directory: Path, suffix: str) -> List[Path]:
    return sorted(p for p in directory.glob(f"*{suffix}") if p.is_file())


def load_documents(data_dir: Path) -> Dict[str, DatasetDocument]:
    docs_dir = data_dir / "documents"
    docs: Dict[str, DatasetDocument] = {}

    for path in _sorted_json_files(docs_dir, ".doc.json"):
        payload = json.loads(path.read_text(encoding="utf-8"))
        doc_id = payload["id"]
        docs[doc_id] = DatasetDocument(
            doc_id=doc_id,
            source_type=payload["source_type"],
            normalized_lines=list(payload["normalized_lines"]),
            target_recipe=dict(payload["target_recipe"]),
        )

    return docs


def _matches_prefix(doc_id: str, prefixes: Iterable[str] | None) -> bool:
    if not prefixes:
        return False
    for raw in prefixes:
        prefix = str(raw).strip()
        if prefix and doc_id.startswith(prefix):
            return True
    return False


def load_line_rows(
    data_dir: Path,
    *,
    include_doc_prefixes: Iterable[str] | None = None,
    exclude_doc_prefixes: Iterable[str] | None = None,
) -> List[LineRow]:
    lines_dir = data_dir / "lines"
    rows: List[LineRow] = []

    for path in _sorted_json_files(lines_dir, ".lines.jsonl"):
        doc_id = path.name.replace(".lines.jsonl", "")
        if include_doc_prefixes and not _matches_prefix(doc_id, include_doc_prefixes):
            continue
        if exclude_doc_prefixes and _matches_prefix(doc_id, exclude_doc_prefixes):
            continue
        for raw_line in path.read_text(encoding="utf-8").splitlines():
            if not raw_line.strip():
                continue
            payload = json.loads(raw_line)
            rows.append(
                LineRow(
                    doc_id=doc_id,
                    line_index=int(payload["line_index"]),
                    text=str(payload["text"]),
                    label=str(payload["label"]),
                )
            )

    rows.sort(key=lambda row: (row.doc_id, row.line_index))
    return rows


def validate_dataset(data_dir: Path) -> ValidationResult:
    documents = load_documents(data_dir)
    rows = load_line_rows(data_dir)

    errors: List[str] = []
    label_counts: Counter[str] = Counter()
    source_counts: Counter[str] = Counter()
    rows_by_doc: Dict[str, List[LineRow]] = defaultdict(list)

    for row in rows:
        rows_by_doc[row.doc_id].append(row)
        label_counts[row.label] += 1
        if row.label not in LABELS:
            errors.append(f"Invalid label '{row.label}' in doc '{row.doc_id}' at line_index={row.line_index}")

    if not documents:
        errors.append("No document-level fixture files found under documents/*.doc.json")

    for doc_id, doc in sorted(documents.items()):
        source_counts[doc.source_type] += 1

        for field in REQUIRED_RECIPE_FIELDS:
            if field not in doc.target_recipe:
                errors.append(f"Doc '{doc_id}' missing target_recipe field '{field}'")

        doc_rows = rows_by_doc.get(doc_id)
        if not doc_rows:
            errors.append(f"Doc '{doc_id}' has no matching line-level file '{doc_id}.lines.jsonl'")
            continue

        if len(doc.normalized_lines) != len(doc_rows):
            errors.append(
                f"Doc '{doc_id}' has {len(doc.normalized_lines)} normalized_lines but {len(doc_rows)} line labels"
            )

        seen_indices = {row.line_index for row in doc_rows}
        expected_indices = set(range(len(doc_rows)))
        if seen_indices != expected_indices:
            errors.append(f"Doc '{doc_id}' line_index values must be contiguous from 0 to {len(doc_rows) - 1}")

        for row in doc_rows:
            if row.line_index < len(doc.normalized_lines):
                expected_text = doc.normalized_lines[row.line_index]
                if expected_text != row.text:
                    errors.append(
                        "Doc '%s' mismatch at line_index=%d (document text != line-level text)"
                        % (doc_id, row.line_index)
                    )

    for row_doc in sorted(rows_by_doc.keys()):
        if row_doc not in documents:
            errors.append(f"Line labels exist for unknown doc '{row_doc}'")

    for label in LABELS:
        label_counts.setdefault(label, 0)

    return ValidationResult(
        is_valid=not errors,
        errors=errors,
        label_counts=dict(sorted(label_counts.items())),
        source_counts=dict(sorted(source_counts.items())),
    )


def normalize_for_features(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"^\d+[.):-]\s*", "", text)
    text = re.sub(r"^[•●○◦▪▫\-]+\s*", "", text)
    return text


def extract_features(text: str) -> Counter[str]:
    normalized = normalize_for_features(text)
    tokens = re.findall(r"[a-z0-9]+", normalized)

    features: Counter[str] = Counter()

    for token in tokens:
        features[f"tok:{token}"] += 1

    for i in range(len(tokens) - 1):
        features[f"tok2:{tokens[i]}_{tokens[i + 1]}"] += 1

    compact = re.sub(r"\s+", " ", normalized)
    for n in (3, 4, 5):
        if len(compact) < n:
            continue
        for i in range(len(compact) - n + 1):
            gram = compact[i : i + n]
            if "  " in gram:
                continue
            features[f"chr{n}:{gram}"] += 1

    # Small structural hints.
    if normalized.endswith(":"):
        features["shape:ends_colon"] += 1
    if any(char.isdigit() for char in normalized):
        features["shape:has_digit"] += 1
    if normalized.startswith("note") or normalized.startswith("tip"):
        features["shape:starts_note"] += 1
    if normalized.startswith("<") and normalized.endswith(">"):
        features["shape:tag_like"] += 1

    return features


_ACTION_PREFIXES = (
    "add",
    "bake",
    "beat",
    "boil",
    "brown",
    "chop",
    "combine",
    "cook",
    "fold",
    "heat",
    "let",
    "marinate",
    "mash",
    "mix",
    "pat",
    "pour",
    "preheat",
    "refrigerate",
    "rest",
    "roast",
    "saute",
    "serve",
    "simmer",
    "spread",
    "stir",
    "toast",
    "toss",
    "whisk",
)

_NOTE_PREFIXES = (
    "note",
    "notes",
    "tip",
    "tips",
    "chef's note",
    "variation",
    "variations",
    "storage",
)

_HEADER_KEYWORDS = (
    "ingredients",
    "ingredient",
    "instructions",
    "instruction",
    "directions",
    "direction",
    "steps",
    "step",
    "method",
)

_INGREDIENT_HEADER_KEYWORDS = (
    "ingredient",
    "ingredients",
    "for the ingredients",
    "what you'll need",
)

_STEP_HEADER_KEYWORDS = (
    "instruction",
    "instructions",
    "direction",
    "directions",
    "step",
    "steps",
    "method",
    "preparation",
)

_INGREDIENT_HINTS = (
    "to taste",
    "for garnish",
    "optional",
    "divided",
    "melted",
)


def rule_based_label(text: str) -> Tuple[str, float] | None:
    raw = text.strip()
    normalized = normalize_for_features(text)
    compact = re.sub(r"\s+", " ", normalized).strip()
    if not compact:
        return ("junk", 0.99)

    words = compact.split()

    if compact.startswith("<") and compact.endswith(">"):
        return ("junk", 0.99)

    if compact in _HEADER_KEYWORDS:
        return ("header", 0.99)

    if compact.startswith("for the ") and compact.endswith(":"):
        return ("header", 0.97)

    if compact.endswith(":"):
        stem = compact[:-1].strip()
        if any(stem.startswith(prefix) for prefix in _NOTE_PREFIXES):
            return ("header", 0.98)
        if stem in _HEADER_KEYWORDS:
            return ("header", 0.98)
        if len(words) <= 5:
            return ("header", 0.90)

    if any(compact.startswith(prefix + ":") for prefix in _NOTE_PREFIXES):
        return ("note", 0.97)

    if any(compact.startswith(prefix + " ") for prefix in _NOTE_PREFIXES):
        return ("note", 0.95)

    if re.match(r"^[\d½¼¾⅓⅔⅛⅜⅝⅞/.\-]+\s+", compact):
        return ("ingredient", 0.95)

    if re.match(r"^\d+\s*[x×]\s+", compact):
        return ("ingredient", 0.92)

    if any(compact.startswith(prefix + " ") for prefix in _ACTION_PREFIXES):
        return ("step", 0.92)

    if len(words) >= 8:
        return ("step", 0.88)

    if any(hint in compact for hint in _INGREDIENT_HINTS):
        return ("ingredient", 0.86)

    looks_like_title = (
        len(words) >= 2
        and len(words) <= 6
        and ":" not in raw
        and not any(char.isdigit() for char in raw)
        and raw[:1].isupper()
        and raw == raw.title()
    )
    if looks_like_title:
        return ("title", 0.78)

    return None


def looks_like_note_header(text: str) -> bool:
    normalized = normalize_for_features(text).strip()
    if normalized.endswith(":"):
        normalized = normalized[:-1].strip()
    return any(normalized.startswith(prefix) for prefix in _NOTE_PREFIXES)


def _header_section_from_text(text: str) -> str | None:
    normalized = normalize_for_features(text).strip()
    if normalized.endswith(":"):
        normalized = normalized[:-1].strip()
    if normalized in _INGREDIENT_HEADER_KEYWORDS:
        return "ingredients"
    if normalized in _STEP_HEADER_KEYWORDS:
        return "steps"
    if any(normalized.startswith(prefix) for prefix in _NOTE_PREFIXES):
        return "notes"
    return None


def split_docs_for_holdout(doc_ids: Iterable[str], holdout_ratio: float = 0.25) -> Tuple[set[str], set[str]]:
    train_docs: set[str] = set()
    holdout_docs: set[str] = set()

    for doc_id in sorted(set(doc_ids)):
        digest = hashlib.sha256(doc_id.encode("utf-8")).hexdigest()
        bucket = int(digest[:8], 16) / 0xFFFFFFFF
        if bucket < holdout_ratio:
            holdout_docs.add(doc_id)
        else:
            train_docs.add(doc_id)

    # Guarantee non-empty split when dataset is very small.
    if not holdout_docs and train_docs:
        moved = sorted(train_docs)[0]
        train_docs.remove(moved)
        holdout_docs.add(moved)

    if not train_docs and holdout_docs:
        moved = sorted(holdout_docs)[0]
        holdout_docs.remove(moved)
        train_docs.add(moved)

    return train_docs, holdout_docs


def split_rows_for_holdout(rows: Iterable[LineRow], holdout_ratio: float = 0.25) -> Tuple[List[LineRow], List[LineRow]]:
    rows_by_label: Dict[str, List[LineRow]] = defaultdict(list)
    for row in rows:
        rows_by_label[row.label].append(row)

    holdout_keys: set[Tuple[str, int]] = set()

    for label, label_rows in rows_by_label.items():
        ordered = sorted(
            label_rows,
            key=lambda row: hashlib.sha256(f"{row.doc_id}:{row.line_index}".encode("utf-8")).hexdigest(),
        )
        holdout_count = max(1, int(round(len(ordered) * holdout_ratio)))
        holdout_count = min(holdout_count, len(ordered))
        for row in ordered[:holdout_count]:
            holdout_keys.add((row.doc_id, row.line_index))

    train_rows: List[LineRow] = []
    holdout_rows: List[LineRow] = []
    for row in sorted(rows, key=lambda item: (item.doc_id, item.line_index)):
        if (row.doc_id, row.line_index) in holdout_keys:
            holdout_rows.append(row)
        else:
            train_rows.append(row)

    if not train_rows and holdout_rows:
        train_rows.append(holdout_rows.pop())

    return train_rows, holdout_rows


@dataclass
class NGramNaiveBayesClassifier:
    labels: Tuple[str, ...] = LABELS
    alpha: float = 1.0

    def __post_init__(self) -> None:
        self._doc_count_by_label: Counter[str] = Counter()
        self._feature_count_by_label: Dict[str, Counter[str]] = {label: Counter() for label in self.labels}
        self._total_feature_count_by_label: Counter[str] = Counter()
        self._vocabulary: set[str] = set()
        self._is_fit = False

    def fit(self, rows: Iterable[LineRow]) -> "NGramNaiveBayesClassifier":
        for row in rows:
            if row.label not in self.labels:
                continue
            self._doc_count_by_label[row.label] += 1
            features = extract_features(row.text)
            self._feature_count_by_label[row.label].update(features)
            self._total_feature_count_by_label[row.label] += sum(features.values())
            self._vocabulary.update(features.keys())

        self._is_fit = True
        return self

    def _log_prior(self, label: str) -> float:
        total_docs = sum(self._doc_count_by_label.values())
        if total_docs == 0:
            return -1e9
        return math.log((self._doc_count_by_label[label] + self.alpha) / (total_docs + self.alpha * len(self.labels)))

    def _log_likelihood(self, label: str, features: Counter[str]) -> float:
        vocab_size = max(1, len(self._vocabulary))
        denom = self._total_feature_count_by_label[label] + self.alpha * vocab_size

        score = 0.0
        for feature, count in features.items():
            numer = self._feature_count_by_label[label][feature] + self.alpha
            score += count * math.log(numer / denom)
        return score

    def predict_with_confidence(self, text: str) -> Tuple[str, float, Dict[str, float]]:
        if not self._is_fit:
            raise RuntimeError("Model is not fit")

        heuristic = rule_based_label(text)
        if heuristic is not None:
            label, confidence = heuristic
            probs = {candidate: 0.0 for candidate in self.labels}
            probs[label] = confidence
            remaining = max(0.0, 1.0 - confidence)
            others = [candidate for candidate in self.labels if candidate != label]
            if others:
                spread = remaining / len(others)
                for candidate in others:
                    probs[candidate] = spread
            return label, confidence, probs

        features = extract_features(text)

        log_scores: Dict[str, float] = {}
        for label in self.labels:
            log_scores[label] = self._log_prior(label) + self._log_likelihood(label, features)

        best_label = max(log_scores, key=log_scores.get)

        max_log = max(log_scores.values())
        exp_scores = {label: math.exp(score - max_log) for label, score in log_scores.items()}
        normalizer = sum(exp_scores.values()) or 1.0
        probs = {label: value / normalizer for label, value in exp_scores.items()}
        confidence = probs[best_label]

        return best_label, confidence, probs

    def to_bytes(self) -> bytes:
        state = {
            "labels": self.labels,
            "alpha": self.alpha,
            "doc_count_by_label": dict(self._doc_count_by_label),
            "feature_count_by_label": {label: dict(counter) for label, counter in self._feature_count_by_label.items()},
            "total_feature_count_by_label": dict(self._total_feature_count_by_label),
            "vocabulary": sorted(self._vocabulary),
        }
        return pickle.dumps(state)

    @classmethod
    def from_bytes(cls, payload: bytes) -> "NGramNaiveBayesClassifier":
        state = pickle.loads(payload)
        model = cls(labels=tuple(state["labels"]), alpha=float(state["alpha"]))
        model._doc_count_by_label = Counter(state["doc_count_by_label"])
        model._feature_count_by_label = {
            label: Counter(features)
            for label, features in state["feature_count_by_label"].items()
        }
        model._total_feature_count_by_label = Counter(state["total_feature_count_by_label"])
        model._vocabulary = set(state["vocabulary"])
        model._is_fit = True
        return model


@dataclass
class ClassificationPrediction:
    doc_id: str
    line_index: int
    gold: str
    predicted: str
    confidence: float


def run_predictions(model: NGramNaiveBayesClassifier, rows: Iterable[LineRow]) -> List[ClassificationPrediction]:
    predictions: List[ClassificationPrediction] = []
    sorted_rows = sorted(rows, key=lambda row: (row.doc_id, row.line_index))

    previous_doc_id: str | None = None
    previous_line_text = ""
    current_section: str | None = None

    for row in sorted_rows:
        if row.doc_id != previous_doc_id:
            previous_doc_id = row.doc_id
            previous_line_text = ""
            current_section = None

        predicted, confidence, _ = model.predict_with_confidence(row.text)
        normalized = normalize_for_features(row.text).strip()

        if row.line_index == 0 and predicted != "title":
            if _header_section_from_text(row.text) is None:
                predicted = "title"
                confidence = max(confidence, 0.88)

        if looks_like_note_header(previous_line_text) and predicted != "header":
            predicted = "note"
            confidence = max(confidence, 0.90)

        if predicted == "header":
            header_section = _header_section_from_text(row.text)
            if header_section:
                current_section = header_section
            elif current_section == "steps" and not normalized.endswith(":"):
                predicted = "step"
                confidence = max(confidence, 0.82)
            elif current_section == "ingredients" and not normalized.endswith(":"):
                predicted = "ingredient"
                confidence = max(confidence, 0.82)

        if current_section == "ingredients" and row.line_index > 0 and predicted in {"step", "title", "junk"}:
            if not any(normalized.startswith(prefix + " ") for prefix in _ACTION_PREFIXES):
                predicted = "ingredient"
                confidence = max(confidence, 0.82)

        if current_section == "steps" and predicted in {"title", "ingredient"} and row.line_index > 0:
            if any(normalized.startswith(prefix + " ") for prefix in _ACTION_PREFIXES):
                predicted = "step"
                confidence = max(confidence, 0.82)

        predictions.append(
            ClassificationPrediction(
                doc_id=row.doc_id,
                line_index=row.line_index,
                gold=row.label,
                predicted=predicted,
                confidence=confidence,
            )
        )
        previous_line_text = row.text

    return predictions


def compute_metrics(predictions: Iterable[ClassificationPrediction]) -> Dict[str, Any]:
    preds = list(predictions)

    confusion: Dict[str, Dict[str, int]] = {
        gold: {pred: 0 for pred in LABELS}
        for gold in LABELS
    }
    for pred in preds:
        confusion[pred.gold][pred.predicted] += 1

    per_class: Dict[str, Dict[str, float]] = {}
    f1_values: List[float] = []

    for label in LABELS:
        tp = confusion[label][label]
        fp = sum(confusion[other][label] for other in LABELS if other != label)
        fn = sum(confusion[label][other] for other in LABELS if other != label)

        precision = tp / (tp + fp) if (tp + fp) else 0.0
        recall = tp / (tp + fn) if (tp + fn) else 0.0
        f1 = 2 * precision * recall / (precision + recall) if (precision + recall) else 0.0

        per_class[label] = {
            "precision": precision,
            "recall": recall,
            "f1": f1,
            "support": float(sum(confusion[label].values())),
        }
        f1_values.append(f1)

    macro_f1 = sum(f1_values) / len(f1_values) if f1_values else 0.0
    present_labels = [
        label
        for label in LABELS
        if float(per_class.get(label, {}).get("support", 0.0)) > 0.0
    ]
    present_f1_values = [float(per_class[label]["f1"]) for label in present_labels]
    macro_f1_present_labels = (
        sum(present_f1_values) / len(present_f1_values)
        if present_f1_values
        else macro_f1
    )

    ingredient_step_confusions = confusion["ingredient"]["step"] + confusion["step"]["ingredient"]
    total_predictions = len(preds)
    ingredient_step_confusion_rate = ingredient_step_confusions / total_predictions if total_predictions else 0.0

    return {
        "macro_f1": macro_f1,
        "macro_f1_present_labels": macro_f1_present_labels,
        "present_labels": present_labels,
        "per_class": per_class,
        "confusion": confusion,
        "ingredient_step_confusion_rate": ingredient_step_confusion_rate,
        "prediction_count": total_predictions,
    }


def save_pickle(path: Path, model: NGramNaiveBayesClassifier) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(model.to_bytes())


def load_pickle(path: Path) -> NGramNaiveBayesClassifier:
    return NGramNaiveBayesClassifier.from_bytes(path.read_bytes())
