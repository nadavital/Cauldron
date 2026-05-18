//
//  SavedCollectionReferenceModel.swift
//  Cauldron
//

import Foundation
import SwiftData

@Model
final class SavedCollectionReferenceModel {
    var id: UUID = UUID()
    var userId: UUID = UUID()
    var sourceCollectionId: UUID = UUID()
    var sourceOwnerId: UUID = UUID()
    var sourceCollectionName: String?
    var cloudRecordName: String?
    var savedAt: Date = Date()
    var sourceCollectionUpdatedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        userId: UUID,
        sourceCollectionId: UUID,
        sourceOwnerId: UUID,
        sourceCollectionName: String? = nil,
        cloudRecordName: String? = nil,
        savedAt: Date = Date(),
        sourceCollectionUpdatedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.sourceCollectionId = sourceCollectionId
        self.sourceOwnerId = sourceOwnerId
        self.sourceCollectionName = sourceCollectionName
        self.cloudRecordName = cloudRecordName
        self.savedAt = savedAt
        self.sourceCollectionUpdatedAt = sourceCollectionUpdatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func from(_ reference: SavedCollectionReference) -> SavedCollectionReferenceModel {
        SavedCollectionReferenceModel(
            id: reference.id,
            userId: reference.userId,
            sourceCollectionId: reference.sourceCollectionId,
            sourceOwnerId: reference.sourceOwnerId,
            sourceCollectionName: reference.sourceCollectionName,
            cloudRecordName: reference.cloudRecordName,
            savedAt: reference.savedAt,
            sourceCollectionUpdatedAt: reference.sourceCollectionUpdatedAt,
            createdAt: reference.createdAt,
            updatedAt: reference.updatedAt
        )
    }

    func toDomain() -> SavedCollectionReference {
        SavedCollectionReference(
            id: id,
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            sourceCollectionName: sourceCollectionName,
            cloudRecordName: cloudRecordName,
            savedAt: savedAt,
            sourceCollectionUpdatedAt: sourceCollectionUpdatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
