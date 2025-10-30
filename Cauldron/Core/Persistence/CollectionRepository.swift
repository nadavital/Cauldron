//
//  CollectionRepository.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftData
import os

/// Thread-safe repository for Collection operations
actor CollectionRepository {
    private let modelContainer: ModelContainer
    private let cloudKitService: CloudKitService
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionRepository")

    // Track collections pending sync
    private var pendingSyncCollections = Set<UUID>()
    private var syncRetryTask: Task<Void, Never>?

    init(modelContainer: ModelContainer, cloudKitService: CloudKitService) {
        self.modelContainer = modelContainer
        self.cloudKitService = cloudKitService

        // Start retry mechanism for failed syncs
        startSyncRetryTask()
    }

    // MARK: - Create

    /// Create a new collection
    func create(_ collection: Collection) async throws {
        let context = ModelContext(modelContainer)
        let model = try CollectionModel.from(collection)
        context.insert(model)
        try context.save()

        logger.info("✅ Created collection: \(collection.name)")

        // Sync to CloudKit PUBLIC database (for sharing)
        await syncCollectionToCloudKit(collection)
    }

    // MARK: - Read

    /// Fetch all collections for current user
    func fetchAll() async throws -> [Collection] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }

    /// Fetch a specific collection by ID
    func fetch(id: UUID) async throws -> Collection? {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<CollectionModel> { model in
            model.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let model = try context.fetch(descriptor).first else {
            return nil
        }

        return try model.toDomain()
    }

    /// Fetch collections containing a specific recipe
    func fetchCollections(containingRecipe recipeId: UUID) async throws -> [Collection] {
        let allCollections = try await fetchAll()
        return allCollections.filter { $0.contains(recipeId: recipeId) }
    }

    // MARK: - Update

    /// Update an existing collection
    func update(_ collection: Collection) async throws {
        let context = ModelContext(modelContainer)

        // Find existing model
        let predicate = #Predicate<CollectionModel> { model in
            model.id == collection.id
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let existingModel = try context.fetch(descriptor).first else {
            logger.error("❌ Cannot update - collection not found in database: \(collection.id)")
            throw CollectionRepositoryError.collectionNotFound
        }

        // Update the model
        let updatedModel = try CollectionModel.from(collection)

        logger.info("🔄 Updating collection '\(collection.name)' with \(collection.recipeCount) recipes")

        // Copy properties (SwiftData doesn't support direct replacement)
        existingModel.name = updatedModel.name
        existingModel.descriptionText = updatedModel.descriptionText
        existingModel.recipeIdsBlob = updatedModel.recipeIdsBlob
        existingModel.visibility = updatedModel.visibility
        existingModel.emoji = updatedModel.emoji
        existingModel.color = updatedModel.color
        existingModel.coverImageType = updatedModel.coverImageType
        existingModel.updatedAt = Date()

        try context.save()
        logger.info("✅ Updated collection in local database: \(collection.name)")

        // Verify the save by reading it back
        let verifyDescriptor = FetchDescriptor(predicate: predicate)
        if let verified = try context.fetch(verifyDescriptor).first {
            let verifiedCollection = try verified.toDomain()
            logger.info("✅ Verification: collection now has \(verifiedCollection.recipeCount) recipes")
        }

        // Sync to CloudKit
        await syncCollectionToCloudKit(collection)
    }

    /// Add a recipe to a collection
    func addRecipe(_ recipeId: UUID, to collectionId: UUID) async throws {
        guard let collection = try await fetch(id: collectionId) else {
            logger.error("❌ Collection not found: \(collectionId)")
            throw CollectionRepositoryError.collectionNotFound
        }

        logger.info("➕ Adding recipe \(recipeId) to collection '\(collection.name)'")
        logger.info("📊 Collection currently has \(collection.recipeCount) recipes: \(collection.recipeIds)")

        let updated = collection.addingRecipe(recipeId)
        logger.info("📊 After adding: collection will have \(updated.recipeCount) recipes: \(updated.recipeIds)")

        try await update(updated)
        logger.info("✅ Successfully added recipe to collection '\(collection.name)'")
    }

    /// Remove a recipe from a collection
    func removeRecipe(_ recipeId: UUID, from collectionId: UUID) async throws {
        guard let collection = try await fetch(id: collectionId) else {
            throw CollectionRepositoryError.collectionNotFound
        }

        let updated = collection.removingRecipe(recipeId)
        try await update(updated)
    }

    /// Remove a recipe from all collections (called when recipe is deleted)
    func removeRecipeFromAllCollections(_ recipeId: UUID) async throws {
        let collections = try await fetchCollections(containingRecipe: recipeId)

        for collection in collections {
            let updated = collection.removingRecipe(recipeId)
            try await update(updated)
        }

        logger.info("🗑️ Removed recipe from \(collections.count) collections")
    }

    // MARK: - Delete

    /// Delete a collection
    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)

        let predicate = #Predicate<CollectionModel> { model in
            model.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let model = try context.fetch(descriptor).first else {
            throw CollectionRepositoryError.collectionNotFound
        }

        context.delete(model)
        try context.save()

        logger.info("🗑️ Deleted collection locally")

        // Delete from CloudKit
        do {
            try await cloudKitService.deleteCollection(id)
            logger.info("✅ Deleted collection from CloudKit")
        } catch {
            logger.error("❌ Failed to delete collection from CloudKit: \(error.localizedDescription)")
        }
    }

    // MARK: - Search

    /// Search collections by name
    func search(query: String) async throws -> [Collection] {
        let allCollections = try await fetchAll()

        if query.isEmpty {
            return allCollections
        }

        return allCollections.filter { collection in
            collection.name.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - CloudKit Sync

    /// Sync collection to CloudKit PUBLIC database
    private func syncCollectionToCloudKit(_ collection: Collection) async {
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - collection will sync later: \(collection.name)")
            pendingSyncCollections.insert(collection.id)
            return
        }

        do {
            logger.info("Syncing collection to CloudKit: \(collection.name)")
            try await cloudKitService.saveCollection(collection)
            logger.info("✅ Successfully synced collection to CloudKit")

            // Remove from pending if it was there
            pendingSyncCollections.remove(collection.id)
        } catch {
            logger.error("❌ CloudKit sync failed for collection '\(collection.name)': \(error.localizedDescription)")
            pendingSyncCollections.insert(collection.id)
        }
    }

    /// Start background task to retry failed syncs
    private func startSyncRetryTask() {
        syncRetryTask?.cancel()
        syncRetryTask = Task {
            while !Task.isCancelled {
                // Wait 2 minutes between retry attempts
                try? await Task.sleep(nanoseconds: 120_000_000_000)

                guard !Task.isCancelled else { break }

                // Retry pending syncs
                await retryPendingSyncs()
            }
        }
    }

    /// Retry syncing collections that failed previously
    private func retryPendingSyncs() async {
        guard !self.pendingSyncCollections.isEmpty else { return }

        logger.info("Retrying sync for \(self.pendingSyncCollections.count) pending collections")

        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.info("CloudKit still not available - will retry later")
            return
        }

        let collectionsToRetry = Array(self.pendingSyncCollections)

        for collectionId in collectionsToRetry {
            guard !Task.isCancelled else { break }

            do {
                guard let collection = try await fetch(id: collectionId) else {
                    // Collection was deleted, remove from pending
                    self.pendingSyncCollections.remove(collectionId)
                    continue
                }

                try await cloudKitService.saveCollection(collection)
                self.pendingSyncCollections.remove(collectionId)
                logger.info("✅ Retry successful for collection: \(collection.name)")
            } catch {
                logger.error("❌ Retry failed for collection: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sync from CloudKit

    /// Fetch collections from CloudKit and sync to local database
    func syncFromCloudKit(userId: UUID) async throws {
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.info("CloudKit not available - skipping sync")
            return
        }

        do {
            let cloudCollections = try await cloudKitService.fetchCollections(forUserId: userId)
            logger.info("📥 Fetched \(cloudCollections.count) collections from CloudKit")

            // Merge with local collections
            for cloudCollection in cloudCollections {
                let localCollection = try await fetch(id: cloudCollection.id)

                if let local = localCollection {
                    // Update if cloud version is newer
                    if cloudCollection.updatedAt > local.updatedAt {
                        try await update(cloudCollection)
                        logger.info("🔄 Updated collection from cloud: \(cloudCollection.name)")
                    }
                } else {
                    // Insert new collection from cloud
                    try await create(cloudCollection)
                    logger.info("➕ Added new collection from cloud: \(cloudCollection.name)")
                }
            }
        } catch {
            logger.error("❌ Failed to sync collections from CloudKit: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: - Errors

enum CollectionRepositoryError: LocalizedError {
    case collectionNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .collectionNotFound:
            return "Collection not found"
        case .invalidData:
            return "Invalid collection data"
        }
    }
}
