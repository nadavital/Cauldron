//
//  CollectionRepository.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftData
import os

// MARK: - Collection Notification Names
extension Notification.Name {
    /// Posted when collection metadata (name, emoji, color, description, cover image) changes
    static let collectionMetadataChanged = Notification.Name("CollectionMetadataChanged")
    /// Posted when collection visibility changes
    static let collectionUpdated = Notification.Name("CollectionUpdated")
    /// Posted when recipes in a collection change
    static let collectionRecipesChanged = Notification.Name("CollectionRecipesChanged")
}

/// Thread-safe repository for Collection operations
actor CollectionRepository {
    private let modelContainer: ModelContainer
    private let cloudKitCore: CloudKitCore
    private let collectionCloudService: CollectionCloudService
    private let operationQueueService: OperationQueueService
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionRepository")

    // Track collections pending sync
    private var pendingSyncCollections = Set<UUID>()
    private var syncRetryTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        cloudKitCore: CloudKitCore,
        collectionCloudService: CollectionCloudService,
        operationQueueService: OperationQueueService
    ) {
        self.modelContainer = modelContainer
        self.cloudKitCore = cloudKitCore
        self.collectionCloudService = collectionCloudService
        self.operationQueueService = operationQueueService

        // Start retry mechanism for failed syncs
        startSyncRetryTask()

        // Listen for recipe visibility changes
        setupRecipeVisibilityObserver()
    }

    /// Setup observer for recipe visibility changes
    private func setupRecipeVisibilityObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RecipeVisibilityChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let recipeId = notification.userInfo?["recipeId"] as? UUID,
                  let oldVisibilityRaw = notification.userInfo?["oldVisibility"] as? String,
                  let newVisibilityRaw = notification.userInfo?["newVisibility"] as? String,
                  let oldVisibility = RecipeVisibility(rawValue: oldVisibilityRaw),
                  let newVisibility = RecipeVisibility(rawValue: newVisibilityRaw) else {
                return
            }

            Task {
                await self.handleRecipeVisibilityChange(
                    recipeId: recipeId,
                    oldVisibility: oldVisibility,
                    newVisibility: newVisibility
                )
            }
        }
    }

    // MARK: - Create

    /// Create a new collection (optimistic - returns immediately)
    func create(_ collection: Collection) async throws {
        // 1. Save locally (immediate)
        let context = ModelContext(modelContainer)
        let model = try CollectionModel.from(collection)
        context.insert(model)
        try context.save()

        // Created collection locally
        NotificationCenter.default.post(
            name: NSNotification.Name("CollectionAdded"),
            object: nil,
            userInfo: [
                "collectionId": collection.id,
                "collection": collection
            ]
        )

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .create,
            entityType: .collection,
            entityId: collection.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, collection] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: collection.id)

            // Sync to CloudKit PUBLIC database (for sharing)
            await self.syncCollectionToCloudKit(collection)

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: collection.id,
                entityType: .collection
            )
        }
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

    /// Update an existing collection (optimistic - returns immediately)
    /// - Parameters:
    ///   - collection: The collection to update
    ///   - shouldUpdateTimestamp: Whether to set updatedAt to current time. Default true for user edits, false for sync operations.
    func update(_ collection: Collection, shouldUpdateTimestamp: Bool = true) async throws {
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

        // Capture old state for change detection
        let oldVisibility = RecipeVisibility(rawValue: existingModel.visibility) ?? .publicRecipe
        let oldRecipeIds = (try? JSONDecoder().decode([UUID].self, from: existingModel.recipeIdsBlob)) ?? []
        let oldName = existingModel.name
        let oldEmoji = existingModel.emoji
        let oldSymbolName = existingModel.symbolName
        let oldColor = existingModel.color
        let oldDescription = existingModel.descriptionText
        let oldCoverImageType = existingModel.coverImageType

        // 1. Update locally (immediate)
        let updatedModel = try CollectionModel.from(collection)

        // Updating collection

        // Copy properties (SwiftData doesn't support direct replacement)
        existingModel.name = updatedModel.name
        existingModel.descriptionText = updatedModel.descriptionText
        existingModel.recipeIdsBlob = updatedModel.recipeIdsBlob
        existingModel.visibility = updatedModel.visibility
        existingModel.emoji = updatedModel.emoji
        existingModel.symbolName = updatedModel.symbolName
        existingModel.color = updatedModel.color
        existingModel.coverImageType = updatedModel.coverImageType
        // Only update timestamp for user actions, not sync operations
        existingModel.updatedAt = shouldUpdateTimestamp ? Date() : collection.updatedAt

        try context.save()
        // Updated collection in local database

        // Verify the save by reading it back
        let verifyDescriptor = FetchDescriptor(predicate: predicate)
        if let verified = try context.fetch(verifyDescriptor).first {
            let verifiedCollection = try verified.toDomain()
            // Verification: collection updated successfully
        }

        // Post notifications for changes (immediate)
        if oldVisibility != collection.visibility {
            NotificationCenter.default.post(
                name: NSNotification.Name("CollectionUpdated"),
                object: nil,
                userInfo: [
                    "collectionId": collection.id,
                    "changeType": "visibility"
                ]
            )
        }

        if oldRecipeIds != collection.recipeIds {
            NotificationCenter.default.post(
                name: NSNotification.Name("CollectionRecipesChanged"),
                object: nil,
                userInfo: [
                    "collectionId": collection.id,
                    "recipeIds": collection.recipeIds
                ]
            )
        }

        // Post notification for metadata changes (name, emoji, color, description, cover image)
        let metadataChanged = oldName != collection.name ||
                              oldEmoji != collection.emoji ||
                              oldSymbolName != collection.symbolName ||
                              oldColor != collection.color ||
                              oldDescription != collection.description ||
                              oldCoverImageType != collection.coverImageType.rawValue
        if metadataChanged {
            NotificationCenter.default.post(
                name: .collectionMetadataChanged,
                object: nil,
                userInfo: [
                    "collectionId": collection.id,
                    "collection": collection
                ]
            )
        }

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, collection] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: collection.id)

            // Sync to CloudKit
            await self.syncCollectionToCloudKit(collection)

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: collection.id,
                entityType: .collection
            )
        }
    }

    /// Add a recipe to a collection
    func addRecipe(_ recipeId: UUID, to collectionId: UUID) async throws {
        guard let collection = try await fetch(id: collectionId) else {
            logger.error("❌ Collection not found: \(collectionId)")
            throw CollectionRepositoryError.collectionNotFound
        }

        // Adding recipe to collection
        let updated = collection.addingRecipe(recipeId)

        try await update(updated)
        // Successfully added recipe to collection
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

        // Removed recipe from collections
    }

    // MARK: - Delete

    /// Delete a collection (optimistic - returns immediately)
    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)

        let predicate = #Predicate<CollectionModel> { model in
            model.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let model = try context.fetch(descriptor).first else {
            throw CollectionRepositoryError.collectionNotFound
        }

        // 1. Delete locally (immediate)
        context.delete(model)
        try context.save()

        // Deleted collection locally

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .delete,
            entityType: .collection,
            entityId: id
        )

        // 3. Trigger CloudKit deletion in background (non-blocking)
        Task.detached { [weak self, id, collectionCloudService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: id)

            // Delete from CloudKit
            do {
                try await collectionCloudService.deleteCollection(id)
                // Deleted collection from CloudKit

                // Mark operation as completed
                await self.operationQueueService.markCompleted(
                    entityId: id,
                    entityType: .collection
                )
            } catch {
                self.logger.error("❌ Failed to delete collection from CloudKit: \(error.localizedDescription)")

                // Mark operation as failed
                await self.operationQueueService.markFailed(
                    operationId: id,
                    error: error.localizedDescription
                )
            }
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
        // Attempting to sync collection to CloudKit
        let isAvailable = await cloudKitCore.isAvailable()

        guard isAvailable else {
            logger.warning("⚠️ CloudKit not available - collection will sync later: \(collection.name)")
            pendingSyncCollections.insert(collection.id)
            return
        }

        do {
            // Always sync the freshest local state to reduce stale change-tag conflicts.
            let collectionToSync = (try? await fetch(id: collection.id)) ?? collection

            // Syncing collection to CloudKit
            try await collectionCloudService.saveCollection(collectionToSync)
            // Successfully synced collection to CloudKit

            // Remove from pending if it was there
            pendingSyncCollections.remove(collectionToSync.id)
        } catch {
            logger.error("❌ CloudKit sync failed for collection '\(collection.name)': \(error.localizedDescription)")
            logger.error("❌ Error details: \(error)")
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

        // Retrying sync for pending collections
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            // CloudKit still not available - will retry later
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

                try await collectionCloudService.saveCollection(collection)
                self.pendingSyncCollections.remove(collectionId)
                // Retry successful for collection
            } catch {
                logger.error("❌ Retry failed for collection: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Recipe Visibility Change Handling

    /// Handle recipe visibility changes and update affected collections
    /// This ensures collections stay in sync when recipes change visibility
    func handleRecipeVisibilityChange(recipeId: UUID, oldVisibility: RecipeVisibility, newVisibility: RecipeVisibility) async {
        // Handling visibility change for recipe

        do {
            // Find all collections containing this recipe
            let affectedCollections = try await fetchCollections(containingRecipe: recipeId)

            guard !affectedCollections.isEmpty else {
                // No collections affected by recipe visibility change
                return
            }

            // Found collections containing this recipe

            // Update each affected collection's timestamp to trigger CloudKit sync
            // This ensures that anyone with a reference to this collection will see the update
            for collection in affectedCollections {
                // Create updated collection with new timestamp
                let updated = collection.updated(
                    name: collection.name,
                    description: collection.description,
                    recipeIds: collection.recipeIds,
                    emoji: collection.emoji,
                    color: collection.color
                )

                try await update(updated)
                // Updated collection due to recipe visibility change
            }
        } catch {
            logger.error("❌ Failed to handle recipe visibility change: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync from CloudKit

    /// Fetch collections from CloudKit and sync to local database
    func syncFromCloudKit(userId: UUID) async throws {
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            // CloudKit not available - skipping sync
            return
        }

        do {
            let cloudCollections = try await collectionCloudService.fetchCollections(forUserId: userId)
            // Fetched collections from CloudKit

            // Merge with local collections
            for cloudCollection in cloudCollections {
                let localCollection = try await fetch(id: cloudCollection.id)

                if let local = localCollection {
                    // Update if cloud version is newer (don't update timestamp - sync operation)
                    if cloudCollection.updatedAt > local.updatedAt {
                        try await update(cloudCollection, shouldUpdateTimestamp: false)
                        // Updated collection from cloud
                    }
                } else {
                    // Insert new collection from cloud
                    try await create(cloudCollection)
                    // Added new collection from cloud
                }
            }
        } catch {
            logger.error("❌ Failed to sync collections from CloudKit: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Account Deletion

    /// Delete all collections owned by a user (for account deletion)
    /// - Parameter userId: The ID of the user whose collections to delete
    func deleteAllUserCollections(userId: UUID) async throws {
        // Deleting all collections for user

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { model in
                model.userId == userId
            }
        )

        let models = try context.fetch(descriptor)
        // Found collections to delete

        // Delete each collection (includes CloudKit cleanup)
        for model in models {
            try await delete(id: model.id)
        }

        // Deleted all user collections
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
