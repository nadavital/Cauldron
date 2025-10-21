//
//  RecipeReference.swift
//  Cauldron
//
//  Created by Claude on 10/17/25.
//

import Foundation

/// A saved reference to someone else's shared recipe
/// This allows users to "bookmark" recipes they can view but don't own
/// References stay synced with the original - edits propagate automatically
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
