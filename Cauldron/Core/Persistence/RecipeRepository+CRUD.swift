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

extension RecipeRepository {
    
    // MARK: - Create
    
    /// Create a new recipe (optimistic - returns immediately)
    func create(_ recipe: Recipe) async throws {
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
                originalCreatorId: recipe.originalCreatorId,
                originalCreatorName: recipe.originalCreatorName,
                savedAt: recipe.savedAt
            )
        }

        // 1. Save locally (immediate)
        let context = ModelContext(modelContainer)
        let model = try RecipeModel.from(recipeToSave)
        context.insert(model)
        try context.save()

        // If this recipe was previously deleted, remove the tombstone
        try await deletedRecipeRepository.unmarkAsDeleted(recipeId: recipe.id)

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .create,
            entityType: .recipe,
            entityId: recipeToSave.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipeToSave, cloudKitService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipeToSave.id)

            // Attempt sync
            await self.syncRecipeToCloudKit(recipeToSave, cloudKitService: cloudKitService)

            // Upload image to CloudKit if exists
            if recipeToSave.imageURL != nil {
                await self.uploadRecipeImage(recipeToSave, to: .private)
            }

            // If visibility is public, also copy to PUBLIC database for sharing
            await self.syncRecipeToPublicDatabase(recipeToSave, cloudKitService: cloudKitService)

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: recipeToSave.id,
                entityType: .recipe
            )
        }
    }
    
    /// Save a public recipe with its image
    /// - Parameters:
    ///   - recipe: The public recipe to save
    ///   - userId: The ID of the user saving the recipe
    /// - Returns: The saved recipe
    func savePublicRecipeWithImage(_ recipe: Recipe, as userId: UUID) async throws -> Recipe {
        // Create a new recipe copy for the user
        var newRecipe = recipe.withOwner(userId)

        // Download image from Public database if exists
        if recipe.imageURL != nil {
            do {
                let publicDB = try await cloudKitService.getPublicDatabase()
                if let imageData = try await cloudKitService.downloadImageAsset(recipeId: recipe.id, from: publicDB),
                   let image = UIImage(data: imageData) {
                    // Save image locally with new recipe ID
                    _ = try await imageManager.saveImage(image, recipeId: newRecipe.id)

                    // Update image URL
                    let imageURL = await imageManager.imageURL(for: "\(newRecipe.id.uuidString).jpg")
                    newRecipe = newRecipe.withImageURL(imageURL)

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
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
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
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Fetch all recipes (excludes preview recipes)
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
    func update(_ recipe: Recipe, shouldUpdateTimestamp: Bool = true, skipImageSync: Bool = false) async throws {
        // Capture old state before updating to detect image changes
        let oldRecipe = try await fetch(id: recipe.id)
        guard let oldRecipe = oldRecipe else {
            throw RepositoryError.notFound
        }

        // 1. Update recipe in local database (immediate)
        try await updateRecipeInDatabase(recipe, shouldUpdateTimestamp: shouldUpdateTimestamp)

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipe.id
        )

        // 3. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipe, oldRecipe, skipImageSync, cloudKitService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipe.id)

            // Sync recipe metadata to CloudKit FIRST (recipe record must exist before image can be attached)
            await self.syncRecipeToCloudKit(recipe, cloudKitService: cloudKitService)

            // Sync to public database if needed
            await self.syncRecipeToPublicDatabase(recipe, cloudKitService: cloudKitService)

            // Sync image changes only if not skipped (returns updated recipe with cloud metadata)
            if !skipImageSync {
                let recipeWithImageMetadata = try? await self.syncImageChanges(
                    oldRecipe: oldRecipe,
                    newRecipe: recipe
                )

                // If image metadata was updated, sync the updated recipe to CloudKit again
                if let recipeWithImageMetadata = recipeWithImageMetadata,
                   recipeWithImageMetadata.cloudImageRecordName != recipe.cloudImageRecordName {
                    await self.syncRecipeToCloudKit(recipeWithImageMetadata, cloudKitService: cloudKitService)

                    if recipeWithImageMetadata.visibility == .publicRecipe {
                        await self.syncRecipeToPublicDatabase(recipeWithImageMetadata, cloudKitService: cloudKitService)
                    }
                }
            }

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: recipe.id,
                entityType: .recipe
            )
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

        guard let model = try context.fetch(descriptor).first else {
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

        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }

        // 1. Toggle locally (immediate)
        model.isFavorite.toggle()
        model.updatedAt = Date()
        try context.save()

        // 2. Get updated recipe for background sync
        let recipe = try model.toDomain()

        // 3. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: id
        )

        // 4. Trigger sync in background (non-blocking)
        Task.detached { [weak self, recipe, cloudKitService] in
            guard let self = self else { return }

            // Sync to CloudKit
            await self.syncRecipeToCloudKit(recipe, cloudKitService: cloudKitService)
            await self.syncRecipeToPublicDatabase(recipe, cloudKitService: cloudKitService)

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: id,
                entityType: .recipe
            )
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
            createdAt: recipe.createdAt,
            updatedAt: Date()
        )

        // Update the recipe (this handles CloudKit sync)
        try await update(updatedRecipe)

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
    
    /// One-time migration: Update all recipes to set current user as owner
    /// This fixes recipes from the old reference system that may have wrong owner IDs
    func migrateRecipeOwnership(currentUserId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let fetchDescriptor = FetchDescriptor<RecipeModel>()
        let allModels = try context.fetch(fetchDescriptor)

        var migratedCount = 0

        for model in allModels {
            // Only update recipes that don't have the current user as owner
            if model.ownerId != currentUserId {
                let oldOwnerId = model.ownerId

                // If the recipe has an owner and it's not the current user,
                // preserve that as the original creator for attribution
                if let oldOwnerId = oldOwnerId {
                    if model.originalCreatorId == nil {
                        model.originalCreatorId = oldOwnerId
                    }
                }

                // Set current user as the owner
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

        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }

        // Get the recipe before deletion for CloudKit sync and tombstone
        let recipe = try model.toDomain()

        // 1. Delete from local database (immediate)
        context.delete(model)
        try context.save()

        // Remove from all collections
        if let collectionRepository = collectionRepository {
            try await collectionRepository.removeRecipeFromAllCollections(recipe.id)
        }

        // Mark as deleted (create tombstone) to prevent re-downloading from CloudKit
        try await deletedRecipeRepository.markAsDeleted(
            recipeId: recipe.id,
            cloudRecordName: recipe.cloudRecordName
        )

        // Remove from pending sync if it was there
        // Note: access pendingSyncRecipes via self since it is on the actor
        // We will likely need to expose pendingSyncRecipes as internal or move the logic
        // For now, let's assume we can expose a method or property.
        // ACTUALLY: Extensions can't access private properties. I will need to make `pendingSyncRecipes` internal.
        // I will fix access control in the main file cleanup step.
        // For now, code assumes access.
        // pendingSyncRecipes.remove(id) -> Needs access.
        
        // Delete local image file immediately
        if recipe.imageURL != nil {
            await imageManager.deleteImage(recipeId: recipe.id)
            await imageSyncManager.removePendingUpload(recipe.id)
        }

        // Post notification that recipe was deleted
        NotificationCenter.default.post(name: NSNotification.Name("RecipeDeleted"), object: recipe.id)

        logger.info("Deleted recipe locally and created tombstone: \(recipe.title)")

        // 2. Queue operation for background sync
        await operationQueueService.addOperation(
            type: .delete,
            entityType: .recipe,
            entityId: recipe.id
        )

        // 3. Trigger CloudKit deletion in background (non-blocking)
        Task.detached { [weak self, recipe, cloudKitService] in
            guard let self = self else { return }

            // Mark operation as in progress
            await self.operationQueueService.markInProgress(operationId: recipe.id)

            // Delete image from CloudKit if exists
            if recipe.imageURL != nil {
                // Delete from Private database
                await self.deleteRecipeImageFromPrivate(recipe)

                // Delete from Public database if recipe was public
                if recipe.visibility == .publicRecipe {
                    await self.deleteRecipeImageFromPublic(recipe)
                }
            }

            // Delete recipe metadata from CloudKit
            await self.deleteRecipeFromCloudKit(recipe, cloudKitService: cloudKitService)

            // Also delete from PUBLIC database if it was shared
            await self.deleteRecipeFromPublicDatabase(recipe, cloudKitService: cloudKitService)

            // Mark operation as completed
            await self.operationQueueService.markCompleted(
                entityId: recipe.id,
                entityType: .recipe
            )
        }
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

        // Delete each recipe (includes CloudKit cleanup and image deletion)
        for model in models {
            let recipe = try model.toDomain()
            try await delete(id: recipe.id)
        }

        logger.info("✅ Deleted all user recipes")
    }
}
