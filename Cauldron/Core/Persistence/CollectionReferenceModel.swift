//
//  CollectionReferenceModel.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftData

/// SwiftData persistence model for CollectionReference
@Model
final class CollectionReferenceModel {
    var id: UUID = UUID()
    var userId: UUID = UUID()
    var originalCollectionId: UUID = UUID()
    var originalOwnerId: UUID = UUID()
    var savedAt: Date = Date()

    // Cached metadata
    var collectionName: String = ""
    var collectionEmoji: String?
    var recipeCount: Int = 0

    // CloudKit sync
    var cloudRecordName: String?

    init(
        id: UUID = UUID(),
        userId: UUID,
        originalCollectionId: UUID,
        originalOwnerId: UUID,
        savedAt: Date = Date(),
        collectionName: String,
        collectionEmoji: String? = nil,
        recipeCount: Int = 0,
        cloudRecordName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.originalCollectionId = originalCollectionId
        self.originalOwnerId = originalOwnerId
        self.savedAt = savedAt
        self.collectionName = collectionName
        self.collectionEmoji = collectionEmoji
        self.recipeCount = recipeCount
        self.cloudRecordName = cloudRecordName
    }

    /// Convert from domain CollectionReference to CollectionReferenceModel
    static func from(_ reference: CollectionReference) -> CollectionReferenceModel {
        CollectionReferenceModel(
            id: reference.id,
            userId: reference.userId,
            originalCollectionId: reference.originalCollectionId,
            originalOwnerId: reference.originalOwnerId,
            savedAt: reference.savedAt,
            collectionName: reference.collectionName,
            collectionEmoji: reference.collectionEmoji,
            recipeCount: reference.recipeCount,
            cloudRecordName: reference.cloudRecordName
        )
    }

    /// Convert to domain CollectionReference
    func toDomain() -> CollectionReference {
        CollectionReference(
            id: id,
            userId: userId,
            originalCollectionId: originalCollectionId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            collectionName: collectionName,
            collectionEmoji: collectionEmoji,
            recipeCount: recipeCount,
            cloudRecordName: cloudRecordName
        )
    }
}
