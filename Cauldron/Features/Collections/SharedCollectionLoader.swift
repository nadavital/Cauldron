//
//  SharedCollectionLoader.swift
//  Cauldron
//
//  Unified logic for loading and filtering shared collection recipes
//

import Foundation
import os

/// Result of loading recipes from a shared collection
struct SharedCollectionLoadResult {
    let visibleRecipes: [Recipe]
    let inaccessibleRecipeCount: Int
    let unavailableRecipeCount: Int
    let totalRecipeCount: Int

    var hasHiddenRecipes: Bool {
        hiddenRecipeCount > 0
    }

    var hiddenRecipeCount: Int {
        inaccessibleRecipeCount + unavailableRecipeCount
    }
}

/// Utility for loading collection recipes with proper visibility filtering
@MainActor
class SharedCollectionLoader {
    private let dependencies: DependencyContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "SharedCollectionLoader")

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    /// Load recipes from a collection with accessibility filtering
    /// - Parameters:
    ///   - collection: The collection to load recipes from
    ///   - viewerId: The ID of the user viewing the collection
    ///   - isFriend: Whether the viewer is friends with the collection owner
    ///   - forceRefresh: Whether to bypass cached public recipe records
    /// - Returns: Load result with visible/hidden recipe counts
    func loadRecipes(
        from collection: Collection,
        viewerId: UUID?,
        isFriend: Bool = false,
        forceRefresh: Bool = false
    ) async -> SharedCollectionLoadResult {
        guard !collection.recipeIds.isEmpty else {
            return SharedCollectionLoadResult(
                visibleRecipes: [],
                inaccessibleRecipeCount: 0,
                unavailableRecipeCount: 0,
                totalRecipeCount: 0
            )
        }

        var visibleRecipes: [Recipe] = []
        var inaccessibleCount = 0
        var unavailableCount = 0

        do {
            let recipesById: [UUID: Recipe]
            if RuntimeEnvironment.isSimulatorQAMode {
                let localRecipes = try await dependencies.recipeRepository.fetch(ids: collection.recipeIds)
                recipesById = RecipeDeduplication.byIdPreferringBest(localRecipes)
            } else {
                recipesById = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(
                    ids: collection.recipeIds,
                    forceRefresh: forceRefresh
                )
            }

            for recipeId in collection.recipeIds {
                guard let recipe = recipesById[recipeId] else {
                    unavailableCount += 1
                    logger.warning("Recipe not found in public database: \(recipeId)")
                    continue
                }

                if recipe.isAccessible(to: viewerId, isFriend: isFriend) {
                    visibleRecipes.append(recipe)
                } else {
                    inaccessibleCount += 1
                    logger.info("Skipped inaccessible recipe: \(recipe.title)")
                }
            }
        } catch {
            unavailableCount = collection.recipeIds.count
            logger.warning("Failed to batch fetch shared collection recipes: \(error.localizedDescription)")
        }

        logger.info("✅ Loaded \(visibleRecipes.count) visible recipes, \(inaccessibleCount) inaccessible, \(unavailableCount) unavailable")

        return SharedCollectionLoadResult(
            visibleRecipes: visibleRecipes,
            inaccessibleRecipeCount: inaccessibleCount,
            unavailableRecipeCount: unavailableCount,
            totalRecipeCount: collection.recipeIds.count
        )
    }

    /// Check friendship status between viewer and collection owner
    /// - Parameters:
    ///   - viewerId: The ID of the user viewing the collection
    ///   - ownerId: The ID of the collection owner
    /// - Returns: Whether the users are friends
    func checkFriendshipStatus(viewerId: UUID?, ownerId: UUID) async -> Bool {
        guard let viewerId = viewerId, viewerId != ownerId else {
            return false
        }

        await dependencies.connectionManager.loadConnections(forUserId: viewerId)
        let connectionStatus = dependencies.connectionManager.connectionStatus(with: ownerId)
        let isFriend = connectionStatus?.isAccepted ?? false

        logger.info("Friendship status with collection owner: \(isFriend)")
        return isFriend
    }
}
