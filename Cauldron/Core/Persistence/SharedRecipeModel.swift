//
//  SharedRecipeModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftData

/// SwiftData model for persisting shared recipes
@Model
final class SharedRecipeModel {
    var id: UUID = UUID()
    var recipeData: Data = Data() // Encoded Recipe
    var sharedByData: Data = Data() // Encoded User
    var sharedAt: Date = Date()
    
    init(id: UUID, recipeData: Data, sharedByData: Data, sharedAt: Date) {
        self.id = id
        self.recipeData = recipeData
        self.sharedByData = sharedByData
        self.sharedAt = sharedAt
    }
    
    /// Convert to domain model
    func toDomain() throws -> SharedRecipe {
        let decoder = JSONDecoder()
        let recipe = try decoder.decode(Recipe.self, from: recipeData)
        let user = try decoder.decode(User.self, from: sharedByData)
        
        return SharedRecipe(
            id: id,
            recipe: recipe,
            sharedBy: user,
            sharedAt: sharedAt
        )
    }
    
    /// Create from domain model
    static func from(_ sharedRecipe: SharedRecipe) throws -> SharedRecipeModel {
        let encoder = JSONEncoder()
        let recipeData = try encoder.encode(sharedRecipe.recipe)
        let userData = try encoder.encode(sharedRecipe.sharedBy)
        
        return SharedRecipeModel(
            id: sharedRecipe.id,
            recipeData: recipeData,
            sharedByData: userData,
            sharedAt: sharedRecipe.sharedAt
        )
    }
}
