import AppIntents
import Foundation
#if canImport(VisualIntelligence)
import VisualIntelligence

@available(iOS 26.0, macCatalyst 27.0, *)
struct RecipeVisualSearchQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [RecipeIntentEntity] {
        let entities = try await RecipeIntentProvider.shared.libraryRecipes()
            .map { recipe in
                RecipeIntentEntity(
                    id: recipe.id,
                    title: recipe.title,
                    ingredientNames: recipe.ingredients.map(\.name),
                    totalMinutes: recipe.totalMinutes,
                    tagNames: recipe.tags.map(\.name),
                    isFavorite: recipe.isFavorite,
                    recipeYield: recipe.yields,
                    updatedAt: recipe.updatedAt,
                    createdAt: recipe.createdAt
                )
            }
        return RecipeVisualLabelMatcher.matches(labels: input.labels, recipes: entities, limit: 8)
    }
}

@available(iOS 26.0, macCatalyst 27.0, *)
@AppIntent(schema: .visualIntelligence.semanticContentSearch)
struct ShowVisualRecipeSearchResultsIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Cauldron Recipes"
    static var openAppWhenRun = true

    var semanticContent: SemanticContentDescriptor

    func perform() async throws -> some IntentResult {
        let entities = try await RecipeIntentProvider.shared.libraryRecipes()
            .map { recipe in
                RecipeIntentEntity(
                    id: recipe.id,
                    title: recipe.title,
                    ingredientNames: recipe.ingredients.map(\.name),
                    totalMinutes: recipe.totalMinutes,
                    tagNames: recipe.tags.map(\.name)
                )
            }
        let matches = RecipeVisualLabelMatcher.matches(
            labels: semanticContent.labels,
            recipes: entities,
            limit: 30
        )
        RecipeIntentNavigationStore.saveVisualSearch(recipeIDs: matches.map(\.id))
        await MainActor.run {
            NotificationCenter.default.post(name: .openVisualRecipeSearch, object: nil)
        }
        return .result()
    }
}
#endif

enum RecipeVisualLabelMatcher {
    nonisolated static func matches(
        labels: [String],
        recipes: [RecipeIntentEntity],
        limit: Int
    ) -> [RecipeIntentEntity] {
        let queryTokens = Set(labels.flatMap(expandedTokens(from:)))
        guard !queryTokens.isEmpty else { return [] }

        return recipes
            .compactMap { recipe -> (recipe: RecipeIntentEntity, score: Int)? in
                let score = relevanceScore(recipe: recipe, queryTokens: queryTokens)
                return score >= 4 ? (recipe, score) : nil
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let titleOrder = lhs.recipe.title.localizedStandardCompare(rhs.recipe.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.recipe.id.uuidString < rhs.recipe.id.uuidString
            }
            .prefix(max(limit, 0))
            .map(\.recipe)
    }

    nonisolated private static func relevanceScore(
        recipe: RecipeIntentEntity,
        queryTokens: Set<String>
    ) -> Int {
        let title = Set(expandedTokens(from: recipe.title))
        let ingredients = Set(recipe.ingredientNames.flatMap(expandedTokens(from:)))
        let tags = Set(recipe.tagNames.flatMap(expandedTokens(from:)))
        return queryTokens.reduce(into: 0) { score, token in
            if title.contains(token) { score += 6 }
            if ingredients.contains(token) { score += 5 }
            if tags.contains(token) { score += 4 }
        }
    }

    nonisolated private static func expandedTokens(from value: String) -> [String] {
        normalizedTokens(from: value).flatMap { token in
            [token] + (synonyms[token] ?? [])
        }
    }

    nonisolated private static func normalizedTokens(from value: String) -> [String] {
        let words = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }
        let canonicalWords = words.map(canonicalToken)
        let phrases = zip(canonicalWords, canonicalWords.dropFirst()).map { $0.0 + $0.1 }
        return Array(Set(words + canonicalWords + phrases))
    }

    nonisolated private static func canonicalToken(_ token: String) -> String {
        if token.count > 4, token.hasSuffix("ies") {
            return String(token.dropLast(3)) + "y"
        }
        if token.count > 4, token.hasSuffix("oes") {
            return String(token.dropLast(2))
        }
        if token.count > 4,
           ["ses", "xes", "zes", "ches", "shes"].contains(where: token.hasSuffix) {
            return String(token.dropLast(2))
        }
        if token.count > 3, token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }
        return token
    }

    nonisolated private static let stopWords: Set<String> = [
        "and", "the", "with", "for", "food", "dish", "meal", "recipe", "plate"
    ]

    nonisolated private static let synonyms: [String: [String]] = [
        "aubergine": ["eggplant"],
        "eggplant": ["aubergine"],
        "garbanzo": ["chickpea"],
        "chickpea": ["garbanzo"],
        "cilantro": ["coriander"],
        "coriander": ["cilantro"],
        "courgette": ["zucchini"],
        "zucchini": ["courgette"],
        "scallion": ["greenonion"],
        "greenonion": ["scallion"],
        "prawn": ["shrimp"],
        "shrimp": ["prawn"],
        "pasta": ["noodle"],
        "noodle": ["pasta"]
    ]
}
