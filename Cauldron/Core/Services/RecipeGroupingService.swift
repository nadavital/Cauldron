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

        // 1. Filter Local Recipes
        var filteredLocal = localRecipes

        if !filterText.isEmpty {
            let lowercased = filterText.lowercased()
            filteredLocal = filteredLocal.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
                recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }

        if !selectedCategories.isEmpty {
            filteredLocal = filteredLocal.filter { recipe in
                selectedCategories.allSatisfy { category in
                    recipe.tags.contains(where: { $0.name.caseInsensitiveCompare(category.tagValue) == .orderedSame })
                }
            }
        }

        // 2. Merge Local + Public
        // Ensure we don't have duplicates by ID (e.g. if I own it, it might be in both lists?)
        // Typically localRecipes are "My Recipes" and publicRecipes are "Others".
        // But for safety, let's combine and then group.
        let allResults = filteredLocal + publicRecipes

        // 3. Group by Original Recipe ID (Deduplication)
        // Key: originalRecipeId ?? id (of original)
        let grouped = Dictionary(grouping: allResults) { recipe -> UUID in
            return recipe.originalRecipeId ?? recipe.id
        }

        // 4. Create SearchRecipeGroup objects
        var groups: [SearchRecipeGroup] = []

        for (_, recipes) in grouped {
            // Identify Primary Recipe to show
            // Preference: 1. Owned by self (if in local results), 2. Original (originalRecipeId == nil), 3. First one
            let primary: Recipe
            if let owned = recipes.first(where: { $0.ownerId == currentUserId }) {
                primary = owned
            } else if let original = recipes.first(where: { $0.originalRecipeId == nil }) {
                primary = original
            } else {
                primary = recipes.first!
            }

            // Find friends who saved this recipe
            // We check if any recipe in this group is owned by a friend
            let friendIds = Set(friends.map { $0.id })
            let friendSavers = recipes
                .filter { $0.ownerId != nil && friendIds.contains($0.ownerId!) }
                .compactMap { recipe -> User? in
                    return friends.first(where: { $0.id == recipe.ownerId })
                }
            // Remove duplicates (e.g. if friend saved multiple versions? Unlikely but safe)
            let uniqueFriendSavers = Array(Set(friendSavers))

            // Total Save Count (proxy: number of copies found in search + maybe explicit save count from server if we had it)
            // Currently using group size as proxy for visible popularity in this search
            let saveCount = recipes.count

            // Get owner tier for the primary recipe (default to Apprentice if not found)
            let ownerTier: UserTier
            if let ownerId = primary.ownerId, let tier = ownerTiers[ownerId] {
                ownerTier = tier
            } else {
                ownerTier = .apprentice
            }

            groups.append(SearchRecipeGroup(
                primaryRecipe: primary,
                saveCount: saveCount,
                friendSavers: uniqueFriendSavers,
                ownerTier: ownerTier
            ))
        }

        // 5. Sort/Rank
        // Rank by: Friend activity (top), then effective score (save count × tier boost)
        groups.sort { g1, g2 in
             if !g1.friendSavers.isEmpty && g2.friendSavers.isEmpty { return true }
             if g1.friendSavers.isEmpty && !g2.friendSavers.isEmpty { return false }
             return g1.effectiveScore > g2.effectiveScore
        }

        return groups
    }
}
