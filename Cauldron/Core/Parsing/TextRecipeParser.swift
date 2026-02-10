//
//  TextRecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Parser for extracting recipes from plain text
actor TextRecipeParser: RecipeParser {

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

    func parse(from text: String) async throws -> Recipe {
        let normalizedText = InputNormalizer.normalize(text)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw ParsingError.invalidSource
        }

        let title = cleanTitle(lines[0])

        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var noteCandidates: [String] = []

        var currentSection: Section = .unknown
        var foundExplicitSection = false
        var currentIngredientSection: String?
        var currentStepSection: String?

        for line in lines.dropFirst() {
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

            switch currentSection {
            case .ingredients:
                // OCR can interleave columns; route obvious action lines to steps.
                if looksLikeInstructionSentence(cleanedLine) {
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

        if !foundExplicitSection || (ingredients.isEmpty && steps.isEmpty) {
            let heuristic = parseHeuristic(lines: Array(lines.dropFirst()))

            if ingredients.isEmpty {
                ingredients = heuristic.ingredients
            }

            if steps.isEmpty {
                steps = heuristic.steps
            }

            noteCandidates.append(contentsOf: heuristic.notes)
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
            notes: notes
        )
    }

    private func cleanTitle(_ line: String) -> String {
        let cleaned = cleanListMarkers(line)
        return cleaned.isEmpty ? line : cleaned
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
            note: parsed.note,
            section: section ?? parsed.section
        )
    }

    private func parseHeuristic(lines: [String]) -> (ingredients: [Ingredient], steps: [CookStep], notes: [String]) {
        var ingredients: [Ingredient] = []
        var steps: [CookStep] = []
        var notes: [String] = []

        var inNotesSection = false

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if NotesExtractor.looksLikeNotesSectionHeader(line) {
                inNotesSection = true
                notes.append(line)
                continue
            }

            if inNotesSection {
                if TextSectionParser.isIngredientSectionHeader(line) || TextSectionParser.isStepsSectionHeader(line) {
                    inNotesSection = false
                } else {
                    notes.append(line)
                    continue
                }
            }

            let cleanedLine = cleanListMarkers(line)
            guard !cleanedLine.isEmpty else { continue }

            if isLikelyInlineNoteLine(cleanedLine) {
                notes.append(cleanedLine)
                continue
            }

            if TextSectionParser.looksLikeNumberedStep(line) || looksLikeInstructionSentence(cleanedLine) {
                let timers = TimerExtractor.extractTimers(from: cleanedLine)
                steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers))
                continue
            }

            if TextSectionParser.looksLikeIngredient(cleanedLine) || looksLikeIngredientPhrase(cleanedLine) {
                ingredients.append(parseIngredient(cleanedLine))
                continue
            }

            if !ingredients.isEmpty && cleanedLine.count > 18 {
                let timers = TimerExtractor.extractTimers(from: cleanedLine)
                steps.append(CookStep(index: steps.count, text: cleanedLine, timers: timers))
            } else {
                ingredients.append(parseIngredient(cleanedLine))
            }
        }

        return (ingredients, steps, notes)
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
