import Foundation

/// Deterministic, dependency-free text export for copying or sharing recipe
/// content. Callers pass the currently displayed recipe so scaling and unit
/// conversion are reflected in the output.
nonisolated enum RecipePlainTextFormatter {
    enum Content {
        case ingredients
        case directions
        case fullRecipe
    }

    static func format(_ recipe: Recipe, content: Content) -> String {
        format(recipe, displayedIngredients: recipe.ingredients, content: content)
    }

    /// Formats the recipe using the exact scaled/unit-converted ingredients
    /// currently presented by the UI while preserving the recipe's steps and
    /// metadata.
    static func format(
        _ recipe: Recipe,
        displayedIngredients: [Ingredient],
        content: Content
    ) -> String {
        switch content {
        case .ingredients:
            return ingredientsSection(displayedIngredients)
        case .directions:
            return directionsSection(recipe.steps)
        case .fullRecipe:
            return fullRecipe(recipe, displayedIngredients: displayedIngredients)
        }
    }

    private static func fullRecipe(
        _ recipe: Recipe,
        displayedIngredients: [Ingredient]
    ) -> String {
        var sections = [recipe.title.trimmingCharacters(in: .whitespacesAndNewlines)]

        let metadata = [
            recipe.yields.trimmingCharacters(in: .whitespacesAndNewlines),
            recipe.displayTime.map { "Total time: \($0)" }
        ].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        if !metadata.isEmpty {
            sections.append(metadata.joined(separator: "\n"))
        }

        sections.append("Ingredients\n\(ingredientsSection(displayedIngredients))")
        sections.append("Directions\n\(directionsSection(recipe.steps))")

        if let notes = recipe.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            sections.append("Notes\n\(notes)")
        }

        let source = sourceLine(for: recipe)
        if !source.isEmpty {
            sections.append(source)
        }

        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func ingredientsSection(_ ingredients: [Ingredient]) -> String {
        groupedLines(
            values: ingredients,
            section: { $0.section },
            line: { "• \($0.displayString)" }
        )
    }

    private static func directionsSection(_ steps: [CookStep]) -> String {
        groupedLines(
            values: steps,
            section: { $0.section },
            line: { step in
                let timers = step.timers.map { "\($0.label): \($0.displayDuration)" }
                let timerSuffix = timers.isEmpty ? "" : " [\(timers.joined(separator: ", "))]"
                return "\(step.index + 1). \(step.text)\(timerSuffix)"
            }
        )
    }

    private static func groupedLines<Value>(
        values: [Value],
        section: (Value) -> String?,
        line: (Value) -> String
    ) -> String {
        var lines: [String] = []
        var activeSection: String?

        for value in values {
            let nextSection = section(value)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedSection = nextSection?.isEmpty == false ? nextSection : nil
            if normalizedSection != activeSection {
                if let normalizedSection {
                    if !lines.isEmpty { lines.append("") }
                    lines.append(normalizedSection)
                }
                activeSection = normalizedSection
            }
            lines.append(line(value))
        }

        return lines.joined(separator: "\n")
    }

    private static func sourceLine(for recipe: Recipe) -> String {
        let title = recipe.sourceTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = recipe.sourceURL?.absoluteString
        switch (title?.isEmpty == false ? title : nil, url) {
        case let (title?, url?): return "Source: \(title) — \(url)"
        case let (title?, nil): return "Source: \(title)"
        case let (nil, url?): return "Source: \(url)"
        case (nil, nil): return ""
        }
    }
}
