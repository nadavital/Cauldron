//
//  SharedRecipe.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Represents a recipe shared with the current user
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
    func createPersonalCopy() -> Recipe {
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
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
