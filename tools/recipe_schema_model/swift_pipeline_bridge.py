#!/usr/bin/env python3
"""Bridge utilities for invoking the Swift classifier+assembler pipeline."""

from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path
from typing import Any


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _swift_sources(repo_root: Path) -> list[Path]:
    return [
        repo_root / "Cauldron/Core/Services/RecipeLineClassificationService.swift",
        repo_root / "Cauldron/Core/Parsing/ModelRecipeAssembler.swift",
        repo_root / "Cauldron/Core/Parsing/RecipeParser.swift",
        repo_root / "Cauldron/Core/Parsing/Utilities/IngredientParser.swift",
        repo_root / "Cauldron/Core/Parsing/Utilities/QuantityValueParser.swift",
        repo_root / "Cauldron/Core/Parsing/Utilities/TimeParser.swift",
        repo_root / "Cauldron/Core/Parsing/Utilities/UnitParser.swift",
        repo_root / "Cauldron/Core/Models/Ingredient.swift",
        repo_root / "Cauldron/Core/Models/CookStep.swift",
        repo_root / "Cauldron/Core/Models/Quantity.swift",
        repo_root / "Cauldron/Core/Models/UnitKind.swift",
        repo_root / "Cauldron/Core/Models/TimerSpec.swift",
    ]


def _harness_source(repo_root: Path) -> str:
    model_path = str(repo_root / "Cauldron/Resources/ML/RecipeLineClassifier.mlmodelc")
    return f"""
import Foundation

func makeTempBundle(withModelAt modelPath: String) throws -> Bundle {{
    let fm = FileManager.default
    let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("RecipeSchemaHarness_\\(UUID().uuidString)", isDirectory: true)
    let bundleURL = tempRoot.appendingPathComponent("Harness.bundle", isDirectory: true)
    try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

    let infoPlistURL = bundleURL.appendingPathComponent("Info.plist")
    let plist: [String: Any] = [
        "CFBundleIdentifier": "local.harness.recipe",
        "CFBundleName": "Harness",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1.0"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: infoPlistURL)

    let src = URL(fileURLWithPath: modelPath, isDirectory: true)
    let dst = bundleURL.appendingPathComponent("RecipeLineClassifier.mlmodelc", isDirectory: true)
    try fm.copyItem(at: src, to: dst)

    guard let bundle = Bundle(url: bundleURL) else {{
        throw NSError(domain: "Harness", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to open temp bundle"])
    }}
    return bundle
}}

struct InputPayload: Codable {{
    let lines: [String]
    let labels: [String]?
    let sourceURL: String?
    let sourceTitle: String?
}}

struct SectionPayload: Codable {{
    let name: String?
    let items: [String]
}}

struct OutputPayload: Codable {{
    let labels: [String]
    let confidences: [Double]
    let sourceURL: String?
    let sourceTitle: String?
    let title: String
    let yields: String
    let totalMinutes: Int?
    let ingredients: [String]
    let ingredientSectionNames: [String?]
    let ingredientSections: [SectionPayload]
    let steps: [String]
    let stepSectionNames: [String?]
    let stepSections: [SectionPayload]
    let notes: [String]
    let notesText: String?
}}

struct Recipe: Sendable {{}}

@main
struct Main {{
    static func main() throws {{
        let modelPath = "{model_path}"
        let bundle = try makeTempBundle(withModelAt: modelPath)

        let classifier = RecipeLineClassificationService(bundle: bundle)
        let assembler = ModelRecipeAssembler()

        let inputData = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try JSONDecoder().decode(InputPayload.self, from: inputData)

        let classifications: [RecipeLineClassification] = {{
            if let labels = payload.labels, labels.count == payload.lines.count {{
                return payload.lines.enumerated().map {{ idx, line in
                    let label = RecipeLineLabel(rawValue: labels[idx]) ?? .junk
                    return RecipeLineClassification(line: line, label: label, confidence: 1.0)
                }}
            }}
            return classifier.classify(lines: payload.lines)
        }}()
        let rows = payload.lines.enumerated().map {{ idx, line in
            ModelRecipeAssembler.Row(
                index: idx,
                text: line,
                label: idx < classifications.count ? classifications[idx].label : .junk
            )
        }}
        let sourceURL = payload.sourceURL.flatMap {{ URL(string: $0) }}
        let assembly = assembler.assemble(rows: rows, sourceURL: sourceURL, sourceTitle: payload.sourceTitle)

        let out = OutputPayload(
            labels: classifications.map {{ $0.label.rawValue }},
            confidences: classifications.map {{ $0.confidence }},
            sourceURL: assembly.sourceURL?.absoluteString,
            sourceTitle: assembly.sourceTitle,
            title: assembly.title,
            yields: assembly.yields,
            totalMinutes: assembly.totalMinutes,
            ingredients: assembly.ingredients.map {{ $0.name }},
            ingredientSectionNames: assembly.ingredients.map {{ $0.section }},
            ingredientSections: assembly.ingredientSections.map {{ SectionPayload(name: $0.name, items: $0.items) }},
            steps: assembly.steps.map {{ $0.text }},
            stepSectionNames: assembly.steps.map {{ $0.section }},
            stepSections: assembly.stepSections.map {{ SectionPayload(name: $0.name, items: $0.items) }},
            notes: assembly.noteLines,
            notesText: assembly.notes
        )

        let outData = try JSONEncoder().encode(out)
        FileHandle.standardOutput.write(outData)
    }}
}}
"""


def _binary_fingerprint(repo_root: Path) -> str:
    sha = hashlib.sha256()
    sha.update(_harness_source(repo_root).encode("utf-8"))
    for source in _swift_sources(repo_root):
        sha.update(str(source).encode("utf-8"))
        stat = source.stat()
        sha.update(str(stat.st_mtime_ns).encode("utf-8"))
        sha.update(str(stat.st_size).encode("utf-8"))
    return sha.hexdigest()[:16]


def _build_binary(repo_root: Path) -> Path:
    fingerprint = _binary_fingerprint(repo_root)
    out_bin = Path(tempfile.gettempdir()) / f"cauldron_swift_schema_pipeline_{fingerprint}"
    if out_bin.exists():
        return out_bin

    harness_path = Path(tempfile.gettempdir()) / f"cauldron_swift_schema_pipeline_{fingerprint}.swift"
    harness_path.write_text(_harness_source(repo_root), encoding="utf-8")

    cmd = [
        "xcrun",
        "swiftc",
        str(harness_path),
        *[str(source) for source in _swift_sources(repo_root)],
        "-o",
        str(out_bin),
    ]
    subprocess.run(cmd, check=True)
    return out_bin


def run_swift_pipeline(
    lines: list[str],
    repo_root: Path | None = None,
    labels: list[str] | None = None,
    source_url: str | None = None,
    source_title: str | None = None,
) -> dict[str, Any]:
    """Run Swift classifier+assembler for the provided normalized lines."""
    root = repo_root or _repo_root()
    binary = _build_binary(root)
    payload = json.dumps(
        {
            "lines": lines,
            "labels": labels,
            "sourceURL": source_url,
            "sourceTitle": source_title,
        }
    ).encode("utf-8")
    proc = subprocess.run([str(binary)], input=payload, capture_output=True, check=True)
    return json.loads(proc.stdout)
