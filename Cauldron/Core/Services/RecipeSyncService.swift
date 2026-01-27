//
//  RecipeSyncService.swift
//  Cauldron
//
//  Created by Claude on 10/8/25.
//

import Foundation
import os
import CloudKit

/// Sync status for recipe syncing
enum RecipeSyncStatus {
    case idle
    case syncing
    case success
    case failed(Error)

    var isSyncing: Bool {
        if case .syncing = self {
            return true
        }
        return false
    }
}

/// Service to coordinate recipe syncing between local storage and CloudKit
actor RecipeSyncService {
    private let cloudKitCore: CloudKitCore
    private let recipeCloudService: RecipeCloudService
    private let recipeRepository: RecipeRepository
    private let deletedRecipeRepository: DeletedRecipeRepository
    private let imageManager: RecipeImageManager
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeSyncService")

    private var lastSyncDate: Date?
    private let lastSyncKey = "lastRecipeSyncDate"
    private var autoSyncTask: Task<Void, Never>?

    /// Tracks consecutive sync failures to detect persistent issues
    private var consecutiveSyncFailures = 0
    private let maxConsecutiveFailuresBeforeNotification = 3

    init(
        cloudKitCore: CloudKitCore,
        recipeCloudService: RecipeCloudService,
        recipeRepository: RecipeRepository,
        deletedRecipeRepository: DeletedRecipeRepository,
        imageManager: RecipeImageManager
    ) {
        self.cloudKitCore = cloudKitCore
        self.recipeCloudService = recipeCloudService
        self.recipeRepository = recipeRepository
        self.deletedRecipeRepository = deletedRecipeRepository
        self.imageManager = imageManager

        // Load last sync date
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = timestamp
        }
    }

    /// Start automatic background sync every hour - call this after initialization
    nonisolated func startPeriodicSync() {
        Task {
            await startPeriodicSyncInternal()
        }
    }

    /// Start automatic background sync every hour (internal)
    private func startPeriodicSyncInternal() {
        autoSyncTask?.cancel()
        autoSyncTask = Task {
            while !Task.isCancelled {
                // Wait 1 hour
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour

                guard !Task.isCancelled else { break }

                // Perform sync if needed
                if shouldAutoSync() {
                    // Performing automatic periodic sync
                    // Get current user ID from session
                    if let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) {
                        do {
                            try await performFullSync(for: userId)
                            // Reset failure counter on success
                            consecutiveSyncFailures = 0
                        } catch {
                            consecutiveSyncFailures += 1
                            let failureCount = consecutiveSyncFailures
                            let errorMessage = error.localizedDescription
                            logger.warning("Automatic periodic sync failed (\(failureCount)/\(maxConsecutiveFailuresBeforeNotification)): \(errorMessage)")

                            // Notify user after multiple consecutive failures
                            if failureCount >= maxConsecutiveFailuresBeforeNotification {
                                await MainActor.run {
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("SyncHealthDegraded"),
                                        object: nil,
                                        userInfo: ["error": errorMessage, "failureCount": failureCount]
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sync Operations

    /// Perform full bidirectional sync
    func performFullSync(for userId: UUID) async throws {
        // Check if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - skipping sync")
            throw CloudKitError.accountNotAvailable(.couldNotDetermine)
        }

        // Fetch recipes from CloudKit
        let cloudRecipes = try await recipeCloudService.syncUserRecipes(ownerId: userId)

        // Fetch local recipes
        let localRecipes = try await recipeRepository.fetchAll()

        // Merge strategies
        try await mergeRecipes(cloudRecipes: cloudRecipes, localRecipes: localRecipes, userId: userId)

        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Clean up old tombstones (older than 30 days)
        try await deletedRecipeRepository.cleanupOldTombstones()

        // Sync completed successfully (don't log routine operations)
    }

    /// Sync a single recipe to CloudKit
    /// All recipes are synced regardless of visibility - visibility only controls social sharing
    func syncRecipeToCloud(_ recipe: Recipe) async throws {
        guard let ownerId = recipe.ownerId else {
            logger.warning("Cannot sync recipe without owner ID: \(recipe.title)")
            return
        }

        // Syncing recipe to CloudKit
        try await recipeCloudService.saveRecipe(recipe, ownerId: ownerId)
        // Recipe synced successfully
    }

    /// Force sync of all local recipes to CloudKit (useful for recovery)
    /// Syncs ALL recipes regardless of visibility - visibility only controls social sharing
    func forceSyncAllRecipesToCloud(for userId: UUID) async throws {
        // Force syncing all local recipes to CloudKit

        // Check if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot force sync")
            throw CloudKitError.accountNotAvailable(.couldNotDetermine)
        }

        // Fetch all local recipes
        let localRecipes = try await recipeRepository.fetchAll()
        // Found local recipes to sync

        var syncedCount = 0
        var failedCount = 0

        for recipe in localRecipes {
            // Only sync recipes owned by this user
            guard let ownerId = recipe.ownerId, ownerId == userId else {
                continue
            }

            // Sync ALL recipes to iCloud (visibility controls social sharing, not cloud backup)
            do {
                try await recipeCloudService.saveRecipe(recipe, ownerId: ownerId)
                syncedCount += 1
                // Synced recipe
            } catch {
                failedCount += 1
                logger.error("Failed to sync recipe '\(recipe.title)': \(error.localizedDescription)")
            }
        }

        logger.info("✅ Force sync complete - Synced: \(syncedCount), Failed: \(failedCount)")
    }

    /// Delete recipe from CloudKit
    func deleteRecipeFromCloud(_ recipe: Recipe) async throws {
        // Deleting recipe from CloudKit
        try await recipeCloudService.deleteRecipe(recipe)
    }

    // MARK: - Merge Logic

    private func mergeRecipes(cloudRecipes: [Recipe], localRecipes: [Recipe], userId: UUID) async throws {
        // Starting recipe merge process

        // Create dictionaries for faster lookup
        var cloudRecipesByID: [UUID: Recipe] = [:]
        for recipe in cloudRecipes {
            cloudRecipesByID[recipe.id] = recipe
        }

        var localRecipesByID: [UUID: Recipe] = [:]
        for recipe in localRecipes {
            localRecipesByID[recipe.id] = recipe
        }

        // Cloud and local recipes ready for merge

        // Track statistics
        var created = 0
        var updated = 0
        var skipped = 0
        var pushedToCloud = 0
        var deletedLocally = 0

        // Process cloud recipes
        for cloudRecipe in cloudRecipes {
            // Check if this recipe was intentionally deleted locally
            let wasDeleted = try await deletedRecipeRepository.isDeleted(recipeId: cloudRecipe.id)
            if wasDeleted {
                deletedLocally += 1
                skipped += 1
                continue
            }

            if let localRecipe = localRecipesByID[cloudRecipe.id] {
                // Recipe exists both locally and in cloud - check which is newer
                if cloudRecipe.updatedAt > localRecipe.updatedAt {
                    // Cloud version is newer - update local (preserve local-only fields like isFavorite)
                    // Updating local recipe from cloud
                    let mergedRecipe = Recipe(
                        id: cloudRecipe.id,
                        title: cloudRecipe.title,
                        ingredients: cloudRecipe.ingredients,
                        steps: cloudRecipe.steps,
                        yields: cloudRecipe.yields,
                        totalMinutes: cloudRecipe.totalMinutes,
                        tags: cloudRecipe.tags,
                        nutrition: cloudRecipe.nutrition,
                        sourceURL: cloudRecipe.sourceURL,
                        sourceTitle: cloudRecipe.sourceTitle,
                        notes: cloudRecipe.notes,
                        imageURL: cloudRecipe.imageURL,
                        isFavorite: localRecipe.isFavorite,  // Preserve local favorite status
                        visibility: cloudRecipe.visibility,
                        ownerId: cloudRecipe.ownerId,
                        cloudRecordName: cloudRecipe.cloudRecordName,
                        cloudImageRecordName: cloudRecipe.cloudImageRecordName,
                        imageModifiedAt: cloudRecipe.imageModifiedAt,
                        createdAt: cloudRecipe.createdAt,
                        updatedAt: cloudRecipe.updatedAt,
                        relatedRecipeIds: cloudRecipe.relatedRecipeIds  // Preserve related recipes
                    )
                    try await recipeRepository.update(mergedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

                    // Download image if cloud has it and local doesn't
                    await downloadImageIfNeeded(recipe: cloudRecipe, userId: userId)

                    updated += 1
                } else if localRecipe.updatedAt > cloudRecipe.updatedAt {
                    // Local version is newer - push to cloud (preserve CloudKit metadata)
                    // Updating cloud recipe from local
                    if let ownerId = localRecipe.ownerId {
                        let cloudSyncRecipe = Recipe(
                            id: localRecipe.id,
                            title: localRecipe.title,
                            ingredients: localRecipe.ingredients,
                            steps: localRecipe.steps,
                            yields: localRecipe.yields,
                            totalMinutes: localRecipe.totalMinutes,
                            tags: localRecipe.tags,
                            nutrition: localRecipe.nutrition,
                            sourceURL: localRecipe.sourceURL,
                            sourceTitle: localRecipe.sourceTitle,
                            notes: localRecipe.notes,
                            imageURL: localRecipe.imageURL,
                            isFavorite: localRecipe.isFavorite,
                            visibility: localRecipe.visibility,
                            ownerId: ownerId,
                            cloudRecordName: cloudRecipe.cloudRecordName ?? localRecipe.cloudRecordName,  // Preserve CloudKit record name
                            cloudImageRecordName: localRecipe.cloudImageRecordName,
                            imageModifiedAt: localRecipe.imageModifiedAt,
                            createdAt: localRecipe.createdAt,
                            updatedAt: localRecipe.updatedAt,
                            relatedRecipeIds: localRecipe.relatedRecipeIds  // Preserve related recipes
                        )
                        try await recipeCloudService.saveRecipe(cloudSyncRecipe, ownerId: ownerId)

                        // Update local to preserve cloud record name (don't update timestamp - this is just metadata sync)
                        try await recipeRepository.update(cloudSyncRecipe, shouldUpdateTimestamp: false, skipImageSync: true)
                    }
                    updated += 1
                    pushedToCloud += 1
                } else {
                    // Same timestamp - ensure CloudKit metadata is preserved locally
                    if localRecipe.cloudRecordName != cloudRecipe.cloudRecordName ||
                       localRecipe.cloudImageRecordName != cloudRecipe.cloudImageRecordName {
                        let updated = Recipe(
                            id: localRecipe.id,
                            title: localRecipe.title,
                            ingredients: localRecipe.ingredients,
                            steps: localRecipe.steps,
                            yields: localRecipe.yields,
                            totalMinutes: localRecipe.totalMinutes,
                            tags: localRecipe.tags,
                            nutrition: localRecipe.nutrition,
                            sourceURL: localRecipe.sourceURL,
                            sourceTitle: localRecipe.sourceTitle,
                            notes: localRecipe.notes,
                            imageURL: localRecipe.imageURL,
                            isFavorite: localRecipe.isFavorite,
                            visibility: localRecipe.visibility,
                            ownerId: localRecipe.ownerId,
                            cloudRecordName: cloudRecipe.cloudRecordName,  // Update CloudKit metadata
                            cloudImageRecordName: cloudRecipe.cloudImageRecordName,
                            imageModifiedAt: cloudRecipe.imageModifiedAt,
                            createdAt: localRecipe.createdAt,
                            updatedAt: localRecipe.updatedAt,
                            relatedRecipeIds: localRecipe.relatedRecipeIds  // Preserve related recipes
                        )
                        // Don't update timestamp - just syncing CloudKit metadata (skip image sync for metadata-only updates)
                        try await recipeRepository.update(updated, shouldUpdateTimestamp: false, skipImageSync: true)
                    }

                    // Download image if missing locally but exists in cloud
                    await downloadImageIfNeeded(recipe: cloudRecipe, userId: userId)

                    skipped += 1
                }
            } else {
                // Recipe exists in cloud but not locally - create local
                // Creating local recipe from cloud (skip cloud sync since we're downloading FROM cloud)
                try await recipeRepository.create(cloudRecipe, skipCloudSync: true)

                // Download image if exists in cloud
                await downloadImageIfNeeded(recipe: cloudRecipe, userId: userId)

                created += 1
            }
        }

        // Process local-only recipes (push ALL to cloud regardless of visibility)
        for localRecipe in localRecipes {
            if cloudRecipesByID[localRecipe.id] == nil {
                // Recipe exists locally but not in cloud
                if let ownerId = localRecipe.ownerId, ownerId == userId {
                    // Push ALL recipes to cloud (visibility controls social sharing, not cloud backup)
                    // Pushing local recipe to cloud
                    try await recipeCloudService.saveRecipe(localRecipe, ownerId: ownerId)
                    pushedToCloud += 1
                }
            }
        }

        // Log summary with deleted count if any
        if deletedLocally > 0 {
            logger.info("✅ Merge complete - Downloaded: \(created), Updated: \(updated), Pushed to Cloud: \(pushedToCloud), Skipped: \(skipped) (including \(deletedLocally) deleted locally)")
        } else {
            logger.info("✅ Merge complete - Downloaded: \(created), Updated: \(updated), Pushed to Cloud: \(pushedToCloud), Skipped: \(skipped)")
        }
    }

    // MARK: - Sync Info

    func getLastSyncDate() -> Date? {
        return lastSyncDate
    }

    func shouldAutoSync() -> Bool {
        guard let lastSync = lastSyncDate else {
            // Never synced before - should sync
            return true
        }

        // Auto-sync if last sync was more than 1 hour ago
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return lastSync < oneHourAgo
    }

    /// Stop periodic sync (call on deinit if needed)
    func stopPeriodicSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    /// Returns the number of consecutive sync failures (0 = healthy)
    func getSyncHealthStatus() -> Int {
        return consecutiveSyncFailures
    }

    /// Reset the sync failure counter (call after user manually triggers successful sync)
    func resetSyncHealth() {
        consecutiveSyncFailures = 0
    }

    // MARK: - Image Sync Helpers

    /// Download recipe image from CloudKit if needed
    /// - Parameters:
    ///   - recipe: The recipe to check and download image for
    ///   - userId: The current user's ID (to determine which database to use)
    private func downloadImageIfNeeded(recipe: Recipe, userId: UUID) async {
        // Check if image already exists locally
        let hasLocalImage = await imageManager.imageExists(recipeId: recipe.id)
        if hasLocalImage {
            // If local image exists and we have cloud metadata, check if cloud image is newer
            if let cloudModified = recipe.imageModifiedAt {
                let localModified = await imageManager.getImageModificationDate(recipeId: recipe.id)
                if let localModified = localModified,
                   localModified >= cloudModified {
                    // Local image is same or newer, no need to download
                    return
                }
            } else {
                // Local image exists but no cloud metadata - assume local is fine
                return
            }
        }

        // If we get here, either:
        // 1. No local image exists, OR
        // 2. Cloud image is newer than local
        // Always attempt download from CloudKit, regardless of cloudImageRecordName

        // Determine which database to use based on recipe ownership
        let isOwnRecipe = recipe.ownerId == userId
        let fromPublic = !isOwnRecipe

        // Download image from CloudKit
        do {
            if let filename = try await imageManager.downloadImageFromCloud(recipeId: recipe.id, fromPublic: fromPublic) {

                // IMPORTANT: Update recipe's imageURL to point to the local file
                // Build the proper local URL (not the CloudKit temporary path)
                let imageURL = await imageManager.imageURL(for: filename)
                let modificationDate = await imageManager.getImageModificationDate(recipeId: recipe.id)

                // Update recipe with correct imageURL and cloud metadata
                let updatedRecipe = recipe
                    .withImageURL(imageURL)
                    .withCloudImageMetadata(
                        recordName: recipe.cloudImageRecordName ?? recipe.id.uuidString,
                        modifiedAt: modificationDate
                    )
                try? await recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

                // Notify views that recipe image was downloaded (so they can refresh and show the image)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RecipeUpdated"),
                        object: recipe.id
                    )
                }
            }
        } catch {
            logger.warning("Failed to download image for recipe '\(recipe.title)': \(error.localizedDescription)")
        }
    }
}
