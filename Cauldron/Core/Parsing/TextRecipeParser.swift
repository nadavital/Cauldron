//
//  TextRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Parser for extracting recipes from plain text
actor TextRecipeParser: RecipeParser {
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

    private enum Section {
        case unknown
        case ingredients
        case steps
        case notes
    }

    private let instructionKeywords = [
        "add", "bake", "beat", "blend", "boil", "combine", "cook", "cool",
        "drain", "fold", "fry", "grill", "heat", "knead", "let", "marinate",
        "mix", "place", "pour", "preheat", "reduce", "rest", "roast", "saute",
        "season", "serve", "simmer", "stir", "transfer", "whisk"
    ]

    private let ingredientHints = [
        "to taste", "for garnish", "optional", "divided", "room temperature", "melted"
    ]

    private let notePrefixes = [
        "note:", "notes:", "tip:", "tips:", "pro tip:", "variation:", "variations:",
        "substitution:", "substitutions:", "storage:", "make ahead", "make-ahead",
        "serving suggestion", "chef's note", "recipe note"
    ]

    private let lineClassifier: RecipeLineClassifying
    private let schemaAssembler: RecipeSchemaAssembler
    private let modelConfidenceThreshold: Double

    init(
        lineClassifier: RecipeLineClassifying = RecipeLineClassificationService(),
        schemaAssembler: RecipeSchemaAssembler = RecipeSchemaAssembler(),
        modelConfidenceThreshold: Double = 0.72
    ) {
        self.lineClassifier = lineClassifier
        self.schemaAssembler = schemaAssembler
        self.modelConfidenceThreshold = modelConfidenceThreshold
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

        var title = selectTitle(from: lines)
        let bodyLines = Array(lines.dropFirst())
        var metadata = ParsedMetadata()
        let contentLines = stripMetadataLines(from: bodyLines, metadata: &metadata)
        let classifications = lineClassifier.classify(lines: contentLines)

        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var noteCandidates: [String] = []

        var currentSection: Section = .unknown
        var foundExplicitSection = false
        var currentIngredientSection: String?
        var currentStepSection: String?

        for (lineIndex, line) in contentLines.enumerated() {
            if TextSectionParser.isIngredientSectionHeader(line) {
                currentSection = .ingredients
                currentIngredientSection = nil
                foundExplicitSection = true
                continue
            }

            if TextSectionParser.isStepsSectionHeader(line) {
                currentSection = .steps
                currentStepSection = nil
                foundExplicitSection = true
                continue
            }

            if NotesExtractor.looksLikeNotesSectionHeader(line) {
                currentSection = .notes
                foundExplicitSection = true
                noteCandidates.append(line)
                continue
            }

            if let subsection = subsectionName(from: line), subsection.count <= 32 {
                switch currentSection {
                case .ingredients, .unknown:
                    currentSection = .ingredients
                    currentIngredientSection = subsection
                    foundExplicitSection = true
                    continue
                case .steps:
                    currentStepSection = subsection
                    continue
                case .notes:
                    noteCandidates.append(line)
                    continue
                }
            }

            let cleanedLine = cleanListMarkers(line)
            guard !cleanedLine.isEmpty else {
                continue
            }

            if isLikelyInlineNoteLine(cleanedLine) {
                noteCandidates.append(cleanedLine)
                continue
            }

            if let classification = classification(at: lineIndex, from: classifications),
               classification.confidence >= modelConfidenceThreshold {
                switch classification.label {
                case .ingredient:
                    if currentSection == .ingredients, looksLikeInstructionSentence(cleanedLine) {
                        let timers = TimerExtractor.extractTimers(from: cleanedLine)
                        steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                        currentSection = .steps
                    } else if currentSection == .steps, !TextSectionParser.looksLikeIngredient(cleanedLine) {
                        let timers = TimerExtractor.extractTimers(from: cleanedLine)
                        steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                        currentSection = .steps
                    } else {
                        ingredients.append(parseIngredient(cleanedLine, section: currentIngredientSection))
                        currentSection = .ingredients
                    }
                    continue
                case .step:
                    let timers = TimerExtractor.extractTimers(from: cleanedLine)
                    steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                    currentSection = .steps
                    continue
                case .note:
                    noteCandidates.append(cleanedLine)
                    currentSection = .notes
                    continue
                case .junk:
                    continue
                case .header:
                    if NotesExtractor.looksLikeNotesSectionHeader(cleanedLine) {
                        currentSection = .notes
                        foundExplicitSection = true
                    } else if currentSection == .ingredients, looksLikeInstructionSentence(cleanedLine) {
                        let timers = TimerExtractor.extractTimers(from: cleanedLine)
                        steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                        currentSection = .steps
                    }
                    continue
                case .title:
                    continue
                }
            }

            switch currentSection {
            case .ingredients:
                // OCR can interleave columns; route obvious action lines to steps.
                if looksLikeInstructionSentence(line) {
                    let timers = TimerExtractor.extractTimers(from: cleanedLine)
                    steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                    currentSection = .steps
                } else {
                    ingredients.append(parseIngredient(cleanedLine, section: currentIngredientSection))
                }

            case .steps:
                // OCR can interleave columns; route obvious ingredient lines back.
                if TextSectionParser.looksLikeIngredient(cleanedLine) {
                    ingredients.append(parseIngredient(cleanedLine, section: currentIngredientSection))
                } else {
                    let timers = TimerExtractor.extractTimers(from: cleanedLine)
                    steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers, section: currentStepSection))
                }

            case .notes:
                noteCandidates.append(cleanedLine)

            case .unknown:
                // Delay to heuristic pass.
                continue
            }
        }

        let schemaAssembly = parseHeuristic(lines: contentLines)
        if !foundExplicitSection || ingredients.isEmpty || steps.isEmpty {
            if ingredients.isEmpty {
                ingredients = schemaAssembly.ingredients
            }

            if steps.isEmpty {
                steps = schemaAssembly.steps
            }

            noteCandidates.append(contentsOf: schemaAssembly.notes)
        } else if shouldPreferSchemaAssembly(
            currentIngredients: ingredients,
            currentSteps: steps,
            currentNotes: noteCandidates,
            schema: schemaAssembly
        ) {
            ingredients = schemaAssembly.ingredients
            steps = schemaAssembly.steps
            noteCandidates = schemaAssembly.notes
        } else {
            noteCandidates.append(contentsOf: schemaAssembly.notes)
        }

        if title.isEmpty || title.lowercased().contains("time") {
            if let promotedTitle = noteCandidates.first(where: looksLikeTitleCandidate) {
                title = promotedTitle
                noteCandidates.removeAll { $0.caseInsensitiveCompare(promotedTitle) == .orderedSame }
            }
        }

        guard !ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }

        guard !steps.isEmpty else {
            throw ParsingError.noStepsFound
        }

        let notes = extractNotes(from: noteCandidates)

        return Recipe(
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: metadata.yields ?? "4 servings",
            totalMinutes: metadata.bestTotalMinutes,
            notes: notes
        )
    }

    private func cleanTitle(_ line: String) -> String {
        let cleaned = cleanListMarkers(line)
        return cleaned.isEmpty ? line : cleaned
    }

    private func selectTitle(from lines: [String]) -> String {
        for rawLine in lines.prefix(12) {
            let cleaned = cleanTitle(rawLine)
            if looksLikeTitleCandidate(cleaned) {
                return cleaned
            }
        }
        return cleanTitle(lines[0])
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

    private func parseIngredient(_ line: String, section: String? = nil) -> Ingredient {
        let parsed = IngredientParser.parseIngredientText(line)
        return Ingredient(
            name: parsed.name,
            quantity: parsed.quantity,
            additionalQuantities: parsed.additionalQuantities,
            note: parsed.note,
            section: section ?? parsed.section
        )
    }

    private func parseHeuristic(lines: [String]) -> (ingredients: [Ingredient], steps: [CookStep], notes: [String]) {
        let classifications = lineClassifier.classify(lines: lines)
        let assembly = schemaAssembler.assemble(
            lines: lines,
            classifications: classifications,
            confidenceThreshold: modelConfidenceThreshold,
            fallbackLabel: fallbackHeuristicLabel(for:)
        )

        let ingredients = assembly.ingredients.map { entry in
            parseIngredient(entry.text, section: entry.section)
        }

        let steps = assembly.steps.enumerated().map { index, entry in
            let timers = TimerExtractor.extractTimers(from: entry.text)
            return CookStep(index: index, text: entry.text, timers: timers, section: entry.section)
        }

        return (ingredients, steps, assembly.notes)
    }

    private func shouldPreferSchemaAssembly(
        currentIngredients: [Ingredient],
        currentSteps: [CookStep],
        currentNotes: [String],
        schema: (ingredients: [Ingredient], steps: [CookStep], notes: [String])
    ) -> Bool {
        guard !schema.ingredients.isEmpty, !schema.steps.isEmpty else {
            return false
        }
        if currentIngredients.isEmpty || currentSteps.isEmpty {
            return true
        }
        if currentSteps.count <= 2, schema.steps.count >= 3 {
            return true
        }
        if currentNotes.count >= max(6, currentSteps.count * 2), schema.steps.count > currentSteps.count {
            return true
        }
        return false
    }

    private func subsectionName(from line: String) -> String? {
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

    private func classification(at index: Int, from classifications: [RecipeLineClassification]) -> RecipeLineClassification? {
        guard classifications.indices.contains(index) else {
            return nil
        }
        return classifications[index]
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
