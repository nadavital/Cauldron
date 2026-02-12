//
//  RecipeSchemaAssembler.swift
//  Cauldron
//
//  Created on February 10, 2026.
//

import Foundation

struct RecipeSchemaAssembler: Sendable {
    private static let instructionKeywords: Set<String> = [
        "add", "bake", "beat", "blend", "boil", "combine", "cook", "cool",
        "drain", "fold", "fry", "grill", "heat", "knead", "let", "marinate",
        "mix", "place", "pour", "preheat", "reduce", "rest", "roast", "saute",
        "season", "serve", "simmer", "stir", "transfer", "whisk"
    ]
    private static let noteKeywordHints: Set<String> = [
        "flavor", "nutrition", "optional", "tip", "tips", "variation", "variations", "wine", "twist"
    ]
    private static let stepKeywordHints: Set<String> = [
        "add", "cook", "drain", "heat", "mix", "prepare", "remove", "rest", "return",
        "serve", "simmer", "sprinkle", "stir", "toss", "set aside", "skillet", "oven", "pot"
    ]

    struct IngredientLine: Sendable {
        let text: String
        let section: String?
    }

    struct StepLine: Sendable {
        let text: String
        let section: String?
    }

    struct Assembly: Sendable {
        let ingredients: [IngredientLine]
        let steps: [StepLine]
        let notes: [String]
    }

    private enum Section {
        case unknown
        case ingredients
        case steps
        case notes
    }

    nonisolated init() {}

    nonisolated func assemble(
        lines: [String],
        classifications: [RecipeLineClassification],
        confidenceThreshold: Double,
        fallbackLabel: (String) -> RecipeLineLabel
    ) -> Assembly {
        var currentSection: Section = .unknown
        var currentIngredientSection: String?
        var currentStepSection: String?

        var ingredientLines: [IngredientLine] = []
        var stepLines: [StepLine] = []
        var noteLines: [String] = []

        for (index, rawLine) in lines.enumerated() {
            let cleanedLine = cleanListMarkers(rawLine)
            guard !cleanedLine.isEmpty else {
                continue
            }

            if TextSectionParser.isIngredientSectionHeader(rawLine) {
                currentSection = .ingredients
                currentIngredientSection = nil
                continue
            }

            if TextSectionParser.isStepsSectionHeader(rawLine) {
                currentSection = .steps
                currentStepSection = nil
                continue
            }

            if NotesExtractor.looksLikeNotesSectionHeader(rawLine) {
                currentSection = .notes
                continue
            }

            if let subsection = subsectionName(from: rawLine), subsection.count <= 32 {
                switch currentSection {
                case .steps:
                    currentStepSection = subsection
                case .notes:
                    noteLines.append(cleanedLine)
                case .ingredients, .unknown:
                    currentSection = .ingredients
                    currentIngredientSection = subsection
                }
                continue
            }

            let fallback = fallbackLabel(cleanedLine)
            let predicted = index < classifications.count ? classifications[index] : nil

            let effectiveLabel: RecipeLineLabel
            if let predicted, predicted.confidence >= confidenceThreshold {
                effectiveLabel = predicted.label
            } else {
                effectiveLabel = fallback
            }

            if currentSection == .notes, [.ingredient, .step, .note].contains(effectiveLabel) {
                if looksLikeStepFragment(cleanedLine) {
                    stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                    currentSection = .steps
                    continue
                }

                if looksLikeNoteFragment(cleanedLine) {
                    noteLines.append(cleanedLine)
                    currentSection = .notes
                    continue
                }
            }

            switch effectiveLabel {
            case .ingredient:
                if currentSection == .ingredients, looksLikeHeaderlessInstruction(cleanedLine) {
                    stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                    currentSection = .steps
                } else if currentSection == .steps, !TextSectionParser.looksLikeIngredient(cleanedLine) {
                    stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                    currentSection = .steps
                } else {
                    ingredientLines.append(IngredientLine(text: cleanedLine, section: currentIngredientSection))
                    currentSection = .ingredients
                }

            case .step:
                stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                currentSection = .steps

            case .note:
                if looksLikeStepFragment(cleanedLine) {
                    stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                    currentSection = .steps
                } else {
                    noteLines.append(cleanedLine)
                    currentSection = .notes
                }

            case .header:
                if NotesExtractor.looksLikeNotesSectionHeader(cleanedLine) {
                    currentSection = .notes
                } else if currentSection == .ingredients, looksLikeHeaderlessInstruction(cleanedLine) {
                    stepLines.append(StepLine(text: cleanedLine, section: currentStepSection))
                    currentSection = .steps
                } else if currentSection == .ingredients {
                    // Recovery: some ingredient lines are misclassified as headers.
                    ingredientLines.append(IngredientLine(text: cleanedLine, section: currentIngredientSection))
                }

            case .title, .junk:
                continue
            }
        }

        return Assembly(
            ingredients: ingredientLines,
            steps: stepLines,
            notes: noteLines
        )
    }

    nonisolated private func cleanListMarkers(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[•●○◦▪▫\-]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^Step\s*\d*[:\.]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func subsectionName(from line: String) -> String? {
        guard line.hasSuffix(":"), !NotesExtractor.looksLikeNotesSectionHeader(line) else {
            return nil
        }

        let withoutColon = String(line.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !withoutColon.isEmpty else {
            return nil
        }

        let lowercased = withoutColon.lowercased()
        guard !TextSectionParser.isIngredientSectionHeader(lowercased),
              !TextSectionParser.isStepsSectionHeader(lowercased),
              !lowercased.hasPrefix("step") else {
            return nil
        }

        if withoutColon.contains(where: { $0.isNumber }) {
            return nil
        }

        return withoutColon
    }

    nonisolated private func looksLikeHeaderlessInstruction(_ line: String) -> Bool {
        if TextSectionParser.looksLikeIngredient(line) {
            return false
        }

        if TextSectionParser.looksLikeNumberedStep(line) {
            return true
        }

        let words = line
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let tokens = line
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard let firstWord = words.first else {
            return false
        }

        if Self.instructionKeywords.contains(firstWord) {
            return true
        }

        if ["in", "on", "to", "then", "meanwhile"].contains(firstWord),
           tokens.contains(where: { Self.instructionKeywords.contains($0) }) {
            return true
        }

        return false
    }

    nonisolated private func looksLikeOCRArtifactLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("templatelab") || lowered.contains("created by") || lowered == "reated b" {
            return true
        }
        if lowered.range(of: #"^\s*(?:prep(?:ping)?|preparation|cook(?:ing)?|total)\s*tim(?:e)?\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    nonisolated private func looksLikeNoteFragment(_ line: String) -> Bool {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return false
        }
        if TextSectionParser.looksLikeIngredient(cleaned) || looksLikeHeaderlessInstruction(cleaned) {
            return false
        }
        if [",", ";", ":"].contains(String(cleaned.first ?? " ")) {
            return cleaned.split(separator: " ").count >= 2
        }
        let lowered = cleaned.lowercased()
        if lowered.hasPrefix("for ") || lowered.hasPrefix("feel ") || lowered.hasPrefix("use ") || lowered.hasPrefix("optional ") {
            return true
        }
        return Self.noteKeywordHints.contains { lowered.contains($0) }
    }

    nonisolated private func looksLikeStepFragment(_ line: String) -> Bool {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return false
        }
        if looksLikeOCRArtifactLine(cleaned) {
            return false
        }
        if TextSectionParser.looksLikeIngredient(cleaned) || looksLikeNoteFragment(cleaned) {
            return false
        }
        if looksLikeHeaderlessInstruction(cleaned) || TextSectionParser.looksLikeNumberedStep(cleaned) {
            return true
        }
        let lowered = cleaned.lowercased()
        if Self.stepKeywordHints.contains(where: { lowered.contains($0) }) {
            return true
        }
        if cleaned.hasSuffix(".") && cleaned.split(separator: " ").count >= 4 {
            return true
        }
        return false
    }
}
