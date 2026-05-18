//
//  SavedReferenceCloudService.swift
//  Cauldron
//

import Foundation
import CloudKit
import os

actor SavedReferenceCloudService {
    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "SavedReferenceCloudService")

    init(core: CloudKitCore) {
        self.core = core
    }

    nonisolated static func recipeReferenceRecordName(userId: UUID, sourceRecipeId: UUID) -> String {
        "savedRecipeReference_\(userId.uuidString)_\(sourceRecipeId.uuidString)"
    }

    nonisolated static func collectionReferenceRecordName(userId: UUID, sourceCollectionId: UUID) -> String {
        "savedCollectionReference_\(userId.uuidString)_\(sourceCollectionId.uuidString)"
    }

    func saveRecipeReference(_ reference: SavedRecipeReference) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: reference.cloudRecordName ?? Self.recipeReferenceRecordName(
                userId: reference.userId,
                sourceRecipeId: reference.sourceRecipeId
            ),
            zoneID: zoneID
        )
        let record = try await fetchOrCreateRecord(
            in: db,
            recordID: recordID,
            recordType: CloudKitCore.RecordType.savedRecipeReference
        )
        populateRecipeReferenceRecord(record, from: reference)
        _ = try await db.save(record)
    }

    func deleteRecipeReference(_ reference: SavedRecipeReference) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: reference.cloudRecordName ?? Self.recipeReferenceRecordName(
                userId: reference.userId,
                sourceRecipeId: reference.sourceRecipeId
            ),
            zoneID: zoneID
        )

        do {
            _ = try await db.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    func fetchRecipeReferences(for userId: UUID) async throws -> [SavedRecipeReference] {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.savedRecipeReference, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]

        do {
            let records = try await fetchAllRecords(matching: query, in: db, zoneID: zoneID)
            return records.compactMap { try? recipeReference(from: $0) }
        } catch let error as CKError where error.code == .unknownItem || error.errorCode == 11 {
            logger.info("SavedRecipeReference record type not yet in CloudKit schema - returning empty list")
            throw SavedReferenceCloudServiceError.recordTypeUnavailable
        }
    }

    func saveCollectionReference(_ reference: SavedCollectionReference) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: reference.cloudRecordName ?? Self.collectionReferenceRecordName(
                userId: reference.userId,
                sourceCollectionId: reference.sourceCollectionId
            ),
            zoneID: zoneID
        )
        let record = try await fetchOrCreateRecord(
            in: db,
            recordID: recordID,
            recordType: CloudKitCore.RecordType.savedCollectionReference
        )
        populateCollectionReferenceRecord(record, from: reference)
        _ = try await db.save(record)
    }

    func deleteCollectionReference(_ reference: SavedCollectionReference) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: reference.cloudRecordName ?? Self.collectionReferenceRecordName(
                userId: reference.userId,
                sourceCollectionId: reference.sourceCollectionId
            ),
            zoneID: zoneID
        )

        do {
            _ = try await db.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    func fetchCollectionReferences(for userId: UUID) async throws -> [SavedCollectionReference] {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.savedCollectionReference, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]

        do {
            let records = try await fetchAllRecords(matching: query, in: db, zoneID: zoneID)
            return records.compactMap { try? collectionReference(from: $0) }
        } catch let error as CKError where error.code == .unknownItem || error.errorCode == 11 {
            logger.info("SavedCollectionReference record type not yet in CloudKit schema - returning empty list")
            throw SavedReferenceCloudServiceError.recordTypeUnavailable
        }
    }

    func populateRecipeReferenceRecord(_ record: CKRecord, from reference: SavedRecipeReference) {
        record["id"] = reference.id.uuidString as CKRecordValue
        record["userId"] = reference.userId.uuidString as CKRecordValue
        record["sourceRecipeId"] = reference.sourceRecipeId.uuidString as CKRecordValue
        record["sourceOwnerId"] = reference.sourceOwnerId?.uuidString as CKRecordValue?
        record["sourceRecipeName"] = reference.sourceRecipeName as CKRecordValue?
        record["originalCreatorName"] = reference.originalCreatorName as CKRecordValue?
        record["materializedRecipeId"] = reference.materializedRecipeId?.uuidString as CKRecordValue?
        record["cloudRecordName"] = record.recordID.recordName as CKRecordValue
        record["savedAt"] = reference.savedAt as CKRecordValue
        record["sourceRecipeUpdatedAt"] = reference.sourceRecipeUpdatedAt as CKRecordValue?
        record["createdAt"] = reference.createdAt as CKRecordValue
        record["updatedAt"] = reference.updatedAt as CKRecordValue
    }

    func recipeReference(from record: CKRecord) throws -> SavedRecipeReference {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let sourceRecipeIdString = record["sourceRecipeId"] as? String,
              let sourceRecipeId = UUID(uuidString: sourceRecipeIdString),
              let savedAt = record["savedAt"] as? Date,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        return SavedRecipeReference(
            id: id,
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            sourceOwnerId: (record["sourceOwnerId"] as? String).flatMap(UUID.init(uuidString:)),
            sourceRecipeName: record["sourceRecipeName"] as? String,
            originalCreatorName: record["originalCreatorName"] as? String,
            materializedRecipeId: (record["materializedRecipeId"] as? String).flatMap(UUID.init(uuidString:)),
            cloudRecordName: record.recordID.recordName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: record["sourceRecipeUpdatedAt"] as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func populateCollectionReferenceRecord(_ record: CKRecord, from reference: SavedCollectionReference) {
        record["id"] = reference.id.uuidString as CKRecordValue
        record["userId"] = reference.userId.uuidString as CKRecordValue
        record["sourceCollectionId"] = reference.sourceCollectionId.uuidString as CKRecordValue
        record["sourceOwnerId"] = reference.sourceOwnerId.uuidString as CKRecordValue
        record["sourceCollectionName"] = reference.sourceCollectionName as CKRecordValue?
        record["cloudRecordName"] = record.recordID.recordName as CKRecordValue
        record["savedAt"] = reference.savedAt as CKRecordValue
        record["sourceCollectionUpdatedAt"] = reference.sourceCollectionUpdatedAt as CKRecordValue?
        record["createdAt"] = reference.createdAt as CKRecordValue
        record["updatedAt"] = reference.updatedAt as CKRecordValue
    }

    func collectionReference(from record: CKRecord) throws -> SavedCollectionReference {
        guard let idString = record["id"] as? String,
              let id = UUID(uuidString: idString),
              let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let sourceCollectionIdString = record["sourceCollectionId"] as? String,
              let sourceCollectionId = UUID(uuidString: sourceCollectionIdString),
              let sourceOwnerIdString = record["sourceOwnerId"] as? String,
              let sourceOwnerId = UUID(uuidString: sourceOwnerIdString),
              let savedAt = record["savedAt"] as? Date,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        return SavedCollectionReference(
            id: id,
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            sourceCollectionName: record["sourceCollectionName"] as? String,
            cloudRecordName: record.recordID.recordName,
            savedAt: savedAt,
            sourceCollectionUpdatedAt: record["sourceCollectionUpdatedAt"] as? Date,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func fetchOrCreateRecord(
        in database: CKDatabase,
        recordID: CKRecord.ID,
        recordType: String
    ) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func fetchAllRecords(
        matching query: CKQuery,
        in db: CKDatabase,
        zoneID: CKRecordZone.ID? = nil
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
            } else if let zoneID {
                results = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 500)
            } else {
                results = try await db.records(matching: query, resultsLimit: 500)
            }

            for (_, result) in results.matchResults {
                if let record = try? result.get() {
                    records.append(record)
                }
            }

            cursor = results.queryCursor
        } while cursor != nil

        return records
    }
}

enum SavedReferenceCloudServiceError: LocalizedError {
    case recordTypeUnavailable

    var errorDescription: String? {
        switch self {
        case .recordTypeUnavailable:
            return "Saved reference CloudKit records are not available yet."
        }
    }
}
