//
//  RecipeRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData
import os
import CloudKit
import UIKit

/// Thread-safe repository for Recipe operations
actor RecipeRepository {
    private let modelContainer: ModelContainer
    private let cloudKitService: CloudKitService
    private let deletedRecipeRepository: DeletedRecipeRepository
    private let collectionRepository: CollectionRepository?
    private let imageManager: ImageManager
    private let imageSyncManager: ImageSyncManager
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeRepository")

    // Track recipes pending sync
    private var pendingSyncRecipes = Set<UUID>()
    private var syncRetryTask: Task<Void, Never>?
    private var imageSyncRetryTask: Task<Void, Never>?

    // Track retry attempts for exponential backoff
    private var imageRetryAttempts: [UUID: Int] = [:]

    init(
        modelContainer: ModelContainer,
        cloudKitService: CloudKitService,
        deletedRecipeRepository: DeletedRecipeRepository,
        collectionRepository: CollectionRepository? = nil,
        imageManager: ImageManager,
        imageSyncManager: ImageSyncManager
    ) {
        self.modelContainer = modelContainer
        self.cloudKitService = cloudKitService
        self.deletedRecipeRepository = deletedRecipeRepository
        self.collectionRepository = collectionRepository
        self.imageManager = imageManager
        self.imageSyncManager = imageSyncManager

        // Start retry mechanism for failed syncs
        startSyncRetryTask()
        startImageSyncRetryTask()
    }

    /// Create a new recipe
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

        let context = ModelContext(modelContainer)
        let model = try RecipeModel.from(recipeToSave)
        context.insert(model)
        try context.save()

        // If this recipe was previously deleted, remove the tombstone
        try await deletedRecipeRepository.unmarkAsDeleted(recipeId: recipe.id)

        // Immediately attempt to sync to CloudKit (not detached)
        await syncRecipeToCloudKit(recipeToSave, cloudKitService: cloudKitService)

        // Upload image to CloudKit if exists
        if recipeToSave.imageURL != nil {
            await uploadRecipeImage(recipeToSave, to: .private)
        }

        // If visibility is public, also copy to PUBLIC database for sharing
        await syncRecipeToPublicDatabase(recipeToSave, cloudKitService: cloudKitService)
    }

    /// Sync a recipe to CloudKit with proper error tracking
    /// Note: ALL recipes are synced to iCloud (including private ones) for backup/sync across devices.
    /// Visibility only controls who else can see the recipe, not whether it syncs.
    private func syncRecipeToCloudKit(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only sync if we have an owner ID and CloudKit is available
        guard let ownerId = recipe.ownerId else {
            logger.info("Skipping CloudKit sync - no owner ID for recipe: \(recipe.title)")
            return
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - recipe will sync later: \(recipe.title)")
            pendingSyncRecipes.insert(recipe.id)
            return
        }

        // Sync ALL recipes to iCloud, regardless of visibility
        // Visibility only controls social sharing, not cloud backup
        do {
            logger.info("Syncing recipe to CloudKit: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
            try await cloudKitService.saveRecipe(recipe, ownerId: ownerId)
            logger.info("✅ Successfully synced recipe to CloudKit: \(recipe.title)")

            // Remove from pending if it was there
            pendingSyncRecipes.remove(recipe.id)
        } catch {
            logger.error("❌ CloudKit sync failed for recipe '\(recipe.title)': \(error.localizedDescription)")

            // Add to pending sync queue for retry
            pendingSyncRecipes.insert(recipe.id)
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

    /// Retry syncing recipes that failed previously
    private func retryPendingSyncs() async {
        guard !self.pendingSyncRecipes.isEmpty else { return }

        logger.info("Retrying sync for \(self.pendingSyncRecipes.count) pending recipes")

        // Check if CloudKit is available first
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.info("CloudKit still not available - will retry later")
            return
        }

        // Get copy of IDs to retry
        let recipesToRetry = Array(self.pendingSyncRecipes)

        for recipeId in recipesToRetry {
            guard !Task.isCancelled else { break }

            do {
                // Fetch the recipe from local storage
                guard let recipe = try await self.fetch(id: recipeId) else {
                    // Recipe was deleted, remove from pending
                    self.pendingSyncRecipes.remove(recipeId)
                    continue
                }

                // Try to sync again
                await self.syncRecipeToCloudKit(recipe, cloudKitService: self.cloudKitService)
            } catch {
                logger.error("Error fetching recipe for retry sync: \(error.localizedDescription)")
            }
        }

        if self.pendingSyncRecipes.isEmpty {
            logger.info("✅ All pending recipes synced successfully")
        }
    }

    /// Get count of recipes pending sync
    func getPendingSyncCount() -> Int {
        return pendingSyncRecipes.count
    }
    
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
    
    /// Fetch all recipes
    func fetchAll() async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Search recipes by title
    func search(title: String) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let lowercaseTitle = title.lowercased()
        
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.title.localizedStandardContains(lowercaseTitle)
            },
            sortBy: [SortDescriptor(\.title)]
        )
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Search recipes by tag
    func search(tag: String) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>()
        let models = try context.fetch(descriptor)
        
        // Filter by tag in memory (since tags are in blob)
        let recipes = try models.map { try $0.toDomain() }
        return recipes.filter { recipe in
            recipe.tags.contains { $0.name.localizedCaseInsensitiveContains(tag) }
        }
    }
    
    /// Update a recipe
    func update(_ recipe: Recipe) async throws {
        // Capture old state before updating to detect image changes
        let oldRecipe = try await fetch(id: recipe.id)
        guard let oldRecipe = oldRecipe else {
            throw RepositoryError.notFound
        }

        // 1. Update recipe in local database
        try await updateRecipeInDatabase(recipe)

        // 2. Sync image changes (returns updated recipe with cloud metadata)
        let recipeWithImageMetadata = try await syncImageChanges(
            oldRecipe: oldRecipe,
            newRecipe: recipe
        )

        // 3. Sync recipe metadata to CloudKit
        await syncRecipeToCloudKit(recipeWithImageMetadata, cloudKitService: cloudKitService)

        // 4. Sync to public database if needed
        await syncRecipeToPublicDatabase(recipeWithImageMetadata, cloudKitService: cloudKitService)
    }

    /// Update recipe in local database only (no CloudKit sync)
    private func updateRecipeInDatabase(_ recipe: Recipe) async throws {
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
        model.updatedAt = Date()

        // Log image filename being saved
        if let imageFilename = recipe.imageURL?.lastPathComponent {
            AppLogger.general.debug("💾 Saving recipe '\(recipe.title)' with image filename: \(imageFilename)")
        } else {
            AppLogger.general.debug("💾 Saving recipe '\(recipe.title)' with NO image")
        }

        try context.save()
    }

    /// Sync image changes between old and new recipe state
    /// - Parameters:
    ///   - oldRecipe: The recipe state before update
    ///   - newRecipe: The recipe state after update
    /// - Returns: Updated recipe with correct cloud image metadata
    private func syncImageChanges(oldRecipe: Recipe, newRecipe: Recipe) async throws -> Recipe {
        let hadImage = oldRecipe.imageURL != nil
        let hasImage = newRecipe.imageURL != nil
        let imageWasRemoved = hadImage && !hasImage

        // Case 1: Image was removed
        if imageWasRemoved {
            logger.info("🗑️ Image removed from recipe: \(newRecipe.title)")
            return try await handleImageRemoval(oldRecipe: oldRecipe, newRecipe: newRecipe)
        }

        // Case 2: Image exists (either new or updated)
        if hasImage {
            return try await handleImageUpdate(newRecipe)
        }

        // Case 3: No image changes
        return newRecipe
    }

    /// Handle image removal - delete from CloudKit and local storage
    private func handleImageRemoval(oldRecipe: Recipe, newRecipe: Recipe) async throws -> Recipe {
        // Delete from Private database
        await deleteRecipeImageFromPrivate(oldRecipe)

        // Delete from Public database if recipe was public
        if oldRecipe.visibility == .publicRecipe {
            await deleteRecipeImageFromPublic(oldRecipe)
        }

        // Delete local image file
        await imageManager.deleteImage(recipeId: newRecipe.id)

        // Clear cloud image metadata
        let updatedRecipe = newRecipe.withCloudImageMetadata(recordName: nil, modifiedAt: nil)
        try await updateRecipeInDatabase(updatedRecipe)

        return updatedRecipe
    }

    /// Handle image update - upload to CloudKit if needed
    private func handleImageUpdate(_ recipe: Recipe) async throws -> Recipe {
        // Verify image file exists
        let hasLocalImage = await imageManager.imageExists(recipeId: recipe.id)

        guard hasLocalImage else {
            // File missing - clean up metadata
            logger.warning("⚠️ Image file missing for recipe '\(recipe.title)' - cleaning up metadata")
            let cleanedRecipe = recipe.withImageURL(nil).withCloudImageMetadata(recordName: nil, modifiedAt: nil)
            try await updateRecipeInDatabase(cleanedRecipe)
            return cleanedRecipe
        }

        // Check if upload is needed
        let localModified = await imageManager.getImageModificationDate(recipeId: recipe.id)
        guard recipe.needsImageUpload(localImageModified: localModified) else {
            return recipe
        }

        // Upload to private database
        await uploadRecipeImage(recipe, to: .private)

        // Upload to public database if recipe is public
        if recipe.visibility == .publicRecipe {
            await uploadRecipeImage(recipe, to: .public)
        }

        // Fetch updated recipe with cloud metadata
        if let updatedRecipe = try await fetch(id: recipe.id) {
            return updatedRecipe
        }

        return recipe
    }
    
    /// Delete a recipe
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

        // Delete from local database
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
        pendingSyncRecipes.remove(id)

        // Delete image from CloudKit and local storage if exists
        if recipe.imageURL != nil {
            // Delete from Private database
            await deleteRecipeImageFromPrivate(recipe)

            // Delete from Public database if recipe was public
            if recipe.visibility == .publicRecipe {
                await deleteRecipeImageFromPublic(recipe)
            }

            // Delete local image file
            await imageManager.deleteImage(recipeId: recipe.id)

            // Remove from pending image uploads if it was there
            await imageSyncManager.removePendingUpload(recipe.id)
        }

        // Immediately delete from CloudKit
        await deleteRecipeFromCloudKit(recipe, cloudKitService: cloudKitService)

        // Also delete from PUBLIC database if it was shared
        await deleteRecipeFromPublicDatabase(recipe, cloudKitService: cloudKitService)

        // Post notification that recipe was deleted
        NotificationCenter.default.post(name: NSNotification.Name("RecipeDeleted"), object: recipe.id)

        logger.info("Deleted recipe and created tombstone: \(recipe.title)")
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

    /// Delete a recipe from CloudKit with proper error handling
    private func deleteRecipeFromCloudKit(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only try to delete if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete recipe from cloud: \(recipe.title)")
            return
        }

        do {
            logger.info("Deleting recipe from CloudKit: \(recipe.title)")
            try await cloudKitService.deleteRecipe(recipe)
            logger.info("✅ Successfully deleted recipe from CloudKit: \(recipe.title)")
        } catch {
            logger.error("❌ CloudKit deletion failed for recipe '\(recipe.title)': \(error.localizedDescription)")
            // Note: We don't add to pending sync since the recipe is deleted locally
        }
    }

    /// Sync recipe to PUBLIC database for sharing (if visibility != private)
    private func syncRecipeToPublicDatabase(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only sync if visibility is public
        guard recipe.visibility != .privateRecipe else {
            // If recipe was made private, delete from PUBLIC database (including image)
            await deleteRecipeFromPublicDatabase(recipe, cloudKitService: cloudKitService)
            // Delete image from public database
            if recipe.imageURL != nil {
                await deleteRecipeImageFromPublic(recipe)
            }
            return
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - recipe PUBLIC sync will happen later: \(recipe.title)")
            return
        }

        do {
            logger.info("Syncing recipe to PUBLIC database for sharing: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
            try await cloudKitService.copyRecipeToPublic(recipe)
            logger.info("✅ Successfully synced recipe to PUBLIC database")

            // Upload image to PUBLIC database if exists
            if recipe.imageURL != nil {
                await uploadRecipeImage(recipe, to: .public)
            }
        } catch {
            logger.error("❌ PUBLIC database sync failed for recipe '\(recipe.title)': \(error.localizedDescription)")
        }
    }

    /// Delete recipe from PUBLIC database
    private func deleteRecipeFromPublicDatabase(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only try to delete if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete recipe from PUBLIC database: \(recipe.title)")
            return
        }

        guard let ownerId = recipe.ownerId else {
            logger.warning("Cannot delete from PUBLIC database - missing ownerId: \(recipe.title)")
            return
        }

        do {
            logger.info("Deleting recipe from PUBLIC database: \(recipe.title)")
            try await cloudKitService.deletePublicRecipe(recipeId: recipe.id, ownerId: ownerId)
            logger.info("✅ Successfully deleted recipe from PUBLIC database")
        } catch {
            logger.error("❌ PUBLIC database deletion failed for recipe '\(recipe.title)': \(error.localizedDescription)")
        }
    }
    
    /// Fetch recent recipes
    func fetchRecent(limit: Int = 10) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<RecipeModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
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

        model.isFavorite.toggle()
        model.updatedAt = Date()
        try context.save()
    }

    /// Update visibility for a recipe
    func updateVisibility(id: UUID, visibility: RecipeVisibility) async throws {
        // Fetch the full recipe
        guard let recipe = try await fetch(id: id) else {
            throw RepositoryError.notFound
        }

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
    }

    /// Check if a similar recipe already exists
    /// Uses title and ingredient count as heuristics to detect duplicates
    func hasSimilarRecipe(title: String, ownerId: UUID, ingredientCount: Int) async throws -> Bool {
        let context = ModelContext(modelContainer)

        // Fetch all recipes owned by this user
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.ownerId == ownerId
            }
        )

        let models = try context.fetch(descriptor)
        let recipes = try models.map { try $0.toDomain() }

        // Check if any recipe has the same title and similar ingredient count
        let hasSimilar = recipes.contains { recipe in
            recipe.title.lowercased() == title.lowercased() &&
            recipe.ingredients.count == ingredientCount
        }

        logger.info("Checking for similar recipe - title: '\(title)', ingredientCount: \(ingredientCount), hasSimilar: \(hasSimilar)")
        return hasSimilar
    }

    /// One-time migration: Update all recipes to set current user as owner
    /// This fixes recipes from the old reference system that may have wrong owner IDs
    func migrateRecipeOwnership(currentUserId: UUID) async throws {
        logger.info("🔄 Starting recipe ownership migration for user: \(currentUserId)")

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
                        logger.info("  Preserved original creator ID: \(oldOwnerId)")
                    }
                }

                // Set current user as the owner
                model.ownerId = currentUserId
                migratedCount += 1

                logger.info("  ✅ Migrated recipe '\(model.title)' - old owner: \(oldOwnerId?.uuidString ?? "nil") → new owner: \(currentUserId)")
            }
        }

        if migratedCount > 0 {
            try context.save()
            logger.info("✅ Migration complete: Updated \(migratedCount) recipes to have current user as owner")
        } else {
            logger.info("✅ Migration complete: No recipes needed updating")
        }
    }

    // MARK: - Image Sync Methods

    /// Database type enum for clarity
    private enum DatabaseType {
        case `private`
        case `public`
    }

    /// Upload recipe image to CloudKit
    /// - Parameters:
    ///   - recipe: The recipe whose image to upload
    ///   - databaseType: Which database to upload to
    private func uploadRecipeImage(_ recipe: Recipe, to databaseType: DatabaseType) async {
        guard recipe.imageURL != nil else { return }

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - image will sync later")
            await imageSyncManager.addPendingUpload(recipe.id)
            return
        }

        do {
            let database = databaseType == .private ?
                try await cloudKitService.getPrivateDatabase() :
                try await cloudKitService.getPublicDatabase()

            logger.info("📤 Uploading image for recipe: \(recipe.title) to \(databaseType == .private ? "PRIVATE" : "PUBLIC") DB")
            let recordName = try await imageManager.uploadImageToCloud(recipeId: recipe.id, database: database)

            // Update recipe with cloud metadata
            let modificationDate = await imageManager.getImageModificationDate(recipeId: recipe.id)
            let updatedRecipe = recipe.withCloudImageMetadata(recordName: recordName, modifiedAt: modificationDate)
            try await updateRecipeInDatabase(updatedRecipe)

            // Remove from pending uploads
            await imageSyncManager.removePendingUpload(recipe.id)
            logger.info("✅ Image uploaded successfully")

        } catch let error as CloudKitError {
            logger.error("❌ Image upload failed: \(error.localizedDescription)")

            // Don't retry quota exceeded errors - user needs to free up iCloud storage first
            if case .quotaExceeded = error {
                logger.error("⚠️ iCloud storage full - user needs to free up space in Settings")
                // Don't add to pending uploads - retry won't help until user takes action
            } else {
                // Other errors can be retried
                await imageSyncManager.addPendingUpload(recipe.id)
            }
        } catch {
            logger.error("❌ Image upload failed: \(error.localizedDescription)")
            await imageSyncManager.addPendingUpload(recipe.id)
        }
    }

    /// Delete recipe image from Private database
    /// - Parameter recipe: The recipe whose image to delete
    private func deleteRecipeImageFromPrivate(_ recipe: Recipe) async {
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete image from PRIVATE database")
            return
        }

        do {
            let database = try await cloudKitService.getPrivateDatabase()
            logger.info("🗑️ Deleting image from PRIVATE database for recipe: \(recipe.title)")
            try await cloudKitService.deleteImageAsset(recipeId: recipe.id, from: database)
            logger.info("✅ Image deleted from PRIVATE database")
        } catch {
            logger.error("❌ Failed to delete image from PRIVATE database: \(error.localizedDescription)")
        }
    }

    /// Delete recipe image from Public database
    /// - Parameter recipe: The recipe whose image to delete
    private func deleteRecipeImageFromPublic(_ recipe: Recipe) async {
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete image from PUBLIC database")
            return
        }

        do {
            let database = try await cloudKitService.getPublicDatabase()
            logger.info("🗑️ Deleting image from PUBLIC database for recipe: \(recipe.title)")
            try await cloudKitService.deleteImageAsset(recipeId: recipe.id, from: database)
            logger.info("✅ Image deleted from PUBLIC database")
        } catch {
            logger.error("❌ Failed to delete image from PUBLIC database: \(error.localizedDescription)")
        }
    }


    /// Start background task to retry failed image uploads with exponential backoff
    private func startImageSyncRetryTask() {
        imageSyncRetryTask?.cancel()
        imageSyncRetryTask = Task {
            var interval: UInt64 = 120_000_000_000 // Start at 2 minutes
            let maxInterval: UInt64 = 3600_000_000_000 // Cap at 1 hour

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)

                guard !Task.isCancelled else { break }

                // Retry pending image uploads
                let success = await retryPendingImageUploads()

                if success {
                    // Reset backoff on success
                    interval = 120_000_000_000
                } else {
                    // Exponential backoff: 2min → 4min → 8min → 16min → 32min → 1hr
                    interval = min(interval * 2, maxInterval)
                    logger.info("Increasing retry interval to \(interval / 1_000_000_000) seconds")
                }
            }
        }
    }

    /// Retry uploading images that failed previously
    /// - Returns: True if all uploads succeeded or there were no pending uploads, false otherwise
    private func retryPendingImageUploads() async -> Bool {
        let pendingUploads = await imageSyncManager.pendingUploads
        guard !pendingUploads.isEmpty else { return true }

        logger.info("Retrying image upload for \(pendingUploads.count) recipes")

        // Check if CloudKit is available first
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.info("CloudKit still not available - will retry image uploads later")
            return false
        }

        var anySuccess = false
        var allSuccess = true

        for recipeId in pendingUploads {
            guard !Task.isCancelled else { break }

            // Get retry count
            let retryCount = imageRetryAttempts[recipeId, default: 0]

            // Give up after 10 attempts (with exponential backoff, this is ~24 hours)
            if retryCount >= 10 {
                logger.warning("Giving up on image upload for recipe \(recipeId) after 10 attempts")
                await imageSyncManager.removePendingUpload(recipeId)
                imageRetryAttempts.removeValue(forKey: recipeId)
                continue
            }

            do {
                guard let recipe = try await fetch(id: recipeId) else {
                    // Recipe was deleted, remove from pending
                    await imageSyncManager.removePendingUpload(recipeId)
                    imageRetryAttempts.removeValue(forKey: recipeId)
                    continue
                }

                // Try to upload again
                await uploadRecipeImage(recipe, to: .private)
                if recipe.visibility == .publicRecipe {
                    await uploadRecipeImage(recipe, to: .public)
                }

                anySuccess = true
                imageRetryAttempts.removeValue(forKey: recipeId) // Reset on success
            } catch {
                logger.error("Retry failed for recipe \(recipeId): \(error.localizedDescription)")
                imageRetryAttempts[recipeId] = retryCount + 1
                allSuccess = false
            }
        }

        return allSuccess
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
}

enum RepositoryError: Error, LocalizedError {
    case notFound
    case invalidData
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .invalidData:
            return "Invalid data format"
        case .saveFailed:
            return "Failed to save changes"
        }
    }
}
