//
//  RecipeModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// SwiftData persistence model for Recipe
@Model
final class RecipeModel {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var yields: String = "4 servings"
    var totalMinutes: Int?
    
    // Arrays stored as JSON blobs for schema stability in v1
    var ingredientsBlob: Data = Data()
    var stepsBlob: Data = Data()
    var tagsBlob: Data = Data()
    var nutritionBlob: Data?
    
    // Source info
    var sourceURL: String?
    var sourceTitle: String?
    
    // Additional fields
    var notes: String?
    var imageURL: String?
    var isFavorite: Bool = false
    
    init(
        id: UUID = UUID(),
        title: String,
        ingredientsBlob: Data,
        stepsBlob: Data,
        tagsBlob: Data,
        yields: String = "4 servings",
        totalMinutes: Int? = nil,
        nutritionBlob: Data? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        notes: String? = nil,
        imageURL: String? = nil,
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.ingredientsBlob = ingredientsBlob
        self.stepsBlob = stepsBlob
        self.tagsBlob = tagsBlob
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.nutritionBlob = nutritionBlob
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.notes = notes
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    /// Convert from domain Recipe to RecipeModel
    static func from(_ recipe: Recipe) throws -> RecipeModel {
        let encoder = JSONEncoder()
        
        let ingredientsData = try encoder.encode(recipe.ingredients)
        let stepsData = try encoder.encode(recipe.steps)
        let tagsData = try encoder.encode(recipe.tags)
        let nutritionData = try recipe.nutrition.map { try encoder.encode($0) }
        
        return RecipeModel(
            id: recipe.id,
            title: recipe.title,
            ingredientsBlob: ingredientsData,
            stepsBlob: stepsData,
            tagsBlob: tagsData,
            yields: recipe.yields,
            totalMinutes: recipe.totalMinutes,
            nutritionBlob: nutritionData,
            sourceURL: recipe.sourceURL?.absoluteString,
            sourceTitle: recipe.sourceTitle,
            notes: recipe.notes,
            imageURL: recipe.imageURL?.absoluteString,
            isFavorite: recipe.isFavorite,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt
        )
    }
    
    /// Convert to domain Recipe
    func toDomain() throws -> Recipe {
        let decoder = JSONDecoder()
        
        let ingredients = try decoder.decode([Ingredient].self, from: ingredientsBlob)
        let steps = try decoder.decode([CookStep].self, from: stepsBlob)
        let tags = try decoder.decode([Tag].self, from: tagsBlob)
        let nutrition = try nutritionBlob.map { try decoder.decode(Nutrition.self, from: $0) }
        
        return Recipe(
            id: id,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL.flatMap { URL(string: $0) },
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: imageURL.flatMap { URL(string: $0) },
            isFavorite: isFavorite,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
