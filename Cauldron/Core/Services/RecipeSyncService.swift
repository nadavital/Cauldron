//
//  RecipeSyncService.swift
//  Cauldron
//
//  Created by Claude on 10/8/25.
//

import Foundation
import os

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
    private let cloudKitService: CloudKitService
    private let recipeRepository: RecipeRepository
    private let deletedRecipeRepository: DeletedRecipeRepository
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeSyncService")

    private var lastSyncDate: Date?
    private let lastSyncKey = "lastRecipeSyncDate"
    private var autoSyncTask: Task<Void, Never>?

    init(cloudKitService: CloudKitService, recipeRepository: RecipeRepository, deletedRecipeRepository: DeletedRecipeRepository) {
        self.cloudKitService = cloudKitService
        self.recipeRepository = recipeRepository
        self.deletedRecipeRepository = deletedRecipeRepository

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
                    logger.info("Performing automatic periodic sync")
                    // Get current user ID from session
                    if let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) {
                        do {
                            try await performFullSync(for: userId)
                            logger.info("Automatic periodic sync completed")
                        } catch {
                            logger.warning("Automatic periodic sync failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sync Operations

    /// Perform full bidirectional sync
    func performFullSync(for userId: UUID) async throws {
        logger.info("Starting full recipe sync for user: \(userId)")

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - skipping sync")
            throw CloudKitError.accountNotAvailable(.couldNotDetermine)
        }

        // Fetch recipes from CloudKit
        let cloudRecipes = try await cloudKitService.syncUserRecipes(ownerId: userId)
        logger.info("Fetched \(cloudRecipes.count) recipes from CloudKit")

        // Fetch local recipes
        let localRecipes = try await recipeRepository.fetchAll()
        logger.info("Found \(localRecipes.count) local recipes")

        // Merge strategies
        try await mergeRecipes(cloudRecipes: cloudRecipes, localRecipes: localRecipes, userId: userId)

        // Update last sync date
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)

        // Clean up old tombstones (older than 30 days)
        try await deletedRecipeRepository.cleanupOldTombstones()

        logger.info("Recipe sync completed successfully")
    }

    /// Sync a single recipe to CloudKit
    /// All recipes are synced regardless of visibility - visibility only controls social sharing
    func syncRecipeToCloud(_ recipe: Recipe) async throws {
        guard let ownerId = recipe.ownerId else {
            logger.warning("Cannot sync recipe without owner ID: \(recipe.title)")
            return
        }

        logger.info("📤 Syncing recipe to CloudKit: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
        try await cloudKitService.saveRecipe(recipe, ownerId: ownerId)
        logger.info("✅ Recipe synced successfully: \(recipe.title)")
    }

    /// Force sync of all local recipes to CloudKit (useful for recovery)
    /// Syncs ALL recipes regardless of visibility - visibility only controls social sharing
    func forceSyncAllRecipesToCloud(for userId: UUID) async throws {
        logger.info("🔄 Force syncing all local recipes to CloudKit...")

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot force sync")
            throw CloudKitError.accountNotAvailable(.couldNotDetermine)
        }

        // Fetch all local recipes
        let localRecipes = try await recipeRepository.fetchAll()
        logger.info("Found \(localRecipes.count) local recipes to sync")

        var syncedCount = 0
        var failedCount = 0

        for recipe in localRecipes {
            // Only sync recipes owned by this user
            guard let ownerId = recipe.ownerId, ownerId == userId else {
                continue
            }

            // Sync ALL recipes to iCloud (visibility controls social sharing, not cloud backup)
            do {
                try await cloudKitService.saveRecipe(recipe, ownerId: ownerId)
                syncedCount += 1
                logger.info("Synced \(syncedCount)/\(localRecipes.count): \(recipe.title)")
            } catch {
                failedCount += 1
                logger.error("Failed to sync recipe '\(recipe.title)': \(error.localizedDescription)")
            }
        }

        logger.info("✅ Force sync complete - Synced: \(syncedCount), Failed: \(failedCount)")
    }

    /// Delete recipe from CloudKit
    func deleteRecipeFromCloud(_ recipe: Recipe) async throws {
        logger.info("Deleting recipe from CloudKit: \(recipe.title)")
        try await cloudKitService.deleteRecipe(recipe)
    }

    // MARK: - Merge Logic

    private func mergeRecipes(cloudRecipes: [Recipe], localRecipes: [Recipe], userId: UUID) async throws {
        logger.info("🔄 Starting recipe merge process...")

        // Create dictionaries for faster lookup
        var cloudRecipesByID: [UUID: Recipe] = [:]
        for recipe in cloudRecipes {
            cloudRecipesByID[recipe.id] = recipe
        }

        var localRecipesByID: [UUID: Recipe] = [:]
        for recipe in localRecipes {
            localRecipesByID[recipe.id] = recipe
        }

        logger.info("Cloud recipes: \(cloudRecipes.count), Local recipes: \(localRecipes.count)")

        // Track statistics
        var created = 0
        var updated = 0
        var skipped = 0
        var pushedToCloud = 0

        // Process cloud recipes
        for cloudRecipe in cloudRecipes {
            // Check if this recipe was intentionally deleted locally
            let wasDeleted = try await deletedRecipeRepository.isDeleted(recipeId: cloudRecipe.id)
            if wasDeleted {
                logger.info("⛔️ Skipping cloud recipe (deleted locally): \(cloudRecipe.title)")
                skipped += 1
                continue
            }

            if let localRecipe = localRecipesByID[cloudRecipe.id] {
                // Recipe exists both locally and in cloud - check which is newer
                if cloudRecipe.updatedAt > localRecipe.updatedAt {
                    // Cloud version is newer - update local (preserve local-only fields like isFavorite)
                    logger.info("⬇️ Updating local recipe from cloud: \(cloudRecipe.title)")
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
                        createdAt: cloudRecipe.createdAt,
                        updatedAt: cloudRecipe.updatedAt
                    )
                    try await recipeRepository.update(mergedRecipe)
                    updated += 1
                } else if localRecipe.updatedAt > cloudRecipe.updatedAt {
                    // Local version is newer - push to cloud (preserve CloudKit metadata)
                    logger.info("⬆️ Updating cloud recipe from local: \(localRecipe.title)")
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
                            createdAt: localRecipe.createdAt,
                            updatedAt: localRecipe.updatedAt
                        )
                        try await cloudKitService.saveRecipe(cloudSyncRecipe, ownerId: ownerId)

                        // Update local to preserve cloud record name
                        try await recipeRepository.update(cloudSyncRecipe)
                    }
                    updated += 1
                    pushedToCloud += 1
                } else {
                    // Same timestamp - ensure CloudKit metadata is preserved locally
                    if localRecipe.cloudRecordName != cloudRecipe.cloudRecordName {
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
                            createdAt: localRecipe.createdAt,
                            updatedAt: localRecipe.updatedAt
                        )
                        try await recipeRepository.update(updated)
                    }
                    skipped += 1
                }
            } else {
                // Recipe exists in cloud but not locally - create local
                logger.info("⬇️ Creating local recipe from cloud: \(cloudRecipe.title)")
                try await recipeRepository.create(cloudRecipe)
                created += 1
            }
        }

        // Process local-only recipes (push ALL to cloud regardless of visibility)
        for localRecipe in localRecipes {
            if cloudRecipesByID[localRecipe.id] == nil {
                // Recipe exists locally but not in cloud
                if let ownerId = localRecipe.ownerId, ownerId == userId {
                    // Push ALL recipes to cloud (visibility controls social sharing, not cloud backup)
                    logger.info("⬆️ Pushing local recipe to cloud: \(localRecipe.title) (visibility: \(localRecipe.visibility.rawValue))")
                    try await cloudKitService.saveRecipe(localRecipe, ownerId: ownerId)
                    pushedToCloud += 1
                }
            }
        }

        logger.info("✅ Merge complete - Downloaded: \(created), Updated: \(updated), Pushed to Cloud: \(pushedToCloud), Skipped: \(skipped)")
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
}
