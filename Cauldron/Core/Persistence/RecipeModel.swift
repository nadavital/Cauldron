//
//  RecipeModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData
import os

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
    var relatedRecipeIdsBlob: Data = Data()
    
    // Source info
    var sourceURL: String?
    var sourceTitle: String?
    
    // Additional fields
    var notes: String?
    var imageURL: String?
    var isFavorite: Bool = false

    // CloudKit sync fields
    var visibility: String = "private"  // RecipeVisibility rawValue
    var ownerId: UUID?
    var cloudRecordName: String?
    var cloudImageRecordName: String?  // CloudKit asset record name for image
    var imageModifiedAt: Date?  // Timestamp when image was last modified

    // Attribution fields for copied recipes
    var originalRecipeId: UUID?
    var originalCreatorId: UUID?
    var originalCreatorName: String?
    var savedAt: Date?
    var isPreview: Bool = false  // true = saved locally but not owned (invisible in library)

    init(
        id: UUID = UUID(),
        title: String,
        ingredientsBlob: Data,
        stepsBlob: Data,
        tagsBlob: Data,
        yields: String = "4 servings",
        totalMinutes: Int? = nil,
        nutritionBlob: Data? = nil,
        relatedRecipeIdsBlob: Data = Data(),
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        notes: String? = nil,
        imageURL: String? = nil,
        isFavorite: Bool = false,
        visibility: String = "private",
        ownerId: UUID? = nil,
        cloudRecordName: String? = nil,
        cloudImageRecordName: String? = nil,
        imageModifiedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originalRecipeId: UUID? = nil,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil,
        savedAt: Date? = nil,
        isPreview: Bool = false
    ) {
        self.id = id
        self.title = title
        self.ingredientsBlob = ingredientsBlob
        self.stepsBlob = stepsBlob
        self.tagsBlob = tagsBlob
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.nutritionBlob = nutritionBlob
        self.relatedRecipeIdsBlob = relatedRecipeIdsBlob
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.notes = notes
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.visibility = visibility
        self.ownerId = ownerId
        self.cloudRecordName = cloudRecordName
        self.cloudImageRecordName = cloudImageRecordName
        self.imageModifiedAt = imageModifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalRecipeId = originalRecipeId
        self.originalCreatorId = originalCreatorId
        self.originalCreatorName = originalCreatorName
        self.savedAt = savedAt
        self.isPreview = isPreview
    }
    
    /// Convert from domain Recipe to RecipeModel
    static func from(_ recipe: Recipe) throws -> RecipeModel {
        let encoder = JSONEncoder()
        
        let ingredientsData = try encoder.encode(recipe.ingredients)
        let stepsData = try encoder.encode(recipe.steps)
        let tagsData = try encoder.encode(recipe.tags)
        let nutritionData = try recipe.nutrition.map { try encoder.encode($0) }
        let relatedIdsData = try encoder.encode(recipe.relatedRecipeIds)
        
        return RecipeModel(
            id: recipe.id,
            title: recipe.title,
            ingredientsBlob: ingredientsData,
            stepsBlob: stepsData,
            tagsBlob: tagsData,
            yields: recipe.yields,
            totalMinutes: recipe.totalMinutes,
            nutritionBlob: nutritionData,
            relatedRecipeIdsBlob: relatedIdsData,
            sourceURL: recipe.sourceURL?.absoluteString,
            sourceTitle: recipe.sourceTitle,
            notes: recipe.notes,
            // Store only the filename, not the full path
            // This prevents issues when the Documents directory path changes (app rebuild, etc.)
            imageURL: recipe.imageURL?.lastPathComponent,
            isFavorite: recipe.isFavorite,
            visibility: recipe.visibility.rawValue,
            ownerId: recipe.ownerId,
            cloudRecordName: recipe.cloudRecordName,
            cloudImageRecordName: recipe.cloudImageRecordName,
            imageModifiedAt: recipe.imageModifiedAt,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt,
            originalRecipeId: recipe.originalRecipeId,
            originalCreatorId: recipe.originalCreatorId,
            originalCreatorName: recipe.originalCreatorName,
            savedAt: recipe.savedAt,
            isPreview: recipe.isPreview
        )
    }
    
    /// Convert to domain Recipe
    func toDomain() throws -> Recipe {
        let decoder = JSONDecoder()

        let ingredients = try decoder.decode([Ingredient].self, from: ingredientsBlob)
        let steps = try decoder.decode([CookStep].self, from: stepsBlob)
        let tags = try decoder.decode([Tag].self, from: tagsBlob)
        let nutrition = try nutritionBlob.map { try decoder.decode(Nutrition.self, from: $0) }
        
        // Handle related recipes - default to empty if blob is empty (migration safety)
        let relatedRecipeIds: [UUID]
        if relatedRecipeIdsBlob.isEmpty {
            relatedRecipeIds = []
        } else {
            relatedRecipeIds = try decoder.decode([UUID].self, from: relatedRecipeIdsBlob)
        }

        // Reconstruct image URL from filename
        // Always build the URL dynamically to handle Documents directory path changes
        var finalImageURL: URL? = nil
        if let imageURLString = imageURL, !imageURLString.isEmpty {
            // Extract filename (handles both old full URLs and new filename-only format)
            let filename: String
            if imageURLString.contains("/") {
                // Old format: full URL - extract filename from path
                if let url = URL(string: imageURLString) {
                    filename = url.lastPathComponent
                    AppLogger.general.debug("🔄 Migrating old imageURL format to filename: \(filename)")
                } else {
                    AppLogger.general.warning("⚠️ Failed to parse imageURL: \(imageURLString)")
                    return Recipe(
                        id: id, title: title, ingredients: ingredients, steps: steps,
                        yields: yields, totalMinutes: totalMinutes, tags: tags, nutrition: nutrition,
                        sourceURL: sourceURL.flatMap { URL(string: $0) }, sourceTitle: sourceTitle,
                        notes: notes, imageURL: nil, isFavorite: isFavorite,
                        visibility: RecipeVisibility(rawValue: visibility) ?? .privateRecipe,
                        ownerId: ownerId, cloudRecordName: cloudRecordName,
                        createdAt: createdAt, updatedAt: updatedAt,
                        relatedRecipeIds: relatedRecipeIds, isPreview: isPreview
                    )
                }
            } else {
                // New format: already a filename
                filename = imageURLString
            }

            // Reconstruct full URL using current Documents directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            finalImageURL = documentsURL.appendingPathComponent("RecipeImages").appendingPathComponent(filename)
        }

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
            imageURL: finalImageURL,
            isFavorite: isFavorite,
            visibility: RecipeVisibility(rawValue: visibility) ?? .privateRecipe,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
}
