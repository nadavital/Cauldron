//
//  TextRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

protocol ModelRecipeTextParsing: Sendable {
    func parse(
        lines: [String],
        sourceURL: URL?,
        sourceTitle: String?,
        imageURL: URL?,
        tags: [Tag],
        preferredTitle: String?,
        yieldsOverride: String?,
        totalMinutesOverride: Int?
    ) async throws -> Recipe
}

/// Parser for extracting recipes from freeform text.
///
/// `parse(from:)` and `parse(lines:...)` both route through the same model-first assembly path.
actor TextRecipeParser: RecipeParser, ModelRecipeTextParsing {
    private struct ParsedMetadata {
        var yields: String?
        var prepMinutes: Int?
        var cookMinutes: Int?
        var totalMinutes: Int?

        var bestTotalMinutes: Int? {
            if let totalMinutes {
                return totalMinutes
            }
            if let prepMinutes, let cookMinutes {
                return prepMinutes + cookMinutes
            }
            return cookMinutes ?? prepMinutes
        }
    }

    private let instructionKeywords: [String] = [
        "add", "bake", "beat", "blend", "boil", "combine", "cook", "cool",
        "drain", "fold", "fry", "grill", "heat", "knead", "let", "marinate",
        "mix", "place", "pour", "preheat", "reduce", "rest", "roast", "saute",
        "season", "serve", "simmer", "stir", "transfer", "whisk"
    ]

    private let ingredientHints: [String] = [
        "to taste", "for garnish", "optional", "divided", "room temperature", "melted"
    ]

    private let notePrefixes: [String] = [
        "note:", "notes:", "tip:", "tips:", "pro tip:", "variation:", "variations:",
        "substitution:", "substitutions:", "storage:", "make ahead", "make-ahead",
        "serving suggestion", "chef's note", "recipe note"
    ]

    private let lineClassifier: RecipeLineClassifying
    private let modelAssembler: ModelRecipeAssembler
    private let modelConfidenceThreshold: Double

    init(
        lineClassifier: RecipeLineClassifying = RecipeLineClassificationService(),
        modelConfidenceThreshold: Double = 0.72,
        modelAssembler: ModelRecipeAssembler = ModelRecipeAssembler()
    ) {
        self.lineClassifier = lineClassifier
        self.modelConfidenceThreshold = modelConfidenceThreshold
        self.modelAssembler = modelAssembler
    }

    func parse(from text: String) async throws -> Recipe {
        let normalizedText = InputNormalizer.normalize(text)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw ParsingError.invalidSource
        }

        let selectedTitle = selectTitle(from: lines)
        let bodyLines = lines.enumerated()
            .filter { $0.offset != selectedTitle.index }
            .map(\.element)
        var metadata = ParsedMetadata()
        let contentLines = stripMetadataLines(from: bodyLines, metadata: &metadata)
        return try await parse(
            lines: contentLines,
            sourceURL: nil,
            sourceTitle: nil,
            imageURL: nil,
            tags: [],
            preferredTitle: selectedTitle.text,
            yieldsOverride: metadata.yields,
            totalMinutesOverride: metadata.bestTotalMinutes
        )
    }

    func parse(
        lines: [String],
        sourceURL: URL?,
        sourceTitle: String?,
        imageURL: URL?,
        tags: [Tag] = [],
        preferredTitle: String? = nil,
        yieldsOverride: String? = nil,
        totalMinutesOverride: Int? = nil
    ) async throws -> Recipe {
        let normalizedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedLines.isEmpty else {
            throw ParsingError.invalidSource
        }

        let classifications = lineClassifier.classify(lines: normalizedLines)
        let rows: [ModelRecipeAssembler.Row] = normalizedLines.enumerated().map { index, line in
            if index < classifications.count, classifications[index].confidence >= modelConfidenceThreshold {
                return ModelRecipeAssembler.Row(index: index, text: line, label: classifications[index].label)
            }
            return ModelRecipeAssembler.Row(index: index, text: line, label: fallbackHeuristicLabel(for: line))
        }

        let assembled = modelAssembler.assemble(
            rows: rows,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle
        )

        var title = assembled.title
        var ingredients = assembled.ingredients
        var steps = assembled.steps
        var noteLines = assembled.noteLines
        var fallbackAssembly: ModelRecipeAssembler.AssembledRecipe?

        if ingredients.isEmpty || steps.isEmpty {
            let schema = assembleWithFallbackLabels(
                lines: normalizedLines,
                sourceURL: sourceURL,
                sourceTitle: sourceTitle
            )
            fallbackAssembly = schema
            if ingredients.isEmpty {
                ingredients = schema.ingredients
            }
            if steps.isEmpty {
                steps = schema.steps
            }
            noteLines.append(contentsOf: schema.noteLines)
            if title == "Untitled Recipe", schema.title != "Untitled Recipe" {
                title = schema.title
            }
        }

        if let preferredTitle {
            let trimmed = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if title == "Untitled Recipe", !trimmed.isEmpty {
                title = trimmed
            }
        }

        guard !ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }
        guard !steps.isEmpty else {
            throw ParsingError.noStepsFound
        }

        let noteText = extractNotes(from: noteLines)

        let yields = yieldsOverride ?? fallbackAssembly?.yields ?? assembled.yields
        let totalMinutes = totalMinutesOverride ?? assembled.totalMinutes ?? fallbackAssembly?.totalMinutes

        return Recipe(
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            sourceURL: assembled.sourceURL,
            sourceTitle: assembled.sourceTitle,
            notes: noteText,
            imageURL: imageURL
        )
    }

    private func cleanTitle(_ line: String) -> String {
        let cleaned = cleanListMarkers(line)
        return cleaned.isEmpty ? line : cleaned
    }

    private func selectTitle(from lines: [String]) -> (text: String, index: Int) {
        let titleScanWindow = 12
        let candidateRangeEnd: Int
        if let firstHeaderIndex = lines.prefix(titleScanWindow).firstIndex(where: { line in
            TextSectionParser.isIngredientSectionHeader(line) ||
            TextSectionParser.isStepsSectionHeader(line) ||
            NotesExtractor.looksLikeNotesSectionHeader(line)
        }) {
            candidateRangeEnd = firstHeaderIndex
        } else {
            candidateRangeEnd = min(lines.count, titleScanWindow)
        }

        if candidateRangeEnd > 0 {
            for index in 0..<candidateRangeEnd {
                let rawLine = lines[index]
                let cleaned = cleanTitle(rawLine)
                if looksLikeTitleCandidate(cleaned) {
                    return (cleaned, index)
                }
            }
        }

        return (cleanTitle(lines[0]), 0)
    }

    private func looksLikeTitleCandidate(_ line: String) -> Bool {
        let cleaned = cleanTitle(line)
        guard !cleaned.isEmpty else {
            return false
        }
        if extractMetadata(from: cleaned) != nil {
            return false
        }
        if TextSectionParser.isIngredientSectionHeader(cleaned) ||
            TextSectionParser.isStepsSectionHeader(cleaned) ||
            NotesExtractor.looksLikeNotesSectionHeader(cleaned) {
            return false
        }
        if TextSectionParser.looksLikeIngredient(cleaned) || looksLikeInstructionSentence(cleaned) || looksLikeHTMLArtifact(cleaned) {
            return false
        }
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return (2...16).contains(words.count)
    }

    private func cleanListMarkers(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[•●○◦▪▫\-]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^Step\s*\d*[:\.]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assembleWithFallbackLabels(
        lines: [String],
        sourceURL: URL?,
        sourceTitle: String?
    ) -> ModelRecipeAssembler.AssembledRecipe {
        let rows: [ModelRecipeAssembler.Row] = lines.enumerated().map { index, line in
            ModelRecipeAssembler.Row(
                index: index,
                text: line,
                label: fallbackHeuristicLabel(for: line)
            )
        }
        return modelAssembler.assemble(
            rows: rows,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle
        )
    }

    private func looksLikeInstructionSentence(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let words = lowercased
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let tokens = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        if TextSectionParser.looksLikeNumberedStep(line) {
            return true
        }

        if instructionKeywords.contains(where: { tokens.contains($0) }) {
            return true
        }

        if words.count >= 8 {
            return true
        }

        if words.count >= 5, line.contains(",") {
            return true
        }

        return false
    }

    private func looksLikeIngredientPhrase(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let words = lowercased
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }

        if words.isEmpty || words.count > 6 {
            return false
        }

        if ingredientHints.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if lowercased.contains(" and "), words.count <= 4 {
            return true
        }

        if instructionKeywords.contains(where: { lowercased.hasPrefix($0 + " ") }) {
            return false
        }

        return words.count <= 4
    }

    private func isLikelyInlineNoteLine(_ line: String) -> Bool {
        let lowercased = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return notePrefixes.contains { lowercased.hasPrefix($0) }
    }

    private func fallbackHeuristicLabel(for line: String) -> RecipeLineLabel {
        if looksLikeHTMLArtifact(line) {
            return .junk
        }

        if line.hasSuffix(":") {
            return .header
        }

        if isLikelyInlineNoteLine(line) {
            return .note
        }

        if TextSectionParser.looksLikeNumberedStep(line) || looksLikeInstructionSentence(line) {
            return .step
        }

        if TextSectionParser.looksLikeIngredient(line) || looksLikeIngredientPhrase(line) {
            return .ingredient
        }

        return line.count > 18 ? .step : .ingredient
    }

    private func stripMetadataLines(from lines: [String], metadata: inout ParsedMetadata) -> [String] {
        var content: [String] = []
        content.reserveCapacity(lines.count)

        for line in lines {
            if let extracted = extractMetadata(from: line) {
                if let yields = extracted.yields {
                    metadata.yields = yields
                }
                if let total = extracted.totalMinutes {
                    metadata.totalMinutes = total
                }
                if let prep = extracted.prepMinutes {
                    metadata.prepMinutes = prep
                }
                if let cook = extracted.cookMinutes {
                    metadata.cookMinutes = cook
                }
                continue
            }
            content.append(line)
        }

        return content
    }

    private func extractMetadata(from line: String) -> ParsedMetadata? {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return nil
        }

        var extracted = ParsedMetadata()
        let lowercased = cleaned.lowercased()

        if isLikelyYieldLine(lowercased), let yields = YieldParser.extractYield(from: cleaned) {
            extracted.yields = yields
        }

        let total = extractMinutes(in: cleaned, pattern: #"(?i)^\s*(?:total\s*time|total|ready\s*in)\s*:?\s*(.+)$"#)
            ?? extractMinutes(in: cleaned, pattern: #"(?i)^\s*time\s*:\s*(.+)$"#)
        if let total {
            extracted.totalMinutes = total
        }
        if let prep = extractMinutes(in: cleaned, pattern: #"(?i)^\s*(?:prep\s*time|prepping\s*time|preparation\s*time)\s*:?\s*(.+)$"#) {
            extracted.prepMinutes = prep
        }
        if let cook = extractMinutes(in: cleaned, pattern: #"(?i)^\s*(?:cook\s*time|cooking\s*time|bake\s*time|roast\s*time)\s*:?\s*(.+)$"#) {
            extracted.cookMinutes = cook
        }

        let hasTime = extracted.totalMinutes != nil || extracted.prepMinutes != nil || extracted.cookMinutes != nil
        if extracted.yields == nil && !hasTime {
            return nil
        }
        return extracted
    }

    private func extractMinutes(in line: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: line) else {
            return nil
        }

        let tail = String(line[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tail.isEmpty else {
            return nil
        }

        return TimeParser.parseTimeString(tail)
    }

    private func isLikelyYieldLine(_ lowercasedLine: String) -> Bool {
        let normalized = lowercasedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["serves", "serving", "servings", "yield", "yields", "makes", "portion", "portions"]
        return prefixes.contains(where: { prefix in
            normalized == prefix || normalized.hasPrefix(prefix + " ") || normalized.hasPrefix(prefix + ":")
        })
    }

    private func looksLikeHTMLArtifact(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        return lowercased.contains("<div") || lowercased.contains("</") || (lowercased.hasPrefix("<") && lowercased.hasSuffix(">"))
    }

    private func extractNotes(from noteCandidates: [String]) -> String? {
        let cleaned = noteCandidates
            .map { cleanListMarkers($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            return nil
        }

        if let extracted = NotesExtractor.extractNotes(from: cleaned), !extracted.isEmpty {
            return extracted
        }

        var seen = Set<String>()
        let deduped = cleaned.filter { seen.insert($0.lowercased()).inserted }
        return deduped.joined(separator: "\n")
    }
}
