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

        // 1. Save locally (immediate)
        let context = ModelContext(modelContainer)
        let model = try RecipeModel.from(recipeToSave)
        context.insert(model)
        try context.save()

        // If this owned recipe was previously deleted, remove the tombstone.
        // Preview/cache records should not clear durable deletion facts.
        if !recipeToSave.isPreview {
            try await deletedRecipeRepository.unmarkAsDeleted(recipeId: recipe.id)
        }

        // Skip CloudKit sync if requested (e.g., when downloading from CloudKit)
        if skipCloudSync || RuntimeEnvironment.isRunningTests {
            return
        }

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .create,
            entityType: .recipe,
            entityId: recipeToSave.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipeToSave, cloudKitCore, recipeCloudService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipeToSave.id)

            // Attempt sync
            let didSyncPrivate = await self.syncRecipeToCloudKit(recipeToSave, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Upload image to CloudKit if exists
            if recipeToSave.imageURL != nil {
                await self.uploadRecipeImage(recipeToSave, to: .private)
            }

            // If visibility is public, also copy to PUBLIC database for sharing
            let publicSyncResult = await self.syncRecipeToPublicDatabase(recipeToSave, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(
                    entityId: recipeToSave.id,
                    entityType: .recipe
                )
            } else {
                await self.operationQueueService.markFailed(
                    operationId: recipeToSave.id,
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

        // 1. Update recipe in local database (immediate)
        try await updateRecipeInDatabase(recipe, shouldUpdateTimestamp: shouldUpdateTimestamp)

        guard !skipCloudSync, !RuntimeEnvironment.isRunningTests else {
            return
        }

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipe.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipe, oldRecipe, skipImageSync, cloudKitCore, recipeCloudService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipe.id)

            // Sync recipe metadata to CloudKit FIRST (recipe record must exist before image can be attached)
            var didSyncPrivate = await self.syncRecipeToCloudKit(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Sync to public database if needed
            var publicSyncResult = await self.syncRecipeToPublicDatabase(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            // Sync image changes only if not skipped (returns updated recipe with cloud metadata)
            if !skipImageSync {
                let recipeWithImageMetadata = try? await self.syncImageChanges(
                    oldRecipe: oldRecipe,
                    newRecipe: recipe
                )

                // If image metadata was updated, sync the updated recipe to CloudKit again
                if let recipeWithImageMetadata = recipeWithImageMetadata,
                   recipeWithImageMetadata.cloudImageRecordName != recipe.cloudImageRecordName {
                    didSyncPrivate = await self.syncRecipeToCloudKit(recipeWithImageMetadata, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

                    if recipeWithImageMetadata.visibility == .publicRecipe {
                        publicSyncResult = await self.syncRecipeToPublicDatabase(recipeWithImageMetadata, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
                    }
                }
            }

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(
                    entityId: recipe.id,
                    entityType: .recipe
                )
            } else {
                await self.operationQueueService.markFailed(
                    operationId: recipe.id,
                    error: "CloudKit sync incomplete for recipe update"
                )
            }
        }
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
        await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: id
        )

        // 4. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipe, recipeCloudService] in
            guard let self = self else { return }

            // Sync to CloudKit
            let didSyncPrivate = await self.syncRecipeToCloudKit(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
            let publicSyncResult = await self.syncRecipeToPublicDatabase(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)

            if didSyncPrivate, publicSyncResult.isSuccess {
                await self.operationQueueService.markCompleted(
                    entityId: id,
                    entityType: .recipe
                )
            } else {
                await self.operationQueueService.markFailed(
                    operationId: id,
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
    func migrateRecipeOwnership(currentUserId: UUID) async throws {
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
        // Don't log if no migration needed - it's the common case
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

        if !recipe.isPreview {
            let currentUserId = await CurrentUserSession.shared.userId
            if let currentUserId,
               let ownerId = recipe.ownerId,
               ownerId != currentUserId {
                logger.warning("Blocked deletion of non-owned recipe: \(recipe.id)")
                throw RepositoryError.notAuthorized
            }
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

        // 1. Delete from local database (immediate)
        context.delete(model)
        try context.save()

        // Remove from all collections
        if let collectionRepository = collectionRepository {
            try await collectionRepository.removeRecipeFromAllCollections(recipe.id)
        }

        if canMutateCloudState {
            // Mark as deleted (create tombstone) to prevent re-downloading from CloudKit.
            try await deletedRecipeRepository.markAsDeleted(
                recipeId: recipe.id,
                cloudRecordName: recipe.cloudRecordName
            )
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
        await operationQueueService.addOperation(
            type: .delete,
            entityType: .recipe,
            entityId: recipe.id,
            payload: try? JSONEncoder().encode(deletePayload)
        )

        // 3. Trigger CloudKit deletion in background (non-blocking)
        Task.detached { [weak self, recipe, recipeCloudService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipe.id)

            var privateDeleteSucceeded = true
            var publicDeleteSucceeded = true
            var tombstoneSaveError: Error?

            if !recipe.isPreview, let ownerId = recipe.ownerId {
                do {
                    let tombstone = DeletedRecipeTombstone(
                        recipeId: recipe.id,
                        ownerId: ownerId,
                        cloudRecordName: recipe.cloudRecordName,
                        sourceDeviceId: deletePayload.sourceDeviceId
                    )
                    try await recipeCloudService.saveDeletedRecipeTombstone(tombstone)
                } catch {
                    tombstoneSaveError = error
                    await self.operationQueueService.markFailed(
                        operationId: recipe.id,
                        error: "Deleted recipe tombstone save failed: \(error.localizedDescription)"
                    )
                }
            }

            guard RecipeDeletionSyncPolicy.canDeleteActiveRecords(tombstoneSaveError: tombstoneSaveError) else {
                return
            }

            // Delete image from CloudKit if exists
            // IMPORTANT: Only delete from cloud if this is the user's own recipe, NOT a preview
            if recipe.imageURL != nil && !recipe.isPreview {
                // Delete from Private database
                await self.deleteRecipeImageFromPrivate(recipe)

                // Delete from Public database if recipe was public
                if recipe.visibility == .publicRecipe {
                    await self.deleteRecipeImageFromPublic(recipe)
                }
            }

            // Delete recipe metadata from CloudKit
            // IMPORTANT: Only delete if this is the user's own recipe, NOT a preview
            if !recipe.isPreview {
                // Delete from private database
                do {
                    try await recipeCloudService.deleteRecipe(recipe)
                } catch {
                    privateDeleteSucceeded = false
                    await self.operationQueueService.markFailed(
                        operationId: recipe.id,
                        error: "Private DB deletion failed: \(error.localizedDescription)"
                    )
                }

                // Always attempt to delete from PUBLIC database (regardless of current visibility)
                // This handles orphaned records from visibility changes or previous sync failures
                do {
                    try await recipeCloudService.deletePublicRecipe(recipeId: recipe.id)
                } catch {
                    publicDeleteSucceeded = false
                    if !privateDeleteSucceeded {
                        await self.operationQueueService.markFailed(
                            operationId: recipe.id,
                            error: "Both private and public DB deletion failed"
                        )
                    }
                }
            }

            if privateDeleteSucceeded, publicDeleteSucceeded {
                await self.operationQueueService.markCompleted(
                    entityId: recipe.id,
                    entityType: .recipe
                )
            } else if privateDeleteSucceeded {
                await self.operationQueueService.markFailed(
                    operationId: recipe.id,
                    error: "Public DB deletion failed"
                )
            }
        }
    }

    /// Remove a local active recipe after a remote deletion tombstone wins during sync.
    /// This avoids re-queuing the same delete while still cleaning local collection membership.
    internal func removeLocalRecipeAfterRemoteDeletion(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
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

        if !RuntimeEnvironment.isRunningTests {
            let accountStatus = await cloudKitCore.checkAccountStatus()
            guard accountStatus.isAvailable else {
                throw CloudKitError.accountNotAvailable(accountStatus)
            }
        }

        // Account deletion must not rely on the normal optimistic delete queue.
        // Finish destructive CloudKit work while the deleting user is still active.
        for recipe in recipes {
            try await deleteRemoteRecipeArtifactsForAccountDeletion(recipe, deletingUserId: userId)
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

            await operationQueueService.markCompleted(entityId: recipe.id, entityType: .recipe)
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
            try await recipeCloudService.deletePublicRecipe(recipeId: recipe.id)
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
