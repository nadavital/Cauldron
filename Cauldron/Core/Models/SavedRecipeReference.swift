//
//  SavedRecipeReference.swift
//  Cauldron
//

import Foundation

nonisolated struct SavedRecipeReference: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID
    let sourceRecipeId: UUID
    let sourceOwnerId: UUID?
    let sourceRecipeName: String?
    let originalCreatorName: String?
    let materializedRecipeId: UUID?
    let cloudRecordName: String?
    let savedAt: Date
    let sourceRecipeUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
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

    nonisolated func withMaterializedRecipeId(_ recipeId: UUID?) -> SavedRecipeReference {
        SavedRecipeReference(
            id: id,
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            sourceOwnerId: sourceOwnerId,
            sourceRecipeName: sourceRecipeName,
            originalCreatorName: originalCreatorName,
            materializedRecipeId: recipeId,
            cloudRecordName: cloudRecordName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}
