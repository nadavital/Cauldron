//
//  RecipeDetailDisplayPolicy.swift
//  Cauldron
//

import Foundation

enum RecipeDetailDisplayPolicy {
    nonisolated static func hasHeroImage(_ recipe: Recipe) -> Bool {
        recipe.imageURL != nil || recipe.cloudImageRecordName != nil
    }

    nonisolated static func shouldRefreshPublicRecipeOnOpen(
        _ recipe: Recipe,
        currentUserId: UUID?
    ) -> Bool {
        !isOwnedByCurrentUser(recipe, currentUserId: currentUserId)
    }

    nonisolated static func shouldSaveAsPreviewOnOpen(
        _ recipe: Recipe,
        currentUserId: UUID?
    ) -> Bool {
        shouldRefreshPublicRecipeOnOpen(recipe, currentUserId: currentUserId) && !recipe.isPreview
    }

    private nonisolated static func isOwnedByCurrentUser(
        _ recipe: Recipe,
        currentUserId: UUID?
    ) -> Bool {
        guard let ownerId = recipe.ownerId, let currentUserId else {
            return false
        }

        return ownerId == currentUserId
    }
}
