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
    /// - Returns: Load result with visible/hidden recipe counts
    func loadRecipes(
        from collection: Collection,
        viewerId: UUID?,
        isFriend: Bool = false
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

        for recipeId in collection.recipeIds {
            do {
                // Fetch recipe from CloudKit PUBLIC database
                guard let recipe = try await dependencies.recipeCloudService.fetchPublicRecipe(id: recipeId) else {
                    skippedCount += 1
                    logger.warning("Recipe not found in public database: \(recipeId)")
                    continue
                }

                // Check if the viewer can access this recipe
                if recipe.isAccessible(to: viewerId, isFriend: isFriend) {
                    visibleRecipes.append(recipe)
                } else {
                    skippedCount += 1
                    logger.info("Skipped inaccessible recipe: \(recipe.title)")
                }
            } catch {
                // Recipe might be private (doesn't exist in PUBLIC database) or deleted
                skippedCount += 1
                logger.warning("Failed to fetch recipe \(recipeId): \(error.localizedDescription)")
            }
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
