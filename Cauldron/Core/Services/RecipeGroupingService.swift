//
//  RecipeGroupingService.swift
//  Cauldron
//
//  Created for Cauldron
//

import Foundation

/// Represents a group of related recipes (original + copies)
struct SearchRecipeGroup: Identifiable {
    let id = UUID()
    let primaryRecipe: Recipe
    let saveCount: Int
    let friendSavers: [User]
    let ownerTier: UserTier
    let relevanceScore: Double

    /// Effective score for ranking (save count multiplied by tier boost)
    var effectiveScore: Double {
        Double(saveCount) * ownerTier.searchBoost
    }
}

/// Service to handle recipe deduplication, grouping, and ranking
enum RecipeGroupingService {

    /// Group, deduplicate, and rank recipes from multiple sources
    /// - Parameters:
    ///   - localRecipes: User's own recipes
    ///   - publicRecipes: Public recipes from CloudKit
    ///   - friends: List of user's friends
    ///   - currentUserId: Current user's ID
    ///   - ownerTiers: Dictionary mapping owner IDs to their tiers (for search boost)
    ///   - filterText: Text filter for recipe search
    ///   - selectedCategories: Category filter
    /// - Returns: Grouped and ranked recipe results
    static func groupAndRankRecipes(
        localRecipes: [Recipe],
        publicRecipes: [Recipe],
        friends: [User],
        currentUserId: UUID,
        ownerTiers: [UUID: UserTier] = [:],
        filterText: String = "",
        selectedCategories: Set<RecipeCategory> = []
    ) -> [SearchRecipeGroup] {
        let normalizedQuery = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTokens = tokenize(normalizedQuery)

        func matchesSelectedCategories(_ recipe: Recipe) -> Bool {
            guard !selectedCategories.isEmpty else { return true }
            return selectedCategories.allSatisfy { category in
                recipe.tags.contains { $0.name.caseInsensitiveCompare(category.tagValue) == .orderedSame }
            }
        }

        func recipeTextScore(_ recipe: Recipe) -> Double {
            guard !normalizedQuery.isEmpty else { return 1 }

            let title = recipe.title.lowercased()
            let tags = recipe.tags.map { $0.name.lowercased() }
            let ingredients = recipe.ingredients.map { $0.name.lowercased() }
            let combined = ([title] + tags + ingredients).joined(separator: " ")

            var score: Double = 0
            let queryLower = normalizedQuery.lowercased()

            if title == queryLower {
                score += 320
            } else if title.hasPrefix(queryLower) {
                score += 250
            } else if title.localizedStandardContains(queryLower) {
                score += 180
            }

            if combined.localizedStandardContains(queryLower) {
                score += 90
            }

            if !queryTokens.isEmpty {
                var matchedTokens = 0
                for token in queryTokens {
                    if title.localizedStandardContains(token) {
                        score += 65
                        matchedTokens += 1
                    } else if tags.contains(where: { $0.localizedStandardContains(token) }) {
                        score += 38
                        matchedTokens += 1
                    } else if ingredients.contains(where: { $0.localizedStandardContains(token) }) {
                        score += 32
                        matchedTokens += 1
                    }
                }

                if matchedTokens == queryTokens.count {
                    score += 80
                } else if matchedTokens == 0 {
                    score = 0
                }
            }

            return score
        }

        func buildCandidate(_ recipe: Recipe) -> (recipe: Recipe, textScore: Double)? {
            guard matchesSelectedCategories(recipe) else { return nil }
            let textScore = recipeTextScore(recipe)
            guard normalizedQuery.isEmpty || textScore > 0 else {
                return nil
            }
            return (recipe: recipe, textScore: textScore)
        }

        // Filter + score local and public results first.
        let allCandidates = (localRecipes + publicRecipes).compactMap(buildCandidate)

        // Group related copies under original ID.
        let grouped = Dictionary(grouping: allCandidates) { candidate -> UUID in
            let recipe = candidate.recipe
            return recipe.originalRecipeId ?? recipe.id
        }

        // Build grouped result cards.
        var groups: [SearchRecipeGroup] = []

        for (_, candidates) in grouped {
            let recipes = candidates.map(\.recipe)
            let recipeScores = Dictionary(uniqueKeysWithValues: candidates.map { ($0.recipe.id, $0.textScore) })

            // Choose best representative recipe.
            let primary: Recipe
            if let owned = recipes
                .filter({ $0.ownerId == currentUserId })
                .max(by: { (recipeScores[$0.id] ?? 0) < (recipeScores[$1.id] ?? 0) }) {
                primary = owned
            } else if let original = recipes
                .filter({ $0.originalRecipeId == nil })
                .max(by: { (recipeScores[$0.id] ?? 0) < (recipeScores[$1.id] ?? 0) }) {
                primary = original
            } else {
                primary = recipes.max(by: { (recipeScores[$0.id] ?? 0) < (recipeScores[$1.id] ?? 0) }) ?? recipes[0]
            }

            let friendIds = Set(friends.map { $0.id })
            let friendSavers = recipes
                .filter { $0.ownerId != nil && friendIds.contains($0.ownerId!) }
                .compactMap { recipe -> User? in
                    return friends.first(where: { $0.id == recipe.ownerId })
                }
            let uniqueFriendSavers = Array(Set(friendSavers))

            let saveCount = recipes.count

            let ownerTier: UserTier
            if let ownerId = primary.ownerId, let tier = ownerTiers[ownerId] {
                ownerTier = tier
            } else {
                ownerTier = .apprentice
            }

            let bestTextScore = candidates.map(\.textScore).max() ?? 0
            let popularityBoost = Double(max(saveCount - 1, 0)) * 30
            let friendBoost = Double(uniqueFriendSavers.count) * 110
            let tierBoost = ownerTier.searchBoost * 35
            let recencyBoost = max(0, 14 - min(14, Date().timeIntervalSince(primary.updatedAt) / 86_400))
            let relevanceScore = bestTextScore + popularityBoost + friendBoost + tierBoost + recencyBoost

            groups.append(SearchRecipeGroup(
                primaryRecipe: primary,
                saveCount: saveCount,
                friendSavers: uniqueFriendSavers,
                ownerTier: ownerTier,
                relevanceScore: relevanceScore
            ))
        }

        groups.sort { g1, g2 in
            if g1.relevanceScore != g2.relevanceScore {
                return g1.relevanceScore > g2.relevanceScore
            }
            return g1.primaryRecipe.updatedAt > g2.primaryRecipe.updatedAt
        }

        return groups
    }

    private static func tokenize(_ query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 2 }
    }
}
