//
//  DeletedCollectionModel.swift
//  Cauldron
//

import Foundation
import SwiftData

/// Tracks deleted collections so deletion wins over stale CloudKit records.
@Model
final class DeletedCollectionModel {
    var collectionId: UUID?
    var ownerId: UUID?
    var deletedAt: Date?
    var cloudRecordName: String?
    var sourceDeviceId: String?
    var schemaVersion: Int = DeletedCollectionTombstone.currentSchemaVersion

    init(
        collectionId: UUID,
        ownerId: UUID,
        deletedAt: Date,
        cloudRecordName: String?,
        sourceDeviceId: String? = nil,
        schemaVersion: Int = DeletedCollectionTombstone.currentSchemaVersion
    ) {
        self.collectionId = collectionId
        self.ownerId = ownerId
        self.deletedAt = deletedAt
        self.cloudRecordName = cloudRecordName
        self.sourceDeviceId = sourceDeviceId
        self.schemaVersion = schemaVersion
    }
}
