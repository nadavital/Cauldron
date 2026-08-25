//
//  RecipeRepository+CRUD.swift
//  Cauldron
//
//  Created by Nadav Avital on 12/10/25.
//

import Foundation
import SwiftData
import os
import CloudKit
import UIKit

enum AccountDeletionRecipeCleanupError: LocalizedError {
    case ownerMismatch(UUID)
    case remoteDeletionIncomplete(UUID, [String])

    var errorDescription: String? {
        switch self {
        case .ownerMismatch(let recipeId):
            return "Recipe \(recipeId) is not owned by the account being deleted."
        case .remoteDeletionIncomplete(let recipeId, let failures):
            return "Could not fully delete recipe \(recipeId) from iCloud: \(failures.joined(separator: "; "))"
        }
    }
}

extension RecipeRepository {
    
    // MARK: - Create

    /// Create a new recipe (optimistic - returns immediately)
    /// - Parameters:
    ///   - recipe: The recipe to create
    ///   - skipCloudSync: If true, only saves locally without triggering CloudKit sync (used when downloading from CloudKit)
    func create(_ recipe: Recipe, skipCloudSync: Bool = false) async throws {
        // Assign cloud record name immediately if not present
        var recipeToSave = recipe
        if recipeToSave.cloudRecordName == nil {
            recipeToSave = Recipe(
                id: recipe.id,
                title: recipe.title,
                ingredients: recipe.ingredients,
                steps: recipe.steps,
                yields: recipe.yields,
                totalMinutes: recipe.totalMinutes,
                tags: recipe.tags,
                nutrition: recipe.nutrition,
                sourceURL: recipe.sourceURL,
                sourceTitle: recipe.sourceTitle,
                notes: recipe.notes,
                imageURL: recipe.imageURL,
                isFavorite: recipe.isFavorite,
                visibility: recipe.visibility,
                ownerId: recipe.ownerId,
                cloudRecordName: recipe.id.uuidString, // Use recipe ID as CloudKit record name
                cloudImageRecordName: recipe.cloudImageRecordName,
                imageModifiedAt: recipe.imageModifiedAt,
                createdAt: recipe.createdAt,
                updatedAt: recipe.updatedAt,
                originalRecipeId: recipe.originalRecipeId,
                originalCreatorId: recipe.originalCreatorId,
                originalCreatorName: recipe.originalCreatorName,
                savedAt: recipe.savedAt,
                sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
                followsSourceUpdates: recipe.followsSourceUpdates,
                relatedRecipeIds: recipe.relatedRecipeIds,
                isPreview: recipe.isPreview
            )
        }

        let accountScope: SyncOperationAccountScope?
        if !skipCloudSync, !RuntimeEnvironment.isRunningTests, !recipeToSave.isPreview {
            guard let ownerID = recipeToSave.ownerId,
                  let verifiedScope = await MainActor.run(body: {
                    CurrentUserSession.shared.syncOperationAccountScope(ownerID: ownerID)
                  }) else { throw UserSessionError.accountChanged }
            accountScope = verifiedScope
        } else {
            accountScope = nil
        }

        // 1. Save locally (immediate)
        let context = ModelContext(modelContainer)
        let model = try RecipeModel.from(recipeToSave)
        context.insert(model)
        try context.save()

        // If this owned recipe was previously deleted, remove the tombstone.
        // Preview/cache records should not clear durable deletion facts.
        if !recipeToSave.isPreview, let ownerId = recipeToSave.ownerId {
            try await deletedRecipeRepository.unmarkAsDeleted(
                recipeId: recipe.id,
                ownerId: ownerId
            )
        }

        // Skip CloudKit sync if requested (e.g., when downloading from CloudKit)
        if skipCloudSync || RuntimeEnvironment.isRunningTests {
            return
        }

        // 2. Queue operation for background sync
        let recipeOwnerID = recipeToSave.ownerId
        let operationID = await operationQueueService.addOperation(
            type: .create,
            entityType: .recipe,
            entityId: recipeToSave.id,
            ownerId: recipeOwnerID,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipeToSave, cloudKitCore, recipeCloudService, operationID, operationQueueService] in
            guard let self else {
                await operationQueueService.markFailed(operationId: operationID, error: "Recipe repository unavailable")
                return
            }

            guard let ownerId = recipeToSave.ownerId,
                  await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: operationID)
            guard let latestRecipe = try? await self.fetch(id: recipeToSave.id, preferredOwnerId: recipeToSave.ownerId) else {
                await operationQueueService.markCompleted(operationId: operationID)
                return
            }
            guard QueuedMutationFreshnessPolicy.matchesPersistedMutation(
                persistedUpdatedAt: latestRecipe.updatedAt,
                persistedVisibility: latestRecipe.visibility,
                expectedUpdatedAt: recipeToSave.updatedAt,
                expectedVisibility: recipeToSave.visibility
            ) else {
                await operationQueueService.markCompleted(operationId: operationID)
                return
            }

            guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            // Attempt sync
            let didSyncPrivate = await self.syncRecipeToCloudKit(latestRecipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Upload image to CloudKit if exists
            if latestRecipe.imageURL != nil {
                await self.uploadRecipeImage(latestRecipe, to: .private)
            }

            // If visibility is public, also copy to PUBLIC database for sharing
            let publicSyncResult = await self.syncRecipeToPublicDatabase(latestRecipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(operationId: operationID)
            } else {
                await self.operationQueueService.markFailed(
                    operationId: operationID,
                    error: "CloudKit sync incomplete for recipe create"
                )
            }
        }
    }
    
    /// Remove duplicate recipes from the local database
    /// This can happen if recipes are synced multiple times due to race conditions
    /// - Returns: The number of duplicates removed
    @discardableResult
    func removeDuplicateRecipes() async throws -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>()
        let allRecipes = try context.fetch(descriptor)

        // Group recipes by ID
        var recipesByID: [UUID: [RecipeModel]] = [:]
        for recipe in allRecipes {
            recipesByID[recipe.id, default: []].append(recipe)
        }

        // Find and remove duplicates
        var removedCount = 0
        for (id, recipes) in recipesByID {
            if recipes.count > 1 {
                logger.warning("🔄 Found \(recipes.count) duplicates for recipe ID: \(id)")

                let nonPreviewOwnerIds = Set(recipes.filter { !$0.isPreview }.compactMap(\.ownerId))
                if nonPreviewOwnerIds.count > 1 {
                    logger.warning("Skipping duplicate repair for recipe ID \(id) because duplicates belong to different owners")
                    continue
                }

                let canonical = recipes.max(by: { lhs, rhs in
                    let lhsScore = duplicateRepairScore(lhs)
                    let rhsScore = duplicateRepairScore(rhs)
                    if lhsScore == rhsScore {
                        return lhs.updatedAt < rhs.updatedAt
                    }
                    return lhsScore < rhsScore
                }) ?? recipes[0]

                for recipe in recipes where recipe !== canonical {
                    mergeDuplicateRecipe(recipe, into: canonical)
                }

                for recipe in recipes where recipe !== canonical {
                    context.delete(recipe)
                    removedCount += 1
                }
            }
        }

        if removedCount > 0 {
            try context.save()
            logger.info("✅ Removed \(removedCount) duplicate recipes")
        }

        return removedCount
    }

    private func duplicateRepairScore(_ recipe: RecipeModel) -> Int {
        var score = 0
        if !recipe.isPreview { score += 10_000 }
        if recipe.ownerId != nil { score += 5_000 }
        if recipe.cloudRecordName != nil { score += 2_500 }
        if recipe.cloudImageRecordName != nil { score += 1_000 }
        if recipe.imageURL != nil { score += 750 }
        if recipe.isFavorite { score += 250 }
        score += min(recipe.ingredientsBlob.count, 2_000)
        score += min(recipe.stepsBlob.count, 2_000)
        score += min(recipe.tagsBlob.count, 500)
        return score
    }

    private func mergeDuplicateRecipe(_ duplicate: RecipeModel, into canonical: RecipeModel) {
        let canonicalIsCopy = Recipe.resolvedFollowsSourceUpdates(
            originalRecipeId: canonical.originalRecipeId,
            savedAt: canonical.savedAt,
            sourceRecipeUpdatedAt: canonical.sourceRecipeUpdatedAt,
            followsSourceUpdates: canonical.followsSourceUpdates
        )

        canonical.isFavorite = canonical.isFavorite || duplicate.isFavorite
        canonical.createdAt = min(canonical.createdAt, duplicate.createdAt)
        canonical.updatedAt = max(canonical.updatedAt, duplicate.updatedAt)

        if canonical.ownerId == nil {
            canonical.ownerId = duplicate.ownerId
        }
        if canonical.cloudRecordName == nil {
            canonical.cloudRecordName = duplicate.cloudRecordName
        }
        if canonical.cloudImageRecordName == nil {
            canonical.cloudImageRecordName = duplicate.cloudImageRecordName
        }
        if canonical.imageModifiedAt == nil {
            canonical.imageModifiedAt = duplicate.imageModifiedAt
        }
        if canonical.imageURL == nil {
            canonical.imageURL = duplicate.imageURL
        }
        if canonical.sourceURL == nil {
            canonical.sourceURL = duplicate.sourceURL
        }
        if canonical.sourceTitle == nil {
            canonical.sourceTitle = duplicate.sourceTitle
        }
        if canonical.notes == nil {
            canonical.notes = duplicate.notes
        }
        if canonicalIsCopy {
            if canonical.originalRecipeId == nil {
                canonical.originalRecipeId = duplicate.originalRecipeId
            }
            if canonical.originalCreatorId == nil {
                canonical.originalCreatorId = duplicate.originalCreatorId
            }
            if canonical.originalCreatorName == nil {
                canonical.originalCreatorName = duplicate.originalCreatorName
            }
            if canonical.savedAt == nil {
                canonical.savedAt = duplicate.savedAt
            }
            if canonical.sourceRecipeUpdatedAt == nil {
                canonical.sourceRecipeUpdatedAt = duplicate.sourceRecipeUpdatedAt
            }
            canonical.followsSourceUpdates = canonical.followsSourceUpdates || duplicate.followsSourceUpdates
        }
        canonical.isPreview = canonical.isPreview && duplicate.isPreview

        if canonical.nutritionBlob == nil {
            canonical.nutritionBlob = duplicate.nutritionBlob
        }
        if canonical.relatedRecipeIdsBlob.isEmpty {
            canonical.relatedRecipeIdsBlob = duplicate.relatedRecipeIdsBlob
        }
    }

    /// Save a public recipe with its image
    /// - Parameters:
    ///   - recipe: The public recipe to save
    ///   - userId: The ID of the user saving the recipe
    /// - Returns: The saved recipe
    func savePublicRecipeWithImage(_ recipe: Recipe, as userId: UUID) async throws -> Recipe {
        // Create a new recipe copy for the user
        let canonicalRelatedRecipeIDs = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: recipe)
        var newRecipe = recipe.withOwner(
            userId,
            visibility: .publicRecipe,
            relatedRecipeIds: canonicalRelatedRecipeIDs
        )
        let sourceImageRecipeID = recipe.sourceAssetReferenceID

        // Download image from Public database if exists
        if recipe.cloudImageRecordName != nil || recipe.imageURL != nil || sourceImageRecipeID != recipe.id {
            do {
                if let imageData = try await recipeCloudService.downloadImageAsset(recipeId: sourceImageRecipeID, fromPublic: true),
                   let image = UIImage(data: imageData) {
                    // Save image locally with new recipe ID
                    _ = try await imageManager.saveImage(image, recipeId: newRecipe.id)

                    // Update image URL
                    let imageURL = await imageManager.imageURL(for: "\(newRecipe.id.uuidString).jpg")
                    newRecipe = newRecipe.withImageState(
                        imageURL: imageURL,
                        cloudImageRecordName: nil,
                        imageModifiedAt: nil
                    )

                    logger.info("✅ Downloaded and saved image for copied recipe")
                }
            } catch {
                logger.warning("Failed to download image for public recipe: \(error.localizedDescription)")
                // Continue without image
            }
        }

        // Create the recipe (will trigger cloud sync)
        try await create(newRecipe)
        return newRecipe
    }

    /// Import a recipe from URL with image
    /// - Parameters:
    ///   - recipe: The recipe to import
    ///   - imageURL: Optional URL of the recipe image
    /// - Returns: The imported recipe
    func importRecipeWithImage(_ recipe: Recipe, imageURL: URL?) async throws -> Recipe {
        var recipeToSave = recipe

        // Download and optimize image if provided
        if let imageURL = imageURL {
            do {
                let filename = try await imageManager.downloadAndSaveImage(from: imageURL, recipeId: recipe.id)
                let localURL = await imageManager.imageURL(for: filename)
                recipeToSave = recipeToSave.withImageURL(localURL)

                logger.info("✅ Downloaded image for imported recipe")
            } catch {
                logger.warning("Failed to download image for imported recipe: \(error.localizedDescription)")
                // Continue without image
            }
        }

        // Create the recipe (will trigger cloud sync with image)
        try await create(recipeToSave)
        return recipeToSave
    }
    
    // MARK: - Read
    
    /// Fetch a recipe by ID
    func fetch(id: UUID) async throws -> Recipe? {
        let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId })
        return try await fetch(id: id, preferredOwnerId: currentUserId)
    }

    internal func fetch(id: UUID, preferredOwnerId: UUID?) async throws -> Recipe? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )

        guard let model = preferredRecipeModel(
            from: try context.fetch(descriptor),
            preferredOwnerId: preferredOwnerId
        ) else {
            return nil
        }
        return try model.toDomain()
    }
    
    /// Fetch multiple recipes by IDs
    func fetch(ids: [UUID]) async throws -> [Recipe] {
        guard !ids.isEmpty else { return [] }
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { ids.contains($0.id) }
        )
        
        let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId })
        let modelsById = Dictionary(grouping: try context.fetch(descriptor), by: \.id)
        var recipes: [Recipe] = []
        recipes.reserveCapacity(ids.count)

        for id in ids {
            guard let models = modelsById[id],
                  let model = preferredRecipeModel(from: models, preferredOwnerId: currentUserId) else {
                continue
            }

            recipes.append(try model.toDomain())
        }

        return recipes
    }
    
    /// Fetch all local non-preview recipes, regardless of owner. Prefer
    /// `fetchLibraryRecipes(ownerId:)` for user-facing library surfaces.
    func fetchAll() async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        // Filter out preview recipes (isPreview = true) - they're for offline access only
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.isPreview == false },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }

    /// Fetch the current user's library recipes only. This is the boundary UI
    /// surfaces should use for local library/profile/collection selection.
    func fetchLibraryRecipes(ownerId: UUID?) async throws -> [Recipe] {
        guard let ownerId else { return [] }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.isPreview == false && model.ownerId == ownerId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Check if a recipe exists in the database
    func recipeExists(id: UUID) async -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )

        do {
            let results = try context.fetch(descriptor)
            return !results.isEmpty
        } catch {
            logger.error("Failed to check if recipe exists: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Update
    
    /// Update a recipe (optimistic - returns immediately)
    /// - Parameters:
    ///   - recipe: The recipe to update
    ///   - shouldUpdateTimestamp: Whether to set updatedAt to current time. Default true for user edits, false for sync operations.
    ///   - skipImageSync: Whether to skip image synchronization. Set to true for metadata-only sync operations to avoid unnecessary image processing.
    ///   - skipCloudSync: Whether to keep the change local-only. Use for preview recipes and other non-owned cached copies.
    func update(
        _ recipe: Recipe,
        shouldUpdateTimestamp: Bool = true,
        skipImageSync: Bool = false,
        skipCloudSync: Bool = false
    ) async throws {
        // Capture old state before updating to detect image changes
        let oldRecipe = try await fetch(id: recipe.id, preferredOwnerId: recipe.ownerId)
        guard let oldRecipe = oldRecipe else {
            throw RepositoryError.notFound
        }

        let accountScope: SyncOperationAccountScope?
        if !skipCloudSync, !RuntimeEnvironment.isRunningTests, !recipe.isPreview {
            guard let ownerID = recipe.ownerId,
                  let verifiedScope = await MainActor.run(body: {
                    CurrentUserSession.shared.syncOperationAccountScope(ownerID: ownerID)
                  }) else { throw UserSessionError.accountChanged }
            accountScope = verifiedScope
        } else {
            accountScope = nil
        }

        // 1. Update recipe in local database (immediate)
        try await updateRecipeInDatabase(recipe, shouldUpdateTimestamp: shouldUpdateTimestamp)

        // The database owns the user-edit timestamp. Capture the value that was
        // actually persisted; comparing replay work to the caller's stale value
        // leaves ordinary edits stuck in progress until stalled-work recovery.
        guard let persistedRecipe = try await fetch(id: recipe.id, preferredOwnerId: recipe.ownerId) else {
            throw RepositoryError.notFound
        }

        guard !skipCloudSync, !RuntimeEnvironment.isRunningTests else {
            return
        }

        // 2. Queue operation for background sync
        let operationID = await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipe.id,
            ownerId: persistedRecipe.ownerId,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, persistedRecipe, oldRecipe, skipImageSync, cloudKitCore, recipeCloudService, operationID, operationQueueService] in
            guard let self else {
                await operationQueueService.markFailed(operationId: operationID, error: "Recipe repository unavailable")
                return
            }

            guard let ownerId = persistedRecipe.ownerId,
                  await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: operationID)
            guard let latestRecipe = try? await self.fetch(id: persistedRecipe.id, preferredOwnerId: persistedRecipe.ownerId) else {
                await operationQueueService.markCompleted(operationId: operationID)
                return
            }
            guard QueuedMutationFreshnessPolicy.matchesPersistedMutation(
                persistedUpdatedAt: latestRecipe.updatedAt,
                persistedVisibility: latestRecipe.visibility,
                expectedUpdatedAt: persistedRecipe.updatedAt,
                expectedVisibility: persistedRecipe.visibility
            ) else {
                // A newer local edit superseded this exact intent. Its successor
                // owns delivery; this claimed operation must still terminate.
                await operationQueueService.markCompleted(operationId: operationID)
                return
            }


            guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            // Sync recipe metadata to CloudKit FIRST (recipe record must exist before image can be attached)
            var didSyncPrivate = await self.syncRecipeToCloudKit(latestRecipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Sync to public database if needed
            var publicSyncResult = await self.syncRecipeToPublicDatabase(latestRecipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Sync image changes only if not skipped (returns updated recipe with cloud metadata)
            if !skipImageSync {
                let recipeWithImageMetadata = try? await self.syncImageChanges(
                    oldRecipe: oldRecipe,
                    newRecipe: latestRecipe
                )

                // If image metadata was updated, sync the updated recipe to CloudKit again
                if let recipeWithImageMetadata = recipeWithImageMetadata,
                   recipeWithImageMetadata.cloudImageRecordName != latestRecipe.cloudImageRecordName {
                    guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                        return
                    }
                    didSyncPrivate = await self.syncRecipeToCloudKit(recipeWithImageMetadata, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

                    if recipeWithImageMetadata.visibility == .publicRecipe {
                        publicSyncResult = await self.syncRecipeToPublicDatabase(recipeWithImageMetadata, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
                    }
                }
            }

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(operationId: operationID)
            } else {
                await self.operationQueueService.markFailed(
                    operationId: operationID,
                    error: "CloudKit sync incomplete for recipe update"
                )
            }
        }
    }

    /// Atomically promotes a deferred import image without replacing any other
    /// recipe fields. The timestamp/source checks prevent a concurrent edit from
    /// being overwritten by the background image task.
    func promoteImportedImageIfCurrent(
        recipeId: UUID,
        ownerId: UUID,
        expectedUpdatedAt: Date,
        expectedImageURL: URL?,
        localizedImageURL: URL
    ) async throws -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == recipeId && $0.ownerId == ownerId }
        )
        guard let model = try context.fetch(descriptor).first,
              model.updatedAt == expectedUpdatedAt,
              model.imageURL == expectedImageURL?.lastPathComponent else {
            return false
        }

        let oldRecipe = try model.toDomain()
        model.imageURL = localizedImageURL.lastPathComponent
        model.updatedAt = Date()
        try context.save()

        let accountScope = await MainActor.run {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: ownerId)
        }

        guard !RuntimeEnvironment.isRunningTests else { return true }

        Task.detached { [weak self, oldRecipe, accountScope, cloudKitCore, recipeCloudService] in
            guard let self else { return }

            // The initial create owns the entity's coalesced queue entry. Wait for
            // that detached sync to finish (success or failure) before enqueueing
            // image promotion, so stale create completion cannot erase this retry.
            while let operation = await self.operationQueueService.getOperation(
                for: recipeId,
                entityType: .recipe
            ), operation.status != .failed {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }

            guard let latestRecipe = try? await self.fetch(id: recipeId, preferredOwnerId: ownerId) else {
                return
            }
            let operationID = await self.operationQueueService.addOperation(
                type: .update,
                entityType: .recipe,
                entityId: recipeId,
                ownerId: ownerId,
                accountRevision: accountScope?.revision,
                accountIdentity: accountScope?.cloudKitIdentity
            )
            guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }
            await self.operationQueueService.markInProgress(operationId: operationID)
            guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }
            let didSyncPrivate = await self.syncRecipeToCloudKit(
                latestRecipe,
                cloudKitCore: cloudKitCore,
                recipeCloudService: recipeCloudService
            )
            let publicResult = await self.syncRecipeToPublicDatabase(
                latestRecipe,
                cloudKitCore: cloudKitCore,
                recipeCloudService: recipeCloudService
            )
            _ = try? await self.syncImageChanges(oldRecipe: oldRecipe, newRecipe: latestRecipe)

            if didSyncPrivate, publicResult.isSuccess {
                await self.operationQueueService.markCompleted(operationId: operationID)
            } else {
                await self.operationQueueService.markFailed(
                    operationId: operationID,
                    error: "CloudKit sync incomplete for imported image promotion"
                )
            }
        }
        return true
    }
    
    /// Update recipe in local database only (no CloudKit sync)
    /// - Parameters:
    ///   - recipe: The recipe to update
    ///   - shouldUpdateTimestamp: Whether to set updatedAt to current time. If false, preserves the recipe's existing timestamp.
    internal func updateRecipeInDatabase(_ recipe: Recipe, shouldUpdateTimestamp: Bool = true) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == recipe.id }
        )

        guard let model = preferredRecipeModel(
            from: try context.fetch(descriptor),
            preferredOwnerId: recipe.ownerId
        ) else {
            throw RepositoryError.notFound
        }

        // Update fields
        let encoder = JSONEncoder()
        model.title = recipe.title
        model.ingredientsBlob = try encoder.encode(recipe.ingredients)
        model.stepsBlob = try encoder.encode(recipe.steps)
        model.tagsBlob = try encoder.encode(recipe.tags)
        model.yields = recipe.yields
        model.totalMinutes = recipe.totalMinutes
        model.nutritionBlob = try recipe.nutrition.map { try encoder.encode($0) }
        model.relatedRecipeIdsBlob = try encoder.encode(recipe.relatedRecipeIds)
        model.sourceURL = recipe.sourceURL?.absoluteString
        model.sourceTitle = recipe.sourceTitle
        model.notes = recipe.notes
        // Store only the filename, not the full path
        model.imageURL = recipe.imageURL?.lastPathComponent
        model.isFavorite = recipe.isFavorite
        model.visibility = recipe.visibility.rawValue
        model.cloudRecordName = recipe.cloudRecordName  // Preserve CloudKit metadata
        model.cloudImageRecordName = recipe.cloudImageRecordName
        model.imageModifiedAt = recipe.imageModifiedAt
        model.ownerId = recipe.ownerId  // Preserve owner ID
        model.originalRecipeId = recipe.originalRecipeId
        model.originalCreatorId = recipe.originalCreatorId
        model.originalCreatorName = recipe.originalCreatorName
        model.savedAt = recipe.savedAt
        model.sourceRecipeUpdatedAt = recipe.sourceRecipeUpdatedAt
        model.followsSourceUpdates = recipe.followsSourceUpdates
        model.isPreview = recipe.isPreview
        // Only update timestamp for user actions, not sync operations
        model.updatedAt = shouldUpdateTimestamp ? Date() : recipe.updatedAt

        try context.save()
    }
    
    /// Toggle favorite status for a recipe
    func toggleFavorite(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )

        let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId })
        guard let model = preferredRecipeModel(
            from: try context.fetch(descriptor),
            preferredOwnerId: currentUserId
        ) else {
            throw RepositoryError.notFound
        }

        // 1. Toggle locally (immediate)
        model.isFavorite.toggle()
        model.updatedAt = Date()
        try context.save()

        // 2. Get updated recipe for background sync
        let recipe = try model.toDomain()

        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        // 3. Queue operation for background sync
        let accountScope = await MainActor.run {
            recipe.ownerId.flatMap { CurrentUserSession.shared.syncOperationAccountScope(ownerID: $0) }
        }
        let operationID = await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: id,
            ownerId: recipe.ownerId,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )

        // 4. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipe, recipeCloudService, operationQueueService] in
            guard let self else {
                await operationQueueService.markFailed(operationId: operationID, error: "Recipe repository unavailable")
                return
            }

            guard let ownerId = recipe.ownerId,
                  await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            await self.operationQueueService.markInProgress(operationId: operationID)

            guard await self.authorizeRecipeReplay(operationID: operationID, entityOwnerId: ownerId) else {
                return
            }

            // Sync to CloudKit
            let didSyncPrivate = await self.syncRecipeToCloudKit(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
            let publicSyncResult = await self.syncRecipeToPublicDatabase(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(operationId: operationID)
            } else {
                await self.operationQueueService.markFailed(
                    operationId: operationID,
                    error: "CloudKit sync incomplete for favorite update"
                )
            }
        }
    }

    /// Update visibility for a recipe
    func updateVisibility(id: UUID, visibility: RecipeVisibility) async throws {
        // Fetch the full recipe
        guard let recipe = try await fetch(id: id) else {
            throw RepositoryError.notFound
        }

        // Store old visibility for notification
        let oldVisibility = recipe.visibility

        // Create updated recipe with new visibility
        let updatedRecipe = Recipe(
            id: recipe.id,
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: recipe.yields,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags,
            nutrition: recipe.nutrition,
            sourceURL: recipe.sourceURL,
            sourceTitle: recipe.sourceTitle,
            notes: recipe.notes,
            imageURL: recipe.imageURL,
            isFavorite: recipe.isFavorite,
            visibility: visibility,
            ownerId: recipe.ownerId,
            cloudRecordName: recipe.cloudRecordName,
            cloudImageRecordName: recipe.cloudImageRecordName,
            imageModifiedAt: recipe.imageModifiedAt,
            createdAt: recipe.createdAt,
            updatedAt: Date(),
            originalRecipeId: recipe.originalRecipeId,
            originalCreatorId: recipe.originalCreatorId,
            originalCreatorName: recipe.originalCreatorName,
            savedAt: recipe.savedAt,
            sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
            followsSourceUpdates: recipe.followsSourceUpdates,
            relatedRecipeIds: recipe.relatedRecipeIds,
            isPreview: recipe.isPreview
        )

        // Update the recipe (this handles CloudKit sync)
        try await update(updatedRecipe)

        if oldVisibility != visibility,
           visibility == .privateRecipe,
           let ownerId = recipe.ownerId {
            let removedCollections = try await collectionRepository?.removeRecipeFromOwnedPublicCollections(
                recipeId: id,
                ownerId: ownerId
            ) ?? []
            if !removedCollections.isEmpty {
                logger.info("Removed private recipe from \(removedCollections.count) public collections")
            }
        }

        logger.info("Updated recipe visibility: \(recipe.title) -> \(visibility.displayName)")

        // Post notification if visibility actually changed
        if oldVisibility != visibility {
            NotificationCenter.default.post(
                name: NSNotification.Name("RecipeVisibilityChanged"),
                object: nil,
                userInfo: [
                    "recipeId": id,
                    "oldVisibility": oldVisibility.rawValue,
                    "newVisibility": visibility.rawValue
                ]
            )
        }
    }

    func visibilityImpactForChangingRecipe(
        id: UUID,
        to visibility: RecipeVisibility
    ) async throws -> RecipeVisibilityChangeImpact {
        guard let recipe = try await fetch(id: id) else {
            throw RepositoryError.notFound
        }

        guard visibility == .privateRecipe,
              recipe.visibility != .privateRecipe,
              let ownerId = recipe.ownerId else {
            return RecipeVisibilityChangeImpact(
                recipeId: id,
                targetVisibility: visibility,
                publicCollectionsAffected: []
            )
        }

        let affectedCollections = try await collectionRepository?.publicCollectionsContainingRecipe(
            recipeId: id,
            ownerId: ownerId
        ) ?? []

        return RecipeVisibilityChangeImpact(
            recipeId: id,
            targetVisibility: visibility,
            publicCollectionsAffected: affectedCollections
        )
    }
    
    /// One-time migration: assign the current user to legacy local recipes that
    /// predate ownership metadata. Standalone records owned by another user are
    /// treated as cached public/source records, but legacy saved copies are
    /// claimed into the current user's library while preserving attribution.
    nonisolated static var legacyRecipeOwnershipMigrationVersion: Int { 1 }
    nonisolated static var legacyRecipeOwnershipMigrationVersionKey: String {
        "recipeOwnershipMigrationVersion"
    }
    nonisolated static var legacyRecipeOwnershipMigrationOwnerKey: String {
        "recipeOwnershipMigrationOwner"
    }

    func migrateRecipeOwnership(
        currentUserId: UUID,
        defaults: UserDefaults = .standard
    ) async throws {
        guard defaults.integer(forKey: Self.legacyRecipeOwnershipMigrationVersionKey)
                < Self.legacyRecipeOwnershipMigrationVersion else {
            try await deletedRecipeRepository.migrateLegacyOwnerlessTombstones(
                to: currentUserId,
                defaults: defaults
            )
            return
        }

        let context = ModelContext(modelContainer)
        let fetchDescriptor = FetchDescriptor<RecipeModel>()
        let allModels = try context.fetch(fetchDescriptor)

        var migratedCount = 0

        for model in allModels {
            if model.isPreview {
                if model.ownerId == currentUserId,
                   let originalCreatorId = model.originalCreatorId {
                    model.ownerId = originalCreatorId
                    migratedCount += 1
                }
                continue
            }

            if model.ownerId == nil {
                model.ownerId = currentUserId
                migratedCount += 1
            } else if model.ownerId != currentUserId,
                      model.originalCreatorId == nil,
                      model.originalRecipeId != nil || model.savedAt != nil {
                if model.originalCreatorId == nil {
                    model.originalCreatorId = model.ownerId
                }
                model.ownerId = currentUserId
                migratedCount += 1
            }
        }

        if migratedCount > 0 {
            try context.save()
            logger.info("Migration complete: Updated \(migratedCount) recipes to have current user as owner")
        }
        defaults.set(Self.legacyRecipeOwnershipMigrationVersion, forKey: Self.legacyRecipeOwnershipMigrationVersionKey)
        defaults.set(currentUserId.uuidString, forKey: Self.legacyRecipeOwnershipMigrationOwnerKey)

        try await deletedRecipeRepository.migrateLegacyOwnerlessTombstones(
            to: currentUserId,
            defaults: defaults
        )
    }
    
    // MARK: - Delete
    
    /// Delete a recipe (optimistic - returns immediately)
    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )

        let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId })
        guard let model = preferredRecipeModel(
            from: try context.fetch(descriptor),
            preferredOwnerId: currentUserId
        ) else {
            throw RepositoryError.notFound
        }

        // Get the recipe before deletion for CloudKit sync and tombstone
        let recipe = try model.toDomain()
        let canMutateCloudState = currentUserId.map { recipe.canMutateCloudState(for: $0) } ?? false
        let accountScope: SyncOperationAccountScope?
        if canMutateCloudState, !RuntimeEnvironment.isRunningTests {
            guard let ownerID = recipe.ownerId,
                  let verifiedScope = await MainActor.run(body: {
                    CurrentUserSession.shared.syncOperationAccountScope(ownerID: ownerID)
                  }) else { throw UserSessionError.accountChanged }
            accountScope = verifiedScope
        } else {
            accountScope = nil
        }

        if !recipe.isPreview {
            let currentUserId = await CurrentUserSession.shared.userId
            if let currentUserId,
               let ownerId = recipe.ownerId,
               ownerId != currentUserId {
                logger.warning("Blocked deletion of non-owned recipe: \(recipe.id)")
                throw RepositoryError.notAuthorized
            }
        }

        // Persist the deletion fact and remove the active row in one SwiftData
        // transaction. A crash can therefore never leave an active recipe removed
        // without the tombstone that prevents CloudKit from resurrecting it.
        if canMutateCloudState, let ownerId = recipe.ownerId {
            let deletedAt = Date()
            let tombstones = try context.fetch(FetchDescriptor<DeletedRecipeModel>())
            if let existing = tombstones.first(where: {
                $0.recipeId == recipe.id && $0.ownerId == ownerId
            }) {
                if existing.deletedAt == nil || existing.deletedAt! <= deletedAt {
                    existing.deletedAt = deletedAt
                    existing.cloudRecordName = existing.cloudRecordName ?? recipe.cloudRecordName
                    existing.sourceDeviceId = existing.sourceDeviceId ?? SyncDeviceIdentifier.current()
                }
            } else {
                context.insert(DeletedRecipeModel(
                    recipeId: recipe.id,
                    ownerId: ownerId,
                    deletedAt: deletedAt,
                    cloudRecordName: recipe.cloudRecordName,
                    sourceDeviceId: SyncDeviceIdentifier.current()
                ))
            }
        }

        // 1. Delete from local database (immediate)
        context.delete(model)
        try context.save()

        // Remove from all collections
        if let collectionRepository = collectionRepository {
            try await collectionRepository.removeRecipeFromAllCollections(recipe.id)
        }

        // Delete local image file immediately
        if recipe.imageURL != nil {
            await imageManager.deleteImage(recipeId: recipe.id)
            await imageSyncManager.removeAllPendingUploads(recipe.id)
        }

        // Post notification that recipe was deleted
        NotificationCenter.default.post(name: NSNotification.Name("RecipeDeleted"), object: recipe.id)

        if recipe.isPreview {
            logger.info("Removed local preview recipe cache: \(recipe.title)")
        } else if !canMutateCloudState {
            logger.info("Removed local cached recipe without remote delete because it is not owned by the current user: \(recipe.title)")
        } else {
            logger.info("Deleted recipe locally and created tombstone: \(recipe.title)")
        }

        guard canMutateCloudState else {
            return
        }

        guard !RuntimeEnvironment.isRunningTests else {
            return
        }

        // 2. Queue operation for background sync
        let deletePayload = RecipeDeleteOperationPayload(
            recipeId: recipe.id,
            ownerId: recipe.ownerId,
            cloudRecordName: recipe.cloudRecordName,
            visibility: recipe.visibility,
            hadImage: recipe.imageURL != nil,
            wasPreview: recipe.isPreview
        )
        let operationID = await operationQueueService.addOperation(
            type: .delete,
            entityType: .recipe,
            entityId: recipe.id,
            payload: try? JSONEncoder().encode(deletePayload),
            ownerId: recipe.ownerId,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )

        // 3. Trigger CloudKit deletion in background (non-blocking)
        Task.detached { [weak self, operationQueueService] in
            guard let self else {
                await operationQueueService.markFailed(operationId: operationID, error: "Recipe repository unavailable")
                return
            }

            guard let operation = await operationQueueService.getOperation(operationId: operationID) else {
                return
            }
            await self.replayRecipeOperation(operation)
        }
    }

    /// Remove a local active recipe after a remote deletion tombstone wins during sync.
    /// This avoids re-queuing the same delete while still cleaning local collection membership.
    internal func removeLocalRecipeAfterRemoteDeletion(id: UUID, ownerId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id && $0.ownerId == ownerId }
        )

        guard let model = try context.fetch(descriptor).first else {
            return
        }

        let recipe = try model.toDomain()
        context.delete(model)
        try context.save()

        if let collectionRepository = collectionRepository {
            try await collectionRepository.removeRecipeFromAllCollections(recipe.id)
        }

        if recipe.imageURL != nil {
            await imageManager.deleteImage(recipeId: recipe.id)
            await imageSyncManager.removeAllPendingUploads(recipe.id)
        }

        NotificationCenter.default.post(name: NSNotification.Name("RecipeDeleted"), object: recipe.id)
        logger.info("Removed local recipe suppressed by remote tombstone: \(recipe.title)")
    }
    
    // MARK: - Account Deletion
    
    /// Delete all recipes owned by a user (for account deletion)
    /// - Parameter userId: The ID of the user whose recipes to delete
    func deleteAllUserRecipes(userId: UUID) async throws {
        logger.info("🗑️ Deleting all recipes for user: \(userId)")

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.ownerId == userId
            }
        )

        let models = try context.fetch(descriptor)
        logger.info("Found \(models.count) recipes to delete")

        var recipes: [Recipe] = []
        for model in models {
            recipes.append(try model.toDomain())
        }

        var remoteDeletionTombstones: [DeletedRecipeTombstone] = []
        if !RuntimeEnvironment.isRunningTests {
            let accountStatus = await cloudKitCore.checkAccountStatus()
            guard accountStatus.isAvailable else {
                throw CloudKitError.accountNotAvailable(accountStatus)
            }

            // Include recipes that exist only on another device. Account
            // deletion must use the authoritative private CloudKit inventory,
            // not merely this installation's local cache.
            let remoteRecipes = try await recipeCloudService.fetchUserRecipes(ownerId: userId)
            remoteDeletionTombstones = try await recipeCloudService.fetchDeletedRecipeTombstones(ownerId: userId)
            let localIDs = Set(recipes.map(\.id))
            recipes.append(contentsOf: remoteRecipes.filter { !localIDs.contains($0.id) })
        }

        // Persist suppression before any remote mutation. Suspended writers
        // re-check this state and the account-deletion gate at publication.
        for recipe in recipes {
            try await deletedRecipeRepository.markAsDeleted(
                recipeId: recipe.id,
                ownerId: userId,
                cloudRecordName: recipe.cloudRecordName
            )
        }

        // Account deletion must not rely on the normal optimistic delete queue.
        // Finish destructive CloudKit work while the deleting user is still active.
        for recipe in recipes {
            try await deleteRemoteRecipeArtifactsForAccountDeletion(recipe, deletingUserId: userId)
        }

        // Resume any deletion that previously stopped after its durable
        // tombstone was written. Such recipes are intentionally absent from
        // fetchUserRecipes, so the tombstone inventory is required here.
        if !RuntimeEnvironment.isRunningTests {
            for tombstone in remoteDeletionTombstones {
                guard let cloudRecordName = tombstone.cloudRecordName else { continue }
                try await recipeCloudService.deletePrivateRecipeRecord(
                    named: cloudRecordName,
                    ownerID: userId
                )
            }
        }

        if !RuntimeEnvironment.isRunningTests {
            try await recipeCloudService.deleteAllPublicRecipesOwnedByCurrentUser(ownerId: userId)
        }

        let deletionContext = ModelContext(modelContainer)
        for recipe in recipes {
            let recipeDescriptor = FetchDescriptor<RecipeModel>(
                predicate: #Predicate { model in
                    model.id == recipe.id && model.ownerId == userId
                }
            )

            for model in try deletionContext.fetch(recipeDescriptor) {
                deletionContext.delete(model)
            }

            if let collectionRepository = collectionRepository {
                try await collectionRepository.removeRecipeFromAllCollections(recipe.id)
            }

            if recipe.imageURL != nil {
                await imageManager.deleteImage(recipeId: recipe.id)
                await imageSyncManager.removeAllPendingUploads(recipe.id)
            }

            await operationQueueService.removeAllOperations(entityId: recipe.id, entityType: .recipe)
            NotificationCenter.default.post(name: NSNotification.Name("RecipeDeleted"), object: recipe.id)
        }

        try deletionContext.save()
        logger.info("✅ Deleted all user recipes")
    }

    private func deleteRemoteRecipeArtifactsForAccountDeletion(
        _ recipe: Recipe,
        deletingUserId: UUID
    ) async throws {
        guard !RuntimeEnvironment.isRunningTests else { return }
        guard !recipe.isPreview else { return }
        guard recipe.ownerId == deletingUserId else {
            throw AccountDeletionRecipeCleanupError.ownerMismatch(recipe.id)
        }

        var failures: [String] = []

        do {
            try await recipeCloudService.saveDeletedRecipeTombstone(
                DeletedRecipeTombstone(
                    recipeId: recipe.id,
                    ownerId: deletingUserId,
                    cloudRecordName: recipe.cloudRecordName
                )
            )
        } catch {
            throw AccountDeletionRecipeCleanupError.remoteDeletionIncomplete(
                recipe.id,
                ["tombstone: \(error.localizedDescription)"]
            )
        }

        if recipe.cloudRecordName != nil {
            do {
                try await recipeCloudService.deleteRecipe(recipe)
            } catch {
                failures.append("private recipe: \(error.localizedDescription)")
            }
        }

        do {
            // Account-wide revocation runs before this inventory cleanup. The
            // deletion gate deliberately rejects per-resource share mutations,
            // so only remove the remaining CloudKit public record here.
            try await recipeCloudService.deletePublicRecipe(
                recipeId: recipe.id,
                ownerID: deletingUserId
            )
        } catch {
            failures.append("public recipe: \(error.localizedDescription)")
        }

        if !failures.isEmpty {
            throw AccountDeletionRecipeCleanupError.remoteDeletionIncomplete(recipe.id, failures)
        }
    }

    private func preferredRecipeModel(
        from models: [RecipeModel],
        preferredOwnerId: UUID?
    ) -> RecipeModel? {
        guard !models.isEmpty else { return nil }

        let selectedModel = models.max { lhs, rhs in
            recipeSelectionScore(lhs, preferredOwnerId: preferredOwnerId) <
                recipeSelectionScore(rhs, preferredOwnerId: preferredOwnerId)
        }

        if models.count > 1, let selectedModel {
            logger.warning("Ambiguous local recipe id \(selectedModel.id.uuidString, privacy: .public); selected owner \(selectedModel.ownerId?.uuidString ?? "none", privacy: .public)")
        }

        return selectedModel
    }

    private func recipeSelectionScore(
        _ model: RecipeModel,
        preferredOwnerId: UUID?
    ) -> Double {
        var score = model.updatedAt.timeIntervalSince1970 / 1_000_000_000

        if let preferredOwnerId, model.ownerId == preferredOwnerId {
            score += 10_000
        }

        if !model.isPreview {
            score += 1_000
        }

        if model.ownerId != nil {
            score += 100
        }

        if model.cloudRecordName != nil {
            score += 10
        }

        return score
    }
}
