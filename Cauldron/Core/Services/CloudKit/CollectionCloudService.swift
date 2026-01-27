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

        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing collection record")
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitCore.RecordType.collection, recordID: recordID)
            logger.info("Creating new collection record")
        }

        // Core fields
        record["collectionId"] = collection.id.uuidString as CKRecordValue
        record["name"] = collection.name as CKRecordValue
        record["userId"] = collection.userId.uuidString as CKRecordValue
        record["visibility"] = collection.visibility.rawValue as CKRecordValue
        record["createdAt"] = collection.createdAt as CKRecordValue
        record["updatedAt"] = collection.updatedAt as CKRecordValue

        // Optional fields
        if let description = collection.description {
            record["description"] = description as CKRecordValue
        }
        if let emoji = collection.emoji {
            record["emoji"] = emoji as CKRecordValue
        }
        if let color = collection.color {
            record["color"] = color as CKRecordValue
        }
        record["coverImageType"] = collection.coverImageType.rawValue as CKRecordValue

        // Recipe IDs stored as JSON string
        if let recipeIdsJSON = try? JSONEncoder().encode(collection.recipeIds),
           let recipeIdsString = String(data: recipeIdsJSON, encoding: .utf8) {
            record["recipeIds"] = recipeIdsString as CKRecordValue
        }

        _ = try await db.save(record)
        logger.info("✅ Saved collection to PUBLIC database")
    }

    /// Fetch user's own collections
    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        logger.info("📥 Fetching collections for user: \(userId)")

        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query)

        var collections: [Collection] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let collection = try? collectionFromRecord(record) {
                collections.append(collection)
            }
        }

        logger.info("✅ Fetched \(collections.count) collections")
        return collections
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

            return collections
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
            return collections
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

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted collection")
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
        let color = record["color"] as? String
        let coverImageTypeString = record["coverImageType"] as? String
        let coverImageType = coverImageTypeString.flatMap { CoverImageType(rawValue: $0) } ?? .recipeGrid

        return Collection(
            id: collectionId,
            name: name,
            description: description,
            userId: userId,
            recipeIds: recipeIds,
            visibility: visibility,
            emoji: emoji,
            color: color,
            coverImageType: coverImageType,
            cloudRecordName: record.recordID.recordName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
