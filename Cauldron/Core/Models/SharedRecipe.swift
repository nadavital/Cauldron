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
/// To actually save a shared recipe, use:
/// - `recipe.withOwner(userId, originalCreatorId:originalCreatorName:)` - Creates an independent copy they can edit
///
/// Note: This model is used for browsing shared recipes in the Sharing tab.
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
}
