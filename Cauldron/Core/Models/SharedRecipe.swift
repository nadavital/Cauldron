//
//  SharedRecipe.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Represents a recipe shared with the current user (displayed in Sharing tab)
///
/// This is a **browsing** model - recipes that are available to view from the PUBLIC database
/// but are not necessarily saved to the user's personal collection yet.
///
/// To actually save a shared recipe, users can:
/// 1. Create a RecipeReference (via "Add to My Recipes") - Creates a bookmark that stays synced with the original
/// 2. Create an owned copy (via "Save a Copy") - Creates an independent recipe they can edit
///
/// Note: This model is separate from RecipeReference which represents recipes the user has explicitly saved.
struct SharedRecipe: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let recipe: Recipe
    let sharedBy: User
    let sharedAt: Date
    
    init(
        id: UUID = UUID(),
        recipe: Recipe,
        sharedBy: User,
        sharedAt: Date = Date()
    ) {
        self.id = id
        self.recipe = recipe
        self.sharedBy = sharedBy
        self.sharedAt = sharedAt
    }
    
    /// Create a copy of this shared recipe for the current user's own collection
    func createPersonalCopy(ownerId: UUID) -> Recipe {
        Recipe(
            id: UUID(), // New ID for the copy
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: recipe.yields,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags,
            nutrition: recipe.nutrition,
            sourceURL: recipe.sourceURL,
            sourceTitle: recipe.sourceTitle,
            notes: recipe.notes,
            imageURL: recipe.imageURL,
            isFavorite: false,
            visibility: .privateRecipe, // Make it private by default
            ownerId: ownerId, // Set the current user as owner
            cloudRecordName: nil, // Clear to ensure new CloudKit record
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
