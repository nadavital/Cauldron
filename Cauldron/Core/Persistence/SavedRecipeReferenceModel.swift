//
//  SavedRecipeReferenceModel.swift
//  Cauldron
//

import Foundation
import SwiftData

@Model
final class SavedRecipeReferenceModel {
    var id: UUID = UUID()
    var userId: UUID = UUID()
    var sourceRecipeId: UUID = UUID()
    var sourceOwnerId: UUID?
    var sourceRecipeName: String?
    var originalCreatorName: String?
    var materializedRecipeId: UUID?
    var cloudRecordName: String?
    var savedAt: Date = Date()
    var sourceRecipeUpdatedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        userId: UUID,
        sourceRecipeId: UUID,
        sourceOwnerId: UUID? = nil,
        sourceRecipeName: String? = nil,
        originalCreatorName: String? = nil,
        materializedRecipeId: UUID? = nil,
        cloudRecordName: String? = nil,
        savedAt: Date = Date(),
        sourceRecipeUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.sourceRecipeId = sourceRecipeId
        self.sourceOwnerId = sourceOwnerId
        self.sourceRecipeName = sourceRecipeName
        self.originalCreatorName = originalCreatorName
        self.materializedRecipeId = materializedRecipeId
        self.cloudRecordName = cloudRecordName
        self.savedAt = savedAt
        self.sourceRecipeUpdatedAt = sourceRecipeUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func from(_ reference: SavedRecipeReference) -> SavedRecipeReferenceModel {
        SavedRecipeReferenceModel(
            id: reference.id,
            userId: reference.userId,
            sourceRecipeId: reference.sourceRecipeId,
            sourceOwnerId: reference.sourceOwnerId,
            sourceRecipeName: reference.sourceRecipeName,
            originalCreatorName: reference.originalCreatorName,
            materializedRecipeId: reference.materializedRecipeId,
            cloudRecordName: reference.cloudRecordName,
            savedAt: reference.savedAt,
            sourceRecipeUpdatedAt: reference.sourceRecipeUpdatedAt,
            createdAt: reference.createdAt,
            updatedAt: reference.updatedAt
        )
    }

    func toDomain() -> SavedRecipeReference {
        SavedRecipeReference(
            id: id,
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            sourceOwnerId: sourceOwnerId,
            sourceRecipeName: sourceRecipeName,
            originalCreatorName: originalCreatorName,
            materializedRecipeId: materializedRecipeId,
            cloudRecordName: cloudRecordName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
