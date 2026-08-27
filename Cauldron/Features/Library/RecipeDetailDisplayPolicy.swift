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

    /// Recreate the hero image view only when its backing image identity
    /// changes. Metadata-only refreshes should leave the visible image in
    /// place so opening a recipe never flashes back to a placeholder.
    nonisolated static func shouldRefreshHeroImage(
        from current: Recipe,
        to updated: Recipe
    ) -> Bool {
        current.imageURL != updated.imageURL ||
            current.cloudImageRecordName != updated.cloudImageRecordName ||
            current.imageModifiedAt != updated.imageModifiedAt ||
            current.cloudRecordName != updated.cloudRecordName
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
