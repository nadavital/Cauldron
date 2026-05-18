//
//  RecipeVisibilityChangeImpact.swift
//  Cauldron
//

import Foundation

struct RecipeVisibilityChangeImpact: Sendable, Hashable {
    let recipeId: UUID
    let targetVisibility: RecipeVisibility
    let publicCollectionsAffected: [Collection]

    nonisolated var publicCollectionCount: Int {
        publicCollectionsAffected.count
    }

    nonisolated var requiresConfirmation: Bool {
        targetVisibility == .privateRecipe && !publicCollectionsAffected.isEmpty
    }
}
