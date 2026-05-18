//
//  SavedCollectionReference.swift
//  Cauldron
//

import Foundation

nonisolated struct SavedCollectionReference: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID
    let sourceCollectionId: UUID
    let sourceOwnerId: UUID
    let sourceCollectionName: String?
    let cloudRecordName: String?
    let savedAt: Date
    let sourceCollectionUpdatedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
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
}
