//
//  CollectionModel.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftData

/// SwiftData persistence model for Collection
@Model
final class CollectionModel {
    var id: UUID = UUID()
    var name: String = ""
    var descriptionText: String?  // "description" is reserved in SwiftData
    var userId: UUID = UUID()  // Default value required for CloudKit
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Recipe membership stored as JSON blob for schema stability
    var recipeIdsBlob: Data = Data()

    // Presentation
    var emoji: String?
    var color: String?
    var coverImageType: String = "recipeGrid"  // CoverImageType rawValue

    // Sharing
    var visibility: String = "private"  // RecipeVisibility rawValue

    // CloudKit sync
    var cloudRecordName: String?

    init(
        id: UUID = UUID(),
        name: String,
        descriptionText: String? = nil,
        userId: UUID,
        recipeIdsBlob: Data = Data(),
        emoji: String? = nil,
        color: String? = nil,
        coverImageType: String = "recipeGrid",
        visibility: String = "private",
        cloudRecordName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.userId = userId
        self.recipeIdsBlob = recipeIdsBlob
        self.emoji = emoji
        self.color = color
        self.coverImageType = coverImageType
        self.visibility = visibility
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convert from domain Collection to CollectionModel
    static func from(_ collection: Collection) throws -> CollectionModel {
        let encoder = JSONEncoder()
        let recipeIdsData = try encoder.encode(collection.recipeIds)

        return CollectionModel(
            id: collection.id,
            name: collection.name,
            descriptionText: collection.description,
            userId: collection.userId,
            recipeIdsBlob: recipeIdsData,
            emoji: collection.emoji,
            color: collection.color,
            coverImageType: collection.coverImageType.rawValue,
            visibility: collection.visibility.rawValue,
            cloudRecordName: collection.cloudRecordName,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt
        )
    }

    /// Convert to domain Collection
    func toDomain() throws -> Collection {
        let decoder = JSONDecoder()
        let recipeIds = try decoder.decode([UUID].self, from: recipeIdsBlob)

        return Collection(
            id: id,
            name: name,
            description: descriptionText,
            userId: userId,
            recipeIds: recipeIds,
            visibility: RecipeVisibility(rawValue: visibility) ?? .privateRecipe,
            emoji: emoji,
            color: color,
            coverImageType: CoverImageType(rawValue: coverImageType) ?? .recipeGrid,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
