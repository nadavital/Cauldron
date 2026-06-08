//
//  CollectionRepository.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import CloudKit
import SwiftData
import os

// MARK: - Collection Notification Names
extension Notification.Name {
    /// Posted when collection metadata (name, emoji, color, description, cover image) changes
    nonisolated static let collectionMetadataChanged = Notification.Name("CollectionMetadataChanged")
    /// Posted when collection visibility changes
    nonisolated static let collectionUpdated = Notification.Name("CollectionUpdated")
    /// Posted when recipes in a collection change
    nonisolated static let collectionRecipesChanged = Notification.Name("CollectionRecipesChanged")
    /// Posted when a collection is deleted locally or suppressed by a remote tombstone
    nonisolated static let collectionDeleted = Notification.Name("CollectionDeleted")
}

nonisolated enum CollectionDeletionSyncPolicy {
    static func canDeleteActiveRecord(tombstoneSaveError: Error?) -> Bool {
        tombstoneSaveError == nil
    }
}

nonisolated enum CollectionDeleteReplayPolicy {
    static func tombstoneForReplay(
        localTombstone: DeletedCollectionTombstone?,
        payloadData: Data?,
        defaultDeletedAt: Date
    ) -> DeletedCollectionTombstone? {
        if let localTombstone {
            return localTombstone
        }

        guard let payloadData,
              let payload = try? JSONDecoder().decode(CollectionRepository.CollectionDeletePayload.self, from: payloadData) else {
            return nil
        }

        return DeletedCollectionTombstone(
            collectionId: payload.collectionId,
            ownerId: payload.ownerId,
            deletedAt: defaultDeletedAt,
            cloudRecordName: nil,
            sourceDeviceId: SyncDeviceIdentifier.current()
        )
    }

    static func tombstoneForSuppressedActiveRecord(
        localTombstone: DeletedCollectionTombstone?,
        remoteTombstone: DeletedCollectionTombstone?
    ) -> DeletedCollectionTombstone? {
        remoteTombstone ?? localTombstone
    }
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
    private var operationQueueReplayTask: Task<Void, Never>?

    struct CollectionDeletePayload: Codable, Sendable {
        let collectionId: UUID
        let ownerId: UUID
    }

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

        if !RuntimeEnvironment.isRunningTests {
            setupRecipeVisibilityObserver()
        }

        if !RuntimeEnvironment.isRunningTests && !RuntimeEnvironment.isSimulatorQAMode {
            // Start retry mechanism for failed syncs after actor initialization completes
            Task {
                await self.startSyncRetryTask()
                await self.startOperationQueueReplayTask()
            }
        }
    }

    private func canModify(_ collection: Collection) async -> Bool {
        if RuntimeEnvironment.isRunningTests {
            let currentUserId = await MainActor.run { CurrentUserSession.shared.userId }
            return currentUserId.map { collection.userId == $0 } ?? true
        }

        guard let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            return false
        }

        return collection.userId == currentUserId
    }

    private func assertCanModify(_ collection: Collection) async throws {
        guard await canModify(collection) else {
            logger.warning("Blocked mutation of non-owned collection: \(collection.id)")
            throw CollectionRepositoryError.notAuthorized
        }
    }

    /// Setup observer for recipe visibility changes
    nonisolated private func setupRecipeVisibilityObserver() {
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
        try await assertCanModify(collection)

        // 1. Save locally (immediate)
        let context = ModelContext(modelContainer)
        let model = try CollectionModel.from(collection)
        context.insert(model)
        try upsertLocalMembershipEdges(
            activeRecipeIds: collection.recipeIds,
            removedRecipeIds: [],
            collectionId: collection.id,
            ownerId: collection.userId,
            baseSortOrder: 0,
            context: context
        )
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

        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

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
            let membershipSynced = await self.syncPendingMembershipEdgesToCloudKit(collectionId: collection.id)
            let metadataPending = await self.isPendingSync(collectionId: collection.id)

            if metadataPending || !membershipSynced {
                await self.operationQueueService.markFailed(
                    operationId: collection.id,
                    error: "Collection create sync incomplete"
                )
            } else {
                // Mark operation as completed
                await self.operationQueueService.markCompleted(
                    entityId: collection.id,
                    entityType: .collection
                )
            }
        }
    }

    // MARK: - Read

    /// Fetch all local collections, regardless of owner. Prefer
    /// `fetchUserCollections(ownerId:visibility:)` for user-facing surfaces.
    func fetchAll() async throws -> [Collection] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try applyMembershipOverlay(to: models.map { try $0.toDomain() }, context: context)
    }

    /// Fetch collections for a specific visibility without loading the full table first.
    func fetchAll(visibility: RecipeVisibility) async throws -> [Collection] {
        let context = ModelContext(modelContainer)
        let visibilityRaw = visibility.rawValue
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { $0.visibility == visibilityRaw },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try applyMembershipOverlay(to: models.map { try $0.toDomain() }, context: context)
    }

    /// Fetch collections owned by a specific user. UI/library surfaces should use
    /// this instead of raw `fetchAll()` when showing the current user's data.
    func fetchUserCollections(
        ownerId: UUID?,
        visibility: RecipeVisibility? = nil
    ) async throws -> [Collection] {
        guard let ownerId else { return [] }

        let context = ModelContext(modelContainer)
        let descriptor: FetchDescriptor<CollectionModel>
        if let visibility {
            let visibilityRaw = visibility.rawValue
            descriptor = FetchDescriptor<CollectionModel>(
                predicate: #Predicate { model in
                    model.userId == ownerId && model.visibility == visibilityRaw
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<CollectionModel>(
                predicate: #Predicate { model in
                    model.userId == ownerId
                },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        }

        let models = try context.fetch(descriptor)
        return try applyMembershipOverlay(to: models.map { try $0.toDomain() }, context: context)
    }

    func fetchSavedCollectionCopy(ownerId: UUID, sourceCollectionId: UUID) async throws -> Collection? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { model in
                model.userId == ownerId && model.originalCollectionId == sourceCollectionId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try applyMembershipOverlay(to: models.map { try $0.toDomain() }, context: context).first
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

        return try applyMembershipOverlay(to: [model.toDomain()], context: context).first
    }

    /// Fetch collections containing a specific recipe
    func fetchCollections(containingRecipe recipeId: UUID) async throws -> [Collection] {
        let allCollections = try await fetchAll()
        return allCollections.filter { $0.contains(recipeId: recipeId) }
    }

    func publicCollectionsContainingRecipe(recipeId: UUID, ownerId: UUID) async throws -> [Collection] {
        let collections = try await fetchCollections(containingRecipe: recipeId)
        return collections.filter { collection in
            collection.userId == ownerId && collection.visibility == .publicRecipe
        }
    }

    // MARK: - Update

    /// Update an existing collection (optimistic - returns immediately)
    /// - Parameters:
    ///   - collection: The collection to update
    ///   - shouldUpdateTimestamp: Whether to set updatedAt to current time. Default true for user edits, false for sync operations.
    func update(
        _ collection: Collection,
        shouldUpdateTimestamp: Bool = true,
        updateMembershipEdges: Bool = true,
        queueCloudSync: Bool = true
    ) async throws {
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

        // Capture old state for change detection. Use membership-overlaid recipe IDs
        // because the legacy recipeIds blob may be stale after multi-device sync.
        let oldCollection = try applyMembershipOverlay(
            to: [existingModel.toDomain()],
            context: context
        ).first ?? existingModel.toDomain()
        let oldVisibility = RecipeVisibility(rawValue: existingModel.visibility) ?? .publicRecipe
        let oldRecipeIds = oldCollection.recipeIds
        let oldName = existingModel.name
        let oldEmoji = existingModel.emoji
        let oldSymbolName = existingModel.symbolName
        let oldColor = existingModel.color
        let oldDescription = existingModel.descriptionText
        let oldCoverImageType = existingModel.coverImageType
        let oldCoverImagePath = existingModel.coverImagePath
        let oldCloudCoverImageRecordName = existingModel.cloudCoverImageRecordName
        let oldCoverImageModifiedAt = existingModel.coverImageModifiedAt
        try await assertCanModify(oldCollection)

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
        existingModel.coverImagePath = updatedModel.coverImagePath
        existingModel.cloudCoverImageRecordName = updatedModel.cloudCoverImageRecordName
        existingModel.coverImageModifiedAt = updatedModel.coverImageModifiedAt
        existingModel.originalCollectionId = updatedModel.originalCollectionId
        existingModel.originalCollectionOwnerId = updatedModel.originalCollectionOwnerId
        existingModel.originalCollectionName = updatedModel.originalCollectionName
        existingModel.savedAt = updatedModel.savedAt
        existingModel.sourceCollectionUpdatedAt = updatedModel.sourceCollectionUpdatedAt
        existingModel.followsSourceUpdates = updatedModel.followsSourceUpdates
        // Only update timestamp for user actions, not sync operations
        existingModel.updatedAt = shouldUpdateTimestamp ? Date() : collection.updatedAt

        if updateMembershipEdges {
            let removedRecipeIds = oldRecipeIds.filter { !collection.recipeIds.contains($0) }
            try upsertLocalMembershipEdges(
                activeRecipeIds: collection.recipeIds,
                removedRecipeIds: removedRecipeIds,
                collectionId: collection.id,
                ownerId: collection.userId,
                baseSortOrder: 0,
                context: context
            )
        }

        try context.save()
        // Updated collection in local database

        // Verify the save by reading it back
        let verifyDescriptor = FetchDescriptor(predicate: predicate)
        if let verified = try context.fetch(verifyDescriptor).first {
            _ = try verified.toDomain()
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

        if updateMembershipEdges && oldRecipeIds != collection.recipeIds {
            NotificationCenter.default.post(
                name: NSNotification.Name("CollectionRecipesChanged"),
                object: nil,
                userInfo: [
                    "collectionId": collection.id,
                    "recipeIds": collection.recipeIds,
                    "collection": collection
                ]
            )
        }

        // Post notification for metadata changes (name, emoji, color, description, cover image)
        let metadataChanged = oldName != collection.name ||
                              oldEmoji != collection.emoji ||
                              oldSymbolName != collection.symbolName ||
                              oldColor != collection.color ||
                              oldDescription != collection.description ||
                              oldCoverImageType != collection.coverImageType.rawValue ||
                              oldCoverImagePath != collection.coverImageURL?.absoluteString ||
                              oldCloudCoverImageRecordName != collection.cloudCoverImageRecordName ||
                              oldCoverImageModifiedAt != collection.coverImageModifiedAt
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

        guard queueCloudSync, !RuntimeEnvironment.isRunningTests else {
            return
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
            let membershipSynced = await self.syncPendingMembershipEdgesToCloudKit(collectionId: collection.id)
            let metadataPending = await self.isPendingSync(collectionId: collection.id)

            if metadataPending || !membershipSynced {
                await self.operationQueueService.markFailed(
                    operationId: collection.id,
                    error: "Collection update sync incomplete"
                )
            } else {
                // Mark operation as completed
                await self.operationQueueService.markCompleted(
                    entityId: collection.id,
                    entityType: .collection
                )
            }
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
        try await removeRecipesFromAllCollections([recipeId])
    }

    @discardableResult
    func removeRecipeFromOwnedPublicCollections(recipeId: UUID, ownerId: UUID) async throws -> [Collection] {
        let collections = try await publicCollectionsContainingRecipe(recipeId: recipeId, ownerId: ownerId)
        for collection in collections {
            let updated = collection.removingRecipe(recipeId)
            try await update(updated)
        }
        return collections
    }

    /// Remove recipes from all collections in one pass. This is used after
    /// tombstone sync so deletion wins over stale collection membership edges.
    func removeRecipesFromAllCollections(_ recipeIds: Set<UUID>) async throws {
        guard !recipeIds.isEmpty else { return }

        let collections = try await fetchAll()
        for collection in collections {
            guard await canModify(collection) else {
                logger.info("Skipping deleted recipe cleanup for non-owned collection: \(collection.id)")
                continue
            }

            let filteredRecipeIds = collection.recipeIds.filter { !recipeIds.contains($0) }
            guard filteredRecipeIds.count != collection.recipeIds.count else { continue }

            let updated = collectionWithRecipeIds(collection, filteredRecipeIds)
            try await update(updated)
        }

        // Removed recipes from collections
    }

    @discardableResult
    func repairInvalidPublicCollectionMemberships(
        recipeRepository: RecipeRepository,
        ownerId: UUID
    ) async throws -> Int {
        let publicCollections = try await fetchAll().filter { collection in
            collection.userId == ownerId && collection.visibility == .publicRecipe
        }
        guard !publicCollections.isEmpty else { return 0 }

        let recipeIds = Array(Set(publicCollections.flatMap(\.recipeIds)))
        guard !recipeIds.isEmpty else { return 0 }

        let recipesById = RecipeDeduplication.byIdPreferringBest(
            try await recipeRepository.fetch(ids: recipeIds)
        )

        var repairedCount = 0
        for collection in publicCollections {
            let validRecipeIds = collection.recipeIds.filter { recipeId in
                guard let recipe = recipesById[recipeId] else {
                    return true
                }
                return recipe.visibility == .publicRecipe
            }

            guard validRecipeIds != collection.recipeIds else { continue }
            try await update(collectionWithRecipeIds(collection, validRecipeIds))
            repairedCount += 1
        }

        if repairedCount > 0 {
            logger.info("Repaired \(repairedCount) public collections with private recipe memberships")
        }
        return repairedCount
    }

    private func applyMembershipOverlay(
        to collections: [Collection],
        context: ModelContext
    ) throws -> [Collection] {
        guard !collections.isEmpty else { return [] }

        let membershipModels = try context.fetch(FetchDescriptor<CollectionMembershipModel>())
        guard !membershipModels.isEmpty else { return collections }

        let edgesByCollection = Dictionary(grouping: membershipModels.map { $0.toDomain() }, by: \.collectionId)

        return collections.map { collection in
            guard let edges = edgesByCollection[collection.id], !edges.isEmpty else {
                return collection
            }

            return CollectionMembershipProjection.collectionWithRecipeIds(
                collection,
                CollectionMembershipProjection.activeRecipeIds(from: edges)
            )
        }
    }

    private func collectionWithRecipeIds(_ collection: Collection, _ recipeIds: [UUID]) -> Collection {
        CollectionMembershipProjection.collectionWithRecipeIds(collection, recipeIds)
    }

    private func upsertLocalMembershipEdges(
        activeRecipeIds: [UUID],
        removedRecipeIds: [UUID],
        collectionId: UUID,
        ownerId: UUID,
        baseSortOrder: Int,
        context: ModelContext
    ) throws {
        for (offset, recipeId) in activeRecipeIds.enumerated() {
            let edge = CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: recipeId,
                ownerId: ownerId,
                status: .active,
                sortOrder: baseSortOrder + offset,
                sourceDeviceId: SyncDeviceIdentifier.current()
            )
            try upsertLocalMembershipEdge(edge, context: context)
        }

        for recipeId in removedRecipeIds {
            let edge = CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: recipeId,
                ownerId: ownerId,
                status: .removed,
                sortOrder: baseSortOrder,
                sourceDeviceId: SyncDeviceIdentifier.current()
            )
            try upsertLocalMembershipEdge(edge, context: context)
        }
    }

    private func upsertLocalMembershipEdge(
        _ edge: CollectionMembershipEdge,
        context: ModelContext
    ) throws {
        let collectionId = edge.collectionId
        let recipeId = edge.recipeId
        let descriptor = FetchDescriptor<CollectionMembershipModel>(
            predicate: #Predicate { model in
                model.collectionId == collectionId && model.recipeId == recipeId
            }
        )

        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= edge.updatedAt else { return }
            existing.ownerId = edge.ownerId
            existing.status = edge.status.rawValue
            existing.updatedAt = edge.updatedAt
            existing.sortOrder = edge.sortOrder
            existing.sourceDeviceId = edge.sourceDeviceId
            existing.schemaVersion = edge.schemaVersion
        } else {
            context.insert(CollectionMembershipModel.from(edge))
        }
    }

    private func removedMembershipEdges(
        for collection: Collection,
        deletedAt: Date
    ) -> [CollectionMembershipEdge] {
        collection.recipeIds.enumerated().map { offset, recipeId in
            CollectionMembershipEdge(
                collectionId: collection.id,
                recipeId: recipeId,
                ownerId: collection.userId,
                status: .removed,
                updatedAt: deletedAt,
                sortOrder: offset,
                sourceDeviceId: SyncDeviceIdentifier.current()
            )
        }
    }

    private func localMembershipEdges(collectionId: UUID) throws -> [CollectionMembershipEdge] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionMembershipModel>(
            predicate: #Predicate { $0.collectionId == collectionId }
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    private func upsertLocalDeletedCollectionTombstone(
        _ tombstone: DeletedCollectionTombstone,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<DeletedCollectionModel>()
        let existing = try context.fetch(descriptor).first { $0.collectionId == tombstone.collectionId }

        if let existing {
            guard existing.deletedAt == nil || existing.deletedAt! <= tombstone.deletedAt else {
                return
            }
            existing.ownerId = tombstone.ownerId
            existing.deletedAt = tombstone.deletedAt
            existing.cloudRecordName = existing.cloudRecordName ?? tombstone.cloudRecordName
            existing.sourceDeviceId = existing.sourceDeviceId ?? tombstone.sourceDeviceId
            existing.schemaVersion = max(existing.schemaVersion, tombstone.schemaVersion)
        } else {
            context.insert(
                DeletedCollectionModel(
                    collectionId: tombstone.collectionId,
                    ownerId: tombstone.ownerId,
                    deletedAt: tombstone.deletedAt,
                    cloudRecordName: tombstone.cloudRecordName,
                    sourceDeviceId: tombstone.sourceDeviceId,
                    schemaVersion: tombstone.schemaVersion
                )
            )
        }
    }

    private func localDeletedCollectionTombstone(collectionId: UUID) throws -> DeletedCollectionTombstone? {
        let context = ModelContext(modelContainer)
        return try localDeletedCollectionTombstones(context: context)
            .first { $0.collectionId == collectionId }
    }

    private func localDeletedCollectionTombstones(context: ModelContext) throws -> [DeletedCollectionTombstone] {
        let descriptor = FetchDescriptor<DeletedCollectionModel>()
        return try context.fetch(descriptor).compactMap { model in
            guard let collectionId = model.collectionId,
                  let ownerId = model.ownerId,
                  let deletedAt = model.deletedAt else {
                return nil
            }

            return DeletedCollectionTombstone(
                collectionId: collectionId,
                ownerId: ownerId,
                deletedAt: deletedAt,
                cloudRecordName: model.cloudRecordName,
                sourceDeviceId: model.sourceDeviceId,
                schemaVersion: model.schemaVersion
            )
        }
    }

    private func removeLocalCollectionSuppressedByTombstone(
        _ tombstone: DeletedCollectionTombstone,
        context: ModelContext
    ) throws {
        let collectionId = tombstone.collectionId
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { $0.id == collectionId }
        )

        guard let model = try context.fetch(descriptor).first else { return }

        let collection = try applyMembershipOverlay(
            to: [model.toDomain()],
            context: context
        ).first ?? model.toDomain()

        for edge in removedMembershipEdges(for: collection, deletedAt: tombstone.deletedAt) {
            try upsertLocalMembershipEdge(edge, context: context)
        }

        context.delete(model)
        try context.save()
        NotificationCenter.default.post(
            name: .collectionDeleted,
            object: collectionId,
            userInfo: ["collectionId": collectionId]
        )
    }

    private func insertSyncedCollection(
        _ collection: Collection,
        seedMembershipEdges: Bool
    ) async throws {
        let context = ModelContext(modelContainer)
        let model = try CollectionModel.from(collection)
        context.insert(model)

        if seedMembershipEdges {
            try upsertLocalMembershipEdges(
                activeRecipeIds: collection.recipeIds,
                removedRecipeIds: [],
                collectionId: collection.id,
                ownerId: collection.userId,
                baseSortOrder: 0,
                context: context
            )
        }

        try context.save()
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

        let collection = try applyMembershipOverlay(
            to: [model.toDomain()],
            context: context
        ).first ?? model.toDomain()
        try await assertCanModify(collection)
        let deletedAt = Date()
        let tombstone = DeletedCollectionTombstone(
            collectionId: collection.id,
            ownerId: collection.userId,
            deletedAt: deletedAt,
            cloudRecordName: collection.cloudRecordName,
            sourceDeviceId: SyncDeviceIdentifier.current()
        )
        let removedMembershipEdges = removedMembershipEdges(for: collection, deletedAt: deletedAt)

        try upsertLocalDeletedCollectionTombstone(tombstone, context: context)
        for edge in removedMembershipEdges {
            try upsertLocalMembershipEdge(edge, context: context)
        }

        // 1. Delete locally (immediate)
        context.delete(model)
        try context.save()

        // Deleted collection locally
        NotificationCenter.default.post(
            name: .collectionDeleted,
            object: id,
            userInfo: ["collectionId": id]
        )

        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .delete,
            entityType: .collection,
            entityId: id,
            payload: try? JSONEncoder().encode(CollectionDeletePayload(
                collectionId: id,
                ownerId: collection.userId
            ))
        )

        // 3. Trigger CloudKit deletion in background (non-blocking)
        Task.detached { [weak self, id, tombstone, removedMembershipEdges] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: id)

            // Delete from CloudKit
            do {
                try await self.syncCollectionDeletionToCloudKit(
                    tombstone: tombstone,
                    removedMembershipEdges: removedMembershipEdges
                )
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

    private func deleteLocalMembershipEdges(collectionId: UUID, context: ModelContext) throws {
        let descriptor = FetchDescriptor<CollectionMembershipModel>(
            predicate: #Predicate { $0.collectionId == collectionId }
        )
        for model in try context.fetch(descriptor) {
            context.delete(model)
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
            if let tombstone = try localDeletedCollectionTombstone(collectionId: collection.id) {
                let removedEdges = try localMembershipEdges(collectionId: collection.id)
                try await syncCollectionDeletionToCloudKit(
                    tombstone: tombstone,
                    removedMembershipEdges: removedEdges
                )
                pendingSyncCollections.remove(collection.id)
                return
            }

            // Always sync the freshest local state to reduce stale change-tag conflicts.
            guard let collectionToSync = try await fetch(id: collection.id) else {
                pendingSyncCollections.remove(collection.id)
                return
            }

            // Syncing collection to CloudKit
            try await collectionCloudService.saveCollection(collectionToSync)
            try await syncCoverImageIfNeeded(for: collectionToSync)
            // Successfully synced collection to CloudKit

            // Remove from pending if it was there
            pendingSyncCollections.remove(collectionToSync.id)
        } catch {
            logger.error("❌ CloudKit sync failed for collection '\(collection.name)': \(error.localizedDescription)")
            logger.error("❌ Error details: \(error)")
            pendingSyncCollections.insert(collection.id)
        }
    }

    private func syncCoverImageIfNeeded(for collection: Collection) async throws {
        guard collection.coverImageType == .customImage,
              let coverImageURL = collection.coverImageURL else {
            return
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: coverImageURL.path)
        let localModifiedAt = attributes?[.modificationDate] as? Date

        guard collection.needsCoverImageUpload(localImageModified: localModifiedAt) else {
            return
        }

        let imageData = try Data(contentsOf: coverImageURL)
        let uploadedRecordName = try await collectionCloudService.uploadCollectionCoverImage(
            collectionId: collection.id,
            imageData: imageData
        )
        try await markCoverImageUploaded(
            collectionId: collection.id,
            recordName: uploadedRecordName,
            modifiedAt: Date()
        )
    }

    private func markCoverImageUploaded(
        collectionId: UUID,
        recordName: String,
        modifiedAt: Date
    ) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { model in
                model.id == collectionId
            }
        )

        guard let model = try context.fetch(descriptor).first else {
            return
        }

        model.cloudCoverImageRecordName = recordName
        model.coverImageModifiedAt = modifiedAt
        try context.save()
    }

    private func syncPendingMembershipEdgesToCloudKit(collectionId: UUID) async -> Bool {
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else { return false }

        do {
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate { $0.collectionId == collectionId }
            )
            let edges = try context.fetch(descriptor).map { $0.toDomain() }
            try await collectionCloudService.saveMembershipEdges(edges)
            return true
        } catch {
            logger.warning("Failed to sync collection membership edges: \(error.localizedDescription)")
            return false
        }
    }

    private func syncCollectionDeletionToCloudKit(
        tombstone: DeletedCollectionTombstone,
        removedMembershipEdges: [CollectionMembershipEdge]
    ) async throws {
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            throw CloudKitError.accountNotAvailable(.couldNotDetermine)
        }

        do {
            try await collectionCloudService.saveDeletedCollectionTombstone(tombstone)
        } catch {
            logger.error("Failed to save collection tombstone before active-record delete: \(error.localizedDescription)")
            if !CollectionDeletionSyncPolicy.canDeleteActiveRecord(tombstoneSaveError: error) {
                throw error
            }
        }

        var deferredError: Error?
        do {
            try await collectionCloudService.saveMembershipEdges(removedMembershipEdges)
        } catch {
            logger.error("Failed to save removed collection membership edges before active-record delete: \(error.localizedDescription)")
            if deferredError == nil, !isMissingCloudKitSchemaError(error) {
                deferredError = error
            }
        }

        try await collectionCloudService.deleteCollection(tombstone.collectionId)

        if let deferredError {
            throw deferredError
        }
    }

    private func isMissingCloudKitSchemaError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        return ckError.code == .unknownItem || ckError.errorCode == 11 || ckError.code == .invalidArguments
    }

    private func isPendingSync(collectionId: UUID) -> Bool {
        pendingSyncCollections.contains(collectionId)
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

    private func startOperationQueueReplayTask() {
        operationQueueReplayTask?.cancel()
        operationQueueReplayTask = Task {
            await replayReadyCollectionOperations()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await replayReadyCollectionOperations()
            }
        }
    }

    private func replayReadyCollectionOperations() async {
        let operations = await operationQueueService.getAllOperations()
            .filter { operation in
                operation.entityType == .collection &&
                (operation.status == .pending || operation.isReadyForRetry)
            }

        guard !operations.isEmpty else { return }

        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.info("CloudKit still not available - collection operation replay will retry later")
            return
        }

        for operation in operations {
            guard !Task.isCancelled else { break }
            await replayCollectionOperation(operation)
        }
    }

    private func replayCollectionOperation(_ operation: SyncOperation) async {
        await operationQueueService.markInProgress(operationId: operation.id)

        switch operation.type {
        case .create, .update:
            do {
                guard let collection = try await fetch(id: operation.entityId) else {
                    if let tombstone = try localDeletedCollectionTombstone(collectionId: operation.entityId) {
                        let removedEdges = try localMembershipEdges(collectionId: operation.entityId)
                        try await syncCollectionDeletionToCloudKit(
                            tombstone: tombstone,
                            removedMembershipEdges: removedEdges
                        )
                    }
                    await operationQueueService.markCompleted(entityId: operation.entityId, entityType: .collection)
                    return
                }

                await syncCollectionToCloudKit(collection)
                let membershipSynced = await syncPendingMembershipEdgesToCloudKit(collectionId: collection.id)
                if pendingSyncCollections.contains(operation.entityId) || !membershipSynced {
                    await operationQueueService.markFailed(
                        operationId: operation.id,
                        error: "Collection replay sync incomplete"
                    )
                } else {
                    await operationQueueService.markCompleted(entityId: operation.entityId, entityType: .collection)
                }
            } catch {
                await operationQueueService.markFailed(
                    operationId: operation.id,
                    error: "Collection replay failed: \(error.localizedDescription)"
                )
            }

        case .delete:
            do {
                let tombstone = CollectionDeleteReplayPolicy.tombstoneForReplay(
                    localTombstone: try localDeletedCollectionTombstone(collectionId: operation.entityId),
                    payloadData: operation.payload,
                    defaultDeletedAt: Date()
                )
                guard let tombstone else {
                    throw CollectionRepositoryError.invalidData
                }

                let removedEdges = try localMembershipEdges(collectionId: operation.entityId)
                try await syncCollectionDeletionToCloudKit(
                    tombstone: tombstone,
                    removedMembershipEdges: removedEdges
                )
                await operationQueueService.markCompleted(entityId: operation.entityId, entityType: .collection)
            } catch {
                await operationQueueService.markFailed(
                    operationId: operation.id,
                    error: "Collection delete replay failed: \(error.localizedDescription)"
                )
            }

        case .acceptConnection, .rejectConnection:
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Unsupported collection queue operation: \(operation.type.rawValue)"
            )
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

                await syncCollectionToCloudKit(collection)
                guard !pendingSyncCollections.contains(collectionId) else {
                    continue
                }

                let membershipSynced = await syncPendingMembershipEdgesToCloudKit(collectionId: collectionId)
                if membershipSynced {
                    self.pendingSyncCollections.remove(collectionId)
                    // Retry successful for collection
                }
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
            let remoteDeletedCollections = try await collectionCloudService.fetchDeletedCollectionTombstones(ownerId: userId)
            let cloudCollections = try await collectionCloudService.fetchCollections(forUserId: userId)
            let cloudMembershipEdges = try await collectionCloudService.fetchMembershipEdges(forUserId: userId)
            let context = ModelContext(modelContainer)
            for tombstone in remoteDeletedCollections {
                try upsertLocalDeletedCollectionTombstone(tombstone, context: context)
                try removeLocalCollectionSuppressedByTombstone(tombstone, context: context)
            }
            let remoteDeletedByCollectionId = remoteDeletedCollections.reduce(into: [UUID: DeletedCollectionTombstone]()) { result, tombstone in
                if let existing = result[tombstone.collectionId] {
                    if existing.deletedAt < tombstone.deletedAt {
                        result[tombstone.collectionId] = tombstone
                    }
                } else {
                    result[tombstone.collectionId] = tombstone
                }
            }
            let deletedCollectionIds = Set(
                try localDeletedCollectionTombstones(context: context).map(\.collectionId)
            )
            let activeCloudMembershipEdges = cloudMembershipEdges.filter {
                !deletedCollectionIds.contains($0.collectionId)
            }
            let cloudMembershipEdgesByCollection = Dictionary(grouping: activeCloudMembershipEdges, by: \.collectionId)
            for edge in activeCloudMembershipEdges {
                try upsertLocalMembershipEdge(edge, context: context)
            }
            if !activeCloudMembershipEdges.isEmpty || !remoteDeletedCollections.isEmpty {
                try context.save()
            }
            // Fetched collections from CloudKit

            // Merge with local collections
            for cloudCollection in cloudCollections {
                guard !deletedCollectionIds.contains(cloudCollection.id) else {
                    logger.info("Skipping collection suppressed by deleted collection tombstone: \(cloudCollection.id)")
                    if let tombstone = CollectionDeleteReplayPolicy.tombstoneForSuppressedActiveRecord(
                        localTombstone: try localDeletedCollectionTombstone(collectionId: cloudCollection.id),
                        remoteTombstone: remoteDeletedByCollectionId[cloudCollection.id]
                    ) {
                        let removedEdges = try localMembershipEdges(collectionId: cloudCollection.id)
                        do {
                            try await syncCollectionDeletionToCloudKit(
                                tombstone: tombstone,
                                removedMembershipEdges: removedEdges
                            )
                        } catch {
                            logger.warning("Failed to clean stale active collection suppressed by tombstone: \(error.localizedDescription)")
                        }
                    } else {
                        logger.warning("Skipping stale active collection cleanup without a durable tombstone: \(cloudCollection.id)")
                    }
                    continue
                }

                let localCollection = try await fetch(id: cloudCollection.id)

                if let local = localCollection {
                    // Update if cloud version is newer (don't update timestamp - sync operation)
                    if cloudCollection.updatedAt > local.updatedAt {
                        let metadataOnlyCollection = collectionWithRecipeIds(cloudCollection, local.recipeIds)
                        try await update(
                            metadataOnlyCollection,
                            shouldUpdateTimestamp: false,
                            updateMembershipEdges: false,
                            queueCloudSync: false
                        )
                        // Updated collection from cloud
                    }
                } else {
                    // Insert new collection from cloud
                    if let membershipEdges = cloudMembershipEdgesByCollection[cloudCollection.id], !membershipEdges.isEmpty {
                        let collectionWithCloudMembership = collectionWithRecipeIds(
                            cloudCollection,
                            CollectionMembershipProjection.activeRecipeIds(from: membershipEdges)
                        )
                        try await insertSyncedCollection(collectionWithCloudMembership, seedMembershipEdges: false)
                    } else {
                        try await insertSyncedCollection(cloudCollection, seedMembershipEdges: true)
                    }
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

        // Delete each collection and wait for CloudKit cleanup before account deletion continues.
        for model in models {
            let collection = try applyMembershipOverlay(
                to: [model.toDomain()],
                context: context
            ).first ?? model.toDomain()
            let deletedAt = Date()
            let tombstone = DeletedCollectionTombstone(
                collectionId: collection.id,
                ownerId: collection.userId,
                deletedAt: deletedAt,
                cloudRecordName: collection.cloudRecordName,
                sourceDeviceId: SyncDeviceIdentifier.current()
            )
            let removedMembershipEdges = removedMembershipEdges(for: collection, deletedAt: deletedAt)

            try upsertLocalDeletedCollectionTombstone(tombstone, context: context)
            for edge in removedMembershipEdges {
                try upsertLocalMembershipEdge(edge, context: context)
            }
            context.delete(model)
            try context.save()

            NotificationCenter.default.post(
                name: .collectionDeleted,
                object: collection.id,
                userInfo: ["collectionId": collection.id]
            )

            guard !RuntimeEnvironment.isRunningTests else {
                continue
            }

            await operationQueueService.addOperation(
                type: .delete,
                entityType: .collection,
                entityId: collection.id
            )
            await operationQueueService.markInProgress(operationId: collection.id)

            do {
                try await syncCollectionDeletionToCloudKit(
                    tombstone: tombstone,
                    removedMembershipEdges: removedMembershipEdges
                )
                await operationQueueService.markCompleted(
                    entityId: collection.id,
                    entityType: .collection
                )
            } catch {
                await operationQueueService.markFailed(
                    operationId: collection.id,
                    error: error.localizedDescription
                )
                throw error
            }
        }

        // Deleted all user collections
    }
}

// MARK: - Errors

enum CollectionRepositoryError: LocalizedError {
    case collectionNotFound
    case invalidData
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .collectionNotFound:
            return "Collection not found"
        case .invalidData:
            return "Invalid collection data"
        case .notAuthorized:
            return "You can only edit your own collections"
        }
    }
}
