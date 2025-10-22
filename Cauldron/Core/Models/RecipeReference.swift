//
//  RecipeReference.swift
//  Cauldron
//
//  Created by Claude on 10/17/25.
//

import Foundation

/// A saved reference to someone else's shared recipe (stored in CloudKit PUBLIC database)
///
/// This represents a user's **explicit save** of a public/shared recipe to their personal collection.
/// Unlike SharedRecipe (which is just a browsing view), RecipeReference is persistent and appears
/// in the user's main recipe list (Cook/Library tabs).
///
/// Key characteristics:
/// - Stored as a separate record in CloudKit (not a copy of the recipe)
/// - Points to the original recipe via originalRecipeId
/// - References stay synced with the original - edits propagate automatically
/// - Can be deleted independently without affecting the original recipe
/// - Allows users to "bookmark" recipes they can view but don't own
///
/// This is distinct from:
/// - SharedRecipe: Temporary browsing model for public recipes (Sharing tab only)
/// - Owned Recipe copy: Independent copy that user can edit (created via "Save a Copy")
struct RecipeReference: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID  // Who saved this reference
    let originalRecipeId: UUID  // Points to the actual recipe
    let originalOwnerId: UUID  // Recipe owner
    let savedAt: Date
    let isCopy: Bool  // false for references, true for independent copies

    // Cached metadata for fast list display (avoid fetching full recipe)
    let recipeTitle: String
    let recipeTags: [String]

    init(
        id: UUID = UUID(),
        userId: UUID,
        originalRecipeId: UUID,
        originalOwnerId: UUID,
        savedAt: Date = Date(),
        isCopy: Bool = false,
        recipeTitle: String,
        recipeTags: [String] = []
    ) {
        self.id = id
        self.userId = userId
        self.originalRecipeId = originalRecipeId
        self.originalOwnerId = originalOwnerId
        self.savedAt = savedAt
        self.isCopy = isCopy
        self.recipeTitle = recipeTitle
        self.recipeTags = recipeTags
    }

    /// Create a reference to a shared recipe (not a copy)
    static func reference(
        userId: UUID,
        recipe: Recipe
    ) -> RecipeReference {
        RecipeReference(
            userId: userId,
            originalRecipeId: recipe.id,
            originalOwnerId: recipe.ownerId ?? userId, // Fallback to userId if ownerId is nil
            isCopy: false,
            recipeTitle: recipe.title,
            recipeTags: recipe.tags.map { $0.name }
        )
    }
}
