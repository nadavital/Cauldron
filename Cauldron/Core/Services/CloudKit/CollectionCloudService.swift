//
//  CollectionCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for collection operations.
//

import Foundation
import CloudKit
import os

struct DeletedCollectionTombstone: Sendable, Equatable {
    nonisolated static let currentSchemaVersion = 1

    let collectionId: UUID
    let ownerId: UUID
    let deletedAt: Date
    let cloudRecordName: String?
    let sourceDeviceId: String?
    let schemaVersion: Int

    nonisolated init(
        collectionId: UUID,
        ownerId: UUID,
        deletedAt: Date,
        cloudRecordName: String?,
        sourceDeviceId: String?,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.collectionId = collectionId
        self.ownerId = ownerId
        self.deletedAt = deletedAt
        self.cloudRecordName = cloudRecordName
        self.sourceDeviceId = sourceDeviceId
        self.schemaVersion = schemaVersion
    }
}

/// CloudKit service for collection-related operations.
///
/// Handles:
/// - Collection CRUD operations
/// - Collection reference management (saved collections)
/// - Cover image upload/download
actor CollectionCloudService {
    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionCloudService")
    private let maxSaveAttempts = 3

    init(core: CloudKitCore) {
        self.core = core
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Collection CRUD

    /// Save collection to PUBLIC database
    func saveCollection(_ collection: Collection) async throws {
        logger.info("💾 Saving collection: \(collection.name)")

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collection.id.uuidString)
        var conflictCandidate: CKRecord?

        for attempt in 1...maxSaveAttempts {
            let record: CKRecord
            if let conflictCandidate {
                record = conflictCandidate
            } else {
                record = try await fetchOrCreateCollectionRecord(recordID: recordID, in: db)
            }

            let shouldClearMissingOptionalFields = conflictCandidate == nil
            populateCollectionRecord(
                record,
                from: collection,
                clearingMissingOptionalFields: shouldClearMissingOptionalFields
            )

            do {
                _ = try await db.save(record)
                logger.info("✅ Saved collection to PUBLIC database")
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
                guard let serverRecord else {
                    logger.error("❌ Conflict without server record payload for collection: \(collection.name)")
                    throw error
                }

                logger.warning("⚠️ Save conflict for collection '\(collection.name)', retrying (\(attempt)/\(self.maxSaveAttempts))")
                conflictCandidate = makeConflictResolvedRecord(serverRecord: serverRecord, localCollection: collection)
            } catch {
                throw error
            }
        }

        logger.error("❌ Exhausted conflict retries for collection '\(collection.name)'")
        throw CloudKitError.syncConflict
    }

    /// Fetch user's own collections
    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        logger.info("📥 Fetching collections for user: \(userId)")

        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var collections: [Collection] = []
        var cursor: CKQueryOperation.Cursor?

        do {
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }

                for (_, result) in results.matchResults {
                    if let record = try? result.get(),
                       let collection = try? collectionFromRecord(record) {
                        collections.append(collection)
                    }
                }

                cursor = results.queryCursor
            } while cursor != nil
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty owner collection list")
                return []
            }
            throw error
        }

        logger.info("✅ Fetched \(collections.count) collections")
        return try await overlayMembershipEdges(on: collections)
    }

    /// Fetch shared collections from friends
    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        guard !friendIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()

        let friendIdStrings = friendIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility != %@",
            friendIdStrings,
            RecipeVisibility.privateRecipe.rawValue
        )
        let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query)

            var collections: [Collection] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let collection = try? collectionFromRecord(record) {
                    collections.append(collection)
                }
            }

            return try await overlayMembershipEdges(on: collections)
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Query collections by owner and visibility
    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        logger.info("🔍 Querying collections from \(ownerIds.count) owners with visibility: \(visibility.rawValue)")

        guard !ownerIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()

        let ownerIdStrings = ownerIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility == %@",
            ownerIdStrings,
            visibility.rawValue
        )

        let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query, resultsLimit: 100)

            var collections: [Collection] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let collection = try? collectionFromRecord(record) {
                    collections.append(collection)
                }
            }

            logger.info("✅ Found \(collections.count) collections")
            return try await overlayMembershipEdges(on: collections)
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Delete collection from PUBLIC database
    func deleteCollection(_ collectionId: UUID) async throws {
        logger.info("🗑️ Deleting collection: \(collectionId)")

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted collection")
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Collection not found in CloudKit (already deleted): \(collectionId)")
        }
    }

    // MARK: - Collection Membership

    nonisolated static func deletedCollectionRecordID(collectionId: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "deletedCollection_\(collectionId.uuidString)")
    }

    func saveDeletedCollectionTombstone(_ tombstone: DeletedCollectionTombstone) async throws {
        let db = try await core.getPublicDatabase()
        let recordID = Self.deletedCollectionRecordID(collectionId: tombstone.collectionId)
        var tombstoneToSave = tombstone
        var conflictCandidate: CKRecord?

        for attempt in 1...maxSaveAttempts {
            let record: CKRecord
            if let conflictCandidate {
                record = conflictCandidate
            } else {
                record = try await fetchOrCreateDeletedCollectionRecord(recordID: recordID, in: db)
            }

            populateDeletedCollectionRecord(record, from: tombstoneToSave)

            do {
                _ = try await db.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }

                let serverTombstone = try? deletedCollectionTombstone(from: serverRecord)
                tombstoneToSave = DeletedCollectionTombstone(
                    collectionId: tombstone.collectionId,
                    ownerId: tombstone.ownerId,
                    deletedAt: max(tombstone.deletedAt, serverTombstone?.deletedAt ?? tombstone.deletedAt),
                    cloudRecordName: tombstone.cloudRecordName ?? serverTombstone?.cloudRecordName,
                    sourceDeviceId: tombstone.sourceDeviceId ?? serverTombstone?.sourceDeviceId,
                    schemaVersion: max(tombstone.schemaVersion, serverTombstone?.schemaVersion ?? tombstone.schemaVersion)
                )
                conflictCandidate = serverRecord
                logger.warning("DeletedCollection save conflict for \(tombstone.collectionId), retrying \(attempt)/\(self.maxSaveAttempts)")
            } catch {
                throw error
            }
        }

        throw CloudKitError.syncConflict
    }

    func fetchDeletedCollectionTombstones(ownerId: UUID) async throws -> [DeletedCollectionTombstone] {
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.deletedCollection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]

        do {
            var tombstones: [DeletedCollectionTombstone] = []
            var cursor: CKQueryOperation.Cursor?

            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }

                tombstones += results.matchResults.compactMap { _, result in
                    guard let record = try? result.get() else { return nil }
                    return try? deletedCollectionTombstone(from: record)
                }
                cursor = results.queryCursor
            } while cursor != nil

            return tombstones
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("DeletedCollection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    nonisolated static func membershipRecordID(collectionId: UUID, recipeId: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "membership_\(collectionId.uuidString)_\(recipeId.uuidString)")
    }

    func saveMembershipEdge(_ edge: CollectionMembershipEdge) async throws {
        let db = try await core.getPublicDatabase()
        let recordID = Self.membershipRecordID(collectionId: edge.collectionId, recipeId: edge.recipeId)
        var record = try await fetchOrCreateMembershipRecord(recordID: recordID, in: db)

        for attempt in 1...maxSaveAttempts {
            populateMembershipRecord(record, from: edge)
            do {
                _ = try await db.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }

                if let serverEdge = try? membershipEdge(from: serverRecord),
                   serverEdge.updatedAt > edge.updatedAt {
                    return
                }

                logger.warning("CollectionMembership save conflict for \(edge.collectionId), retrying \(attempt)/\(self.maxSaveAttempts)")
                record = serverRecord
            } catch {
                throw error
            }
        }

        throw CloudKitError.syncConflict
    }

    func saveMembershipEdges(_ edges: [CollectionMembershipEdge]) async throws {
        for edge in edges {
            try await saveMembershipEdge(edge)
        }
    }

    func fetchMembershipEdges(forUserId userId: UUID) async throws -> [CollectionMembershipEdge] {
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "ownerId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.collectionMembership, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            var edges: [CollectionMembershipEdge] = []
            var cursor: CKQueryOperation.Cursor?

            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }

                edges += results.matchResults.compactMap { _, result in
                    guard let record = try? result.get() else { return nil }
                    return try? membershipEdge(from: record)
                }
                cursor = results.queryCursor
            } while cursor != nil

            return edges
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("CollectionMembership record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    // MARK: - Cover Image

    /// Upload collection cover image to CloudKit
    func uploadCollectionCoverImage(collectionId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading collection cover image for collection: \(collectionId)")

        let optimizedData = try await core.optimizeImageForCloudKit(imageData, maxDimension: 1200, targetSize: 2_000_000)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection_\(collectionId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let asset = CKAsset(fileURL: tempURL)

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            record["coverImageAsset"] = asset
            record["coverImageModifiedAt"] = Date() as CKRecordValue

            let savedRecord = try await db.save(record)
            logger.info("✅ Uploaded collection cover image asset")
            return savedRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.error("Collection record not found in CloudKit: \(collectionId)")
                throw CloudKitError.invalidRecord
            } else if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload collection cover image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download collection cover image from CloudKit
    func downloadCollectionCoverImage(collectionId: UUID) async throws -> Data? {
        logger.info("📥 Downloading collection cover image for collection: \(collectionId)")

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            guard let asset = record["coverImageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.info("No collection cover image asset found for collection: \(collectionId)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            logger.info("✅ Downloaded collection cover image (\(data.count) bytes)")
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return nil
            }
            throw error
        }
    }

    /// Delete collection cover image from CloudKit
    func deleteCollectionCoverImage(collectionId: UUID) async throws {
        logger.info("🗑️ Deleting collection cover image for collection: \(collectionId)")

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            record["coverImageAsset"] = nil
            record["coverImageModifiedAt"] = nil

            _ = try await db.save(record)
            logger.info("✅ Deleted collection cover image asset")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return
            }
            throw error
        }
    }

    // MARK: - Private Helpers

    private func fetchOrCreateCollectionRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            let record = try await db.record(for: recordID)
            logger.info("Updating existing collection record")
            return record
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Creating new collection record")
            return CKRecord(recordType: CloudKitCore.RecordType.collection, recordID: recordID)
        }
    }

    private func fetchOrCreateDeletedCollectionRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            return try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: CloudKitCore.RecordType.deletedCollection, recordID: recordID)
        }
    }

    private func makeConflictResolvedRecord(serverRecord: CKRecord, localCollection: Collection) -> CKRecord {
        populateCollectionRecord(
            serverRecord,
            from: localCollection,
            clearingMissingOptionalFields: false
        )
        return serverRecord
    }

    func populateCollectionRecord(
        _ record: CKRecord,
        from collection: Collection,
        clearingMissingOptionalFields: Bool = true
    ) {
        // Core fields
        record["collectionId"] = collection.id.uuidString as CKRecordValue
        record["name"] = collection.name as CKRecordValue
        record["userId"] = collection.userId.uuidString as CKRecordValue
        record["visibility"] = collection.visibility.rawValue as CKRecordValue
        record["createdAt"] = collection.createdAt as CKRecordValue
        record["updatedAt"] = collection.updatedAt as CKRecordValue
        record["coverImageType"] = collection.coverImageType.rawValue as CKRecordValue
        record["originalCollectionId"] = collection.originalCollectionId?.uuidString as CKRecordValue?
        record["originalCollectionOwnerId"] = collection.originalCollectionOwnerId?.uuidString as CKRecordValue?
        record["originalCollectionName"] = collection.originalCollectionName as CKRecordValue?
        record["savedAt"] = collection.savedAt as CKRecordValue?
        record["sourceCollectionUpdatedAt"] = collection.sourceCollectionUpdatedAt as CKRecordValue?
        record["followsSourceUpdates"] = (collection.followsSourceUpdates ? 1 : 0) as CKRecordValue

        // Optional fields.
        // On first save attempt, clear missing local fields so explicit user clears persist.
        // During conflict retry, preserve server values when local optionals are absent.
        if let description = collection.description {
            record["description"] = description as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["description"] = nil
        }

        if let emoji = collection.emoji {
            record["emoji"] = emoji as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["emoji"] = nil
        }

        if let symbolName = collection.symbolName {
            record["symbolName"] = symbolName as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["symbolName"] = nil
        }

        if let color = collection.color {
            record["color"] = color as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["color"] = nil
        }

        if let recipeIdsJSON = try? JSONEncoder().encode(collection.recipeIds),
           let recipeIdsString = String(data: recipeIdsJSON, encoding: .utf8) {
            record["recipeIds"] = recipeIdsString as CKRecordValue
        } else {
            logger.error("❌ Failed to encode recipe IDs for collection: \(collection.name)")
            record["recipeIds"] = "[]" as CKRecordValue
        }
    }

    func collectionFromRecord(_ record: CKRecord) throws -> Collection {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let name = record["name"] as? String,
              let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let visibilityString = record["visibility"] as? String,
              let visibility = RecipeVisibility(rawValue: visibilityString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        // Parse recipe IDs from JSON string
        let recipeIds: [UUID]
        if let recipeIdsString = record["recipeIds"] as? String,
           let recipeIdsData = recipeIdsString.data(using: .utf8),
           let ids = try? JSONDecoder().decode([UUID].self, from: recipeIdsData) {
            recipeIds = ids
        } else {
            recipeIds = []
        }

        let description = record["description"] as? String
        let emoji = record["emoji"] as? String
        let symbolName = record["symbolName"] as? String
        let color = record["color"] as? String
        let coverImageTypeString = record["coverImageType"] as? String
        let coverImageType = coverImageTypeString.flatMap { CoverImageType(rawValue: $0) } ?? .recipeGrid
        let coverImageModifiedAt = record["coverImageModifiedAt"] as? Date
        let hasCloudCoverImage = record["coverImageAsset"] as? CKAsset != nil || coverImageModifiedAt != nil
        let cloudCoverImageRecordName = hasCloudCoverImage ? record.recordID.recordName : nil
        let originalCollectionId = (record["originalCollectionId"] as? String).flatMap(UUID.init(uuidString:))
        let originalCollectionOwnerId = (record["originalCollectionOwnerId"] as? String).flatMap(UUID.init(uuidString:))
        let followsSourceUpdates = Self.boolValue(for: record["followsSourceUpdates"])

        return Collection(
            id: collectionId,
            name: name,
            description: description,
            userId: userId,
            recipeIds: recipeIds,
            visibility: visibility,
            emoji: emoji,
            symbolName: symbolName,
            color: color,
            coverImageType: coverImageType,
            cloudCoverImageRecordName: cloudCoverImageRecordName,
            coverImageModifiedAt: coverImageModifiedAt,
            cloudRecordName: record.recordID.recordName,
            originalCollectionId: originalCollectionId,
            originalCollectionOwnerId: originalCollectionOwnerId,
            originalCollectionName: record["originalCollectionName"] as? String,
            savedAt: record["savedAt"] as? Date,
            sourceCollectionUpdatedAt: record["sourceCollectionUpdatedAt"] as? Date,
            followsSourceUpdates: followsSourceUpdates,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func overlayMembershipEdges(on collections: [Collection]) async throws -> [Collection] {
        guard !collections.isEmpty else { return [] }

        var allEdges: [CollectionMembershipEdge] = []
        for ownerId in Set(collections.map(\.userId)) {
            allEdges.append(contentsOf: try await fetchMembershipEdges(forUserId: ownerId))
        }

        let edgesByCollectionId = Dictionary(grouping: allEdges, by: \.collectionId)
        guard !edgesByCollectionId.isEmpty else { return collections }

        return collections.map { collection in
            guard let edges = edgesByCollectionId[collection.id] else {
                return collection
            }
            return collectionWithRecipeIds(collection, activeRecipeIds(from: edges))
        }
    }

    private func activeRecipeIds(from edges: [CollectionMembershipEdge]) -> [UUID] {
        edges
            .filter { $0.status == .active }
            .sorted(by: { (lhs: CollectionMembershipEdge, rhs: CollectionMembershipEdge) in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.updatedAt < rhs.updatedAt
            })
            .map(\.recipeId)
    }

    private func collectionWithRecipeIds(_ collection: Collection, _ recipeIds: [UUID]) -> Collection {
        Collection(
            id: collection.id,
            name: collection.name,
            description: collection.description,
            userId: collection.userId,
            recipeIds: recipeIds,
            visibility: collection.visibility,
            emoji: collection.emoji,
            symbolName: collection.symbolName,
            color: collection.color,
            coverImageType: collection.coverImageType,
            coverImageURL: collection.coverImageURL,
            cloudCoverImageRecordName: collection.cloudCoverImageRecordName,
            coverImageModifiedAt: collection.coverImageModifiedAt,
            cloudRecordName: collection.cloudRecordName,
            originalCollectionId: collection.originalCollectionId,
            originalCollectionOwnerId: collection.originalCollectionOwnerId,
            originalCollectionName: collection.originalCollectionName,
            savedAt: collection.savedAt,
            sourceCollectionUpdatedAt: collection.sourceCollectionUpdatedAt,
            followsSourceUpdates: collection.followsSourceUpdates,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt
        )
    }

    private func fetchOrCreateMembershipRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            return try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: CloudKitCore.RecordType.collectionMembership, recordID: recordID)
        }
    }

    func populateMembershipRecord(_ record: CKRecord, from edge: CollectionMembershipEdge) {
        record["collectionId"] = edge.collectionId.uuidString as CKRecordValue
        record["recipeId"] = edge.recipeId.uuidString as CKRecordValue
        record["ownerId"] = edge.ownerId.uuidString as CKRecordValue
        record["status"] = edge.status.rawValue as CKRecordValue
        record["updatedAt"] = edge.updatedAt as CKRecordValue
        record["sortOrder"] = edge.sortOrder as NSNumber
        record["sourceDeviceId"] = edge.sourceDeviceId as CKRecordValue?
        record["schemaVersion"] = edge.schemaVersion as NSNumber
    }

    func membershipEdge(from record: CKRecord) throws -> CollectionMembershipEdge {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let recipeIdString = record["recipeId"] as? String,
              let recipeId = UUID(uuidString: recipeIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let statusString = record["status"] as? String,
              let status = CollectionMembershipStatus(rawValue: statusString),
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        let sortOrder = (record["sortOrder"] as? NSNumber)?.intValue ?? 0
        let schemaVersion = (record["schemaVersion"] as? NSNumber)?.intValue ?? CollectionMembershipEdge.currentSchemaVersion
        return CollectionMembershipEdge(
            collectionId: collectionId,
            recipeId: recipeId,
            ownerId: ownerId,
            status: status,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            sourceDeviceId: record["sourceDeviceId"] as? String,
            schemaVersion: schemaVersion
        )
    }

    func populateDeletedCollectionRecord(_ record: CKRecord, from tombstone: DeletedCollectionTombstone) {
        record["collectionId"] = tombstone.collectionId.uuidString as CKRecordValue
        record["ownerId"] = tombstone.ownerId.uuidString as CKRecordValue
        record["deletedAt"] = tombstone.deletedAt as CKRecordValue
        record["cloudRecordName"] = tombstone.cloudRecordName as CKRecordValue?
        record["sourceDeviceId"] = tombstone.sourceDeviceId as CKRecordValue?
        record["schemaVersion"] = tombstone.schemaVersion as NSNumber
    }

    func deletedCollectionTombstone(from record: CKRecord) throws -> DeletedCollectionTombstone {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let deletedAt = record["deletedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        return DeletedCollectionTombstone(
            collectionId: collectionId,
            ownerId: ownerId,
            deletedAt: deletedAt,
            cloudRecordName: record["cloudRecordName"] as? String,
            sourceDeviceId: record["sourceDeviceId"] as? String,
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue ?? DeletedCollectionTombstone.currentSchemaVersion
        )
    }

    private nonisolated static func boolValue(for value: CKRecordValue?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return false
    }
}
