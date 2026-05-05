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
    let hiddenRecipeCount: Int
    let totalRecipeCount: Int

    var hasHiddenRecipes: Bool {
        hiddenRecipeCount > 0
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
                hiddenRecipeCount: 0,
                totalRecipeCount: 0
            )
        }

        var visibleRecipes: [Recipe] = []
        var skippedCount = 0

        do {
            let recipesById = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(
                ids: collection.recipeIds,
                forceRefresh: forceRefresh
            )

            for recipeId in collection.recipeIds {
                guard let recipe = recipesById[recipeId] else {
                    skippedCount += 1
                    logger.warning("Recipe not found in public database: \(recipeId)")
                    continue
                }

                if recipe.isAccessible(to: viewerId, isFriend: isFriend) {
                    visibleRecipes.append(recipe)
                } else {
                    skippedCount += 1
                    logger.info("Skipped inaccessible recipe: \(recipe.title)")
                }
            }
        } catch {
            skippedCount = collection.recipeIds.count
            logger.warning("Failed to batch fetch shared collection recipes: \(error.localizedDescription)")
        }

        logger.info("✅ Loaded \(visibleRecipes.count) visible recipes, \(skippedCount) hidden/unavailable")

        return SharedCollectionLoadResult(
            visibleRecipes: visibleRecipes,
            hiddenRecipeCount: skippedCount,
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
