//
//  CollectionCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for collection operations.
//

import Foundation
import CloudKit
import os

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

        let collectionsWithMemberships = await applyMembershipOverlay(to: collections)
        logger.info("✅ Fetched \(collectionsWithMemberships.count) collections")
        return collectionsWithMemberships
    }

    /// Fetch shared collections from friends
    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        guard !friendIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()

        do {
            var collections: [Collection] = []
            for friendIdChunk in Self.chunkedStrings(friendIds.map(\.uuidString)) {
                let predicate = NSPredicate(
                    format: "userId IN %@ AND visibility != %@",
                    friendIdChunk,
                    RecipeVisibility.privateRecipe.rawValue
                )
                let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

                let records = try await fetchAllRecords(matching: query, in: db)
                for record in records {
                    guard let collection = try? collectionFromRecord(record) else { continue }
                    collections.append(collection)
                }
            }

            return await applyMembershipOverlay(to: deduplicatedAndSortedCollections(collections))
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

        do {
            var collections: [Collection] = []
            for ownerIdChunk in Self.chunkedStrings(ownerIds.map(\.uuidString)) {
                let predicate = NSPredicate(
                    format: "userId IN %@ AND visibility == %@",
                    ownerIdChunk,
                    visibility.rawValue
                )

                let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

                let records = try await fetchAllRecords(matching: query, in: db)
                for record in records {
                    guard let collection = try? collectionFromRecord(record) else { continue }
                    collections.append(collection)
                }
            }

            let collectionsWithMemberships = await applyMembershipOverlay(to: deduplicatedAndSortedCollections(collections))
            logger.info("✅ Found \(collectionsWithMemberships.count) collections")
            return collectionsWithMemberships
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    func fetchPublicCollections(ids: [UUID]) async throws -> [UUID: Collection] {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return [:] }

        let db = try await core.getPublicDatabase()
        var collections: [Collection] = []

        for id in uniqueIds {
            let recordID = CKRecord.ID(recordName: id.uuidString)
            do {
                let record = try await db.record(for: recordID)
                let collection = try collectionFromRecord(record)
                guard collection.visibility != .privateRecipe else { continue }
                collections.append(collection)
            } catch let error as CKError where error.code == .unknownItem {
                continue
            } catch {
                logger.warning("Failed to fetch saved source collection \(id.uuidString): \(error.localizedDescription)")
            }
        }

        let overlaidCollections = await applyMembershipOverlay(to: collections)
        return Dictionary(uniqueKeysWithValues: overlaidCollections.map { ($0.id, $0) })
    }

    /// Delete collection from PUBLIC database
    func deleteCollection(_ collectionId: UUID, ownerId: UUID? = nil) async throws {
        logger.info("🗑️ Deleting collection: \(collectionId)")

        if let ownerId {
            try await deleteMembershipEdges(forCollectionId: collectionId, ownerId: ownerId)
        }

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

    func deleteMembershipEdges(forCollectionId collectionId: UUID, ownerId: UUID) async throws {
        let edges = try await fetchMembershipEdges(forUserId: ownerId)
            .filter { $0.collectionId == collectionId }

        guard !edges.isEmpty else {
            logger.info("No collection membership edges found to delete for collection: \(collectionId)")
            return
        }

        let db = try await core.getPublicDatabase()
        let recordIDs = edges.map {
            Self.membershipRecordID(collectionId: $0.collectionId, recipeId: $0.recipeId)
        }

        for chunk in Self.chunked(recordIDs, size: 200) {
            try await deleteRecordIDs(chunk, in: db)
        }

        logger.info("✅ Deleted \(edges.count) collection membership edges for collection: \(collectionId)")
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

    private func fetchAllRecords(
        matching query: CKQuery,
        in db: CKDatabase,
        resultsLimit: Int = 500
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: resultsLimit)
            } else {
                results = try await db.records(matching: query, resultsLimit: resultsLimit)
            }

            records += results.matchResults.compactMap { _, result in
                try? result.get()
            }
            cursor = results.queryCursor
        } while cursor != nil

        return records
    }

    private func deleteRecordIDs(_ recordIDs: [CKRecord.ID], in db: CKDatabase) async throws {
        guard !recordIDs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.database = db
            operation.start()
        }
    }

    private func deduplicatedAndSortedCollections(_ collections: [Collection]) -> [Collection] {
        var byId: [UUID: Collection] = [:]
        for collection in collections {
            if let existing = byId[collection.id] {
                if collection.updatedAt > existing.updatedAt {
                    byId[collection.id] = collection
                }
            } else {
                byId[collection.id] = collection
            }
        }

        return byId.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func applyMembershipOverlay(to collections: [Collection]) async -> [Collection] {
        guard !collections.isEmpty else { return [] }

        var edges: [CollectionMembershipEdge] = []
        for ownerId in Set(collections.map(\.userId)) {
            do {
                edges += try await fetchMembershipEdges(forUserId: ownerId)
            } catch {
                logger.warning("Failed to fetch collection memberships for owner \(ownerId.uuidString): \(error.localizedDescription)")
            }
        }

        guard !edges.isEmpty else { return collections }

        let edgesByCollection = Dictionary(grouping: edges, by: \.collectionId)
        return collections.map { collection in
            guard let collectionEdges = edgesByCollection[collection.id], !collectionEdges.isEmpty else {
                return collection
            }
            return CollectionMembershipProjection.collectionWithRecipeIds(
                collection,
                CollectionMembershipProjection.activeRecipeIds(from: collectionEdges)
            )
        }
    }

    private nonisolated static func chunkedStrings(_ values: [String], size: Int = 100) -> [[String]] {
        chunked(values, size: size)
    }

    private nonisolated static func chunked<Value>(_ values: [Value], size: Int) -> [[Value]] {
        guard size > 0, !values.isEmpty else { return [] }

        return stride(from: 0, to: values.count, by: size).map { startIndex in
            let endIndex = min(startIndex + size, values.count)
            return Array(values[startIndex..<endIndex])
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

        if collection.coverImageType != .customImage, clearingMissingOptionalFields {
            record["coverImageAsset"] = nil
            record["coverImageModifiedAt"] = nil
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
        let hasCloudCoverImage = record["coverImageAsset"] as? CKAsset != nil
        let coverImageModifiedAt = record["coverImageModifiedAt"] as? Date
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
            cloudCoverImageRecordName: hasCloudCoverImage ? record.recordID.recordName : nil,
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
