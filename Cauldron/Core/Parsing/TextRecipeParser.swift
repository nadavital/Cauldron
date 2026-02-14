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

/// Parser for extracting recipes from freeform text using the on-device line model + assembler.
actor TextRecipeParser: RecipeParser, ModelRecipeTextParsing {
    private let lineClassifier: RecipeLineClassifying
    private let modelAssembler: ModelRecipeAssembler
    private let modelConfidenceThreshold: Double

    init(
        lineClassifier: RecipeLineClassifying = RecipeLineClassificationService(),
        schemaAssembler: RecipeSchemaAssembler = RecipeSchemaAssembler(),
        modelConfidenceThreshold: Double = 0.72,
        modelAssembler: ModelRecipeAssembler = ModelRecipeAssembler()
    ) {
        self.lineClassifier = lineClassifier
        self.modelConfidenceThreshold = modelConfidenceThreshold
        self.modelAssembler = modelAssembler
        _ = schemaAssembler // Kept for API compatibility with existing tests/call sites.
    }

    func parse(from text: String) async throws -> Recipe {
        let normalizedText = InputNormalizer.normalize(text)
        let lines = normalizedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return try await parse(
            lines: lines,
            sourceURL: nil,
            sourceTitle: nil,
            imageURL: nil,
            tags: [],
            preferredTitle: lines.first
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
            return ModelRecipeAssembler.Row(index: index, text: line, label: fallbackLabel(for: line))
        }

        var assembled = modelAssembler.assemble(
            rows: rows,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle
        )

        if let preferredTitle {
            let trimmed = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if assembled.title == "Untitled Recipe", !trimmed.isEmpty {
                assembled = ModelRecipeAssembler.AssembledRecipe(
                    title: trimmed,
                    sourceURL: assembled.sourceURL,
                    sourceTitle: assembled.sourceTitle,
                    yields: assembled.yields,
                    totalMinutes: assembled.totalMinutes,
                    ingredients: assembled.ingredients,
                    steps: assembled.steps,
                    noteLines: assembled.noteLines,
                    notes: assembled.notes,
                    ingredientSections: assembled.ingredientSections,
                    stepSections: assembled.stepSections
                )
            }
        }

        guard !assembled.ingredients.isEmpty else {
            throw ParsingError.noIngredientsFound
        }
        guard !assembled.steps.isEmpty else {
            throw ParsingError.noStepsFound
        }

        let yields = yieldsOverride ?? assembled.yields
        let totalMinutes = totalMinutesOverride ?? assembled.totalMinutes

        return Recipe(
            title: assembled.title,
            ingredients: assembled.ingredients,
            steps: assembled.steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            sourceURL: assembled.sourceURL,
            sourceTitle: assembled.sourceTitle,
            notes: assembled.notes,
            imageURL: imageURL
        )
    }

    private func fallbackLabel(for line: String) -> RecipeLineLabel {
        let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty {
            return .junk
        }
        if NotesExtractor.looksLikeNotesSectionHeader(cleaned) {
            return .header
        }
        if TextSectionParser.isIngredientSectionHeader(cleaned) || TextSectionParser.isStepsSectionHeader(cleaned) {
            return .header
        }
        if cleaned.hasSuffix(":") {
            return .header
        }
        let lowercased = cleaned.lowercased()
        if lowercased.hasPrefix("tip") || lowercased.hasPrefix("note") || lowercased.hasPrefix("variation") {
            return .note
        }
        if TextSectionParser.looksLikeIngredient(cleaned) {
            return .ingredient
        }
        if TextSectionParser.looksLikeNumberedStep(cleaned) {
            return .step
        }
        return cleaned.count > 18 ? .step : .ingredient
    }
}
