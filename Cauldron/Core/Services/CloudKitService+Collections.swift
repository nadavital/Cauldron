//
//  CloudKitService+Collections.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os
#if canImport(UIKit)
import UIKit
#endif

extension CloudKitService {
    // MARK: - Collections

    /// Save collection to PUBLIC database (for sharing)
    func saveCollection(_ collection: Collection) async throws {
        logger.info("💾 Saving collection: \(collection.name)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collection.id.uuidString)

        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing collection record")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: collectionRecordType, recordID: recordID)
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

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
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

    /// Fetch shared collections from friends (friends-only and public visibility)
    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        // Fetching shared collections (don't log routine operations)

        guard !friendIds.isEmpty else { return [] }

        let db = try getPublicDatabase()

        // Query for collections where:
        // - userId is in friendIds AND
        // - visibility is NOT private
        let friendIdStrings = friendIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility != %@",
            friendIdStrings,
            RecipeVisibility.privateRecipe.rawValue
        )
        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
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

            // Return shared collections (don't log routine operations)
            return collections
        } catch let error as CKError {
            // Handle schema not yet deployed - record type doesn't exist until first save
            if error.code == .unknownItem || error.errorCode == 11 { // 11 = unknown record type
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Query collections by owner and visibility (similar to querySharedRecipes)
    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        logger.info("🔍 Querying collections from \(ownerIds.count) owners with visibility: \(visibility.rawValue)")

        guard !ownerIds.isEmpty else { return [] }

        let db = try getPublicDatabase()

        // Build predicate for userId and visibility
        let ownerIdStrings = ownerIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility == %@",
            ownerIdStrings,
            visibility.rawValue
        )

        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
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
            // Handle schema not yet deployed - record type doesn't exist until first save
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

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted collection")
    }

    // MARK: - Collection References

    /// Save collection reference to PUBLIC database
    func saveCollectionReference(_ reference: CollectionReference) async throws {
        logger.info("💾 Saving collection reference: \(reference.collectionName)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: reference.id.uuidString)
        let record = CKRecord(recordType: collectionReferenceRecordType, recordID: recordID)

        // Core fields
        record["userId"] = reference.userId.uuidString as CKRecordValue
        record["originalCollectionId"] = reference.originalCollectionId.uuidString as CKRecordValue
        record["originalOwnerId"] = reference.originalOwnerId.uuidString as CKRecordValue
        record["savedAt"] = reference.savedAt as CKRecordValue

        // Cached metadata
        record["collectionName"] = reference.collectionName as CKRecordValue
        if let emoji = reference.collectionEmoji {
            record["collectionEmoji"] = emoji as CKRecordValue
        }
        record["recipeCount"] = reference.recipeCount as CKRecordValue

        // Staleness tracking
        record["lastValidatedAt"] = reference.lastValidatedAt as CKRecordValue
        record["cachedVisibility"] = reference.cachedVisibility as CKRecordValue

        _ = try await db.save(record)
        logger.info("✅ Saved collection reference to PUBLIC database")
    }

    /// Fetch user's saved collection references
    func fetchCollectionReferences(forUserId userId: UUID) async throws -> [CollectionReference] {
        logger.info("📥 Fetching collection references for user: \(userId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: collectionReferenceRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query)

            var references: [CollectionReference] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let reference = try? collectionReferenceFromRecord(record) {
                    references.append(reference)
                }
            }

            logger.info("✅ Fetched \(references.count) collection references")
            return references
        } catch let error as CKError {
            // Handle schema not yet deployed - record type doesn't exist until first save
            if error.code == .unknownItem || error.errorCode == 11 { // 11 = unknown record type
                logger.info("CollectionReference record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Delete a collection reference
    func deleteCollectionReference(_ referenceId: UUID) async throws {
        logger.info("🗑️ Deleting collection reference: \(referenceId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: referenceId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted collection reference")
    }

    // MARK: - Collection Cover Image Methods

    /// Upload collection cover image to CloudKit
    /// - Parameters:
    ///   - collectionId: The collection ID this image belongs to
    ///   - imageData: The image data to upload
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadCollectionCoverImage(collectionId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading collection cover image for collection: \(collectionId)")

        // Optimize image before upload
        let optimizedData = try await optimizeImageForCloudKit(imageData)

        // Create temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection_\(collectionId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create CKAsset
        let asset = CKAsset(fileURL: tempURL)

        // Get collection's CloudKit record
        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            // Fetch existing collection record
            let record = try await db.record(for: recordID)

            // Add cover image asset and modification timestamp
            record["coverImageAsset"] = asset
            record["coverImageModifiedAt"] = Date() as CKRecordValue

            // Save updated record
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
    /// - Parameter collectionId: The collection ID to download image for
    /// - Returns: The image data, or nil if no image exists
    func downloadCollectionCoverImage(collectionId: UUID) async throws -> Data? {
        logger.info("📥 Downloading collection cover image for collection: \(collectionId)")

        let db = try getPublicDatabase()
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
    /// - Parameter collectionId: The collection ID to delete image for
    func deleteCollectionCoverImage(collectionId: UUID) async throws {
        logger.info("🗑️ Deleting collection cover image for collection: \(collectionId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            // Remove cover image asset fields
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
    
    // MARK: - Private Helpers for Collections

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

    func collectionReferenceFromRecord(_ record: CKRecord) throws -> CollectionReference {
        guard let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let originalCollectionIdString = record["originalCollectionId"] as? String,
              let originalCollectionId = UUID(uuidString: originalCollectionIdString),
              let originalOwnerIdString = record["originalOwnerId"] as? String,
              let originalOwnerId = UUID(uuidString: originalOwnerIdString),
              let savedAt = record["savedAt"] as? Date,
              let collectionName = record["collectionName"] as? String,
              let recipeCount = record["recipeCount"] as? Int else {
            throw CloudKitError.invalidRecord
        }

        let collectionEmoji = record["collectionEmoji"] as? String
        // Optional fields with defaults for backward compatibility
        let lastValidatedAt = record["lastValidatedAt"] as? Date ?? savedAt
        let cachedVisibility = record["cachedVisibility"] as? String ?? "public"

        return CollectionReference(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            userId: userId,
            originalCollectionId: originalCollectionId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            collectionName: collectionName,
            collectionEmoji: collectionEmoji,
            recipeCount: recipeCount,
            lastValidatedAt: lastValidatedAt,
            cachedVisibility: cachedVisibility,
            cloudRecordName: record.recordID.recordName
        )
    }
}
