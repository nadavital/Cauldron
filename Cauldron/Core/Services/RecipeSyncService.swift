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
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeSyncService")

    private var lastSyncDate: Date?
    private let lastSyncKey = "lastRecipeSyncDate"

    init(cloudKitService: CloudKitService, recipeRepository: RecipeRepository) {
        self.cloudKitService = cloudKitService
        self.recipeRepository = recipeRepository

        // Load last sync date
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            self.lastSyncDate = timestamp
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

        logger.info("Recipe sync completed successfully")
    }

    /// Sync a single recipe to CloudKit
    func syncRecipeToCloud(_ recipe: Recipe) async throws {
        guard let ownerId = recipe.ownerId else {
            logger.warning("Cannot sync recipe without owner ID: \(recipe.title)")
            return
        }

        // Only sync non-private recipes
        guard recipe.visibility != .privateRecipe else {
            logger.info("Skipping sync for private recipe: \(recipe.title)")
            return
        }

        logger.info("Syncing recipe to CloudKit: \(recipe.title)")
        try await cloudKitService.saveRecipe(recipe, ownerId: ownerId)
    }

    /// Delete recipe from CloudKit
    func deleteRecipeFromCloud(_ recipe: Recipe) async throws {
        logger.info("Deleting recipe from CloudKit: \(recipe.title)")
        try await cloudKitService.deleteRecipe(recipe)
    }

    // MARK: - Merge Logic

    private func mergeRecipes(cloudRecipes: [Recipe], localRecipes: [Recipe], userId: UUID) async throws {
        // Create dictionaries for faster lookup
        var cloudRecipesByID: [UUID: Recipe] = [:]
        for recipe in cloudRecipes {
            cloudRecipesByID[recipe.id] = recipe
        }

        var localRecipesByID: [UUID: Recipe] = [:]
        for recipe in localRecipes {
            localRecipesByID[recipe.id] = recipe
        }

        // Track statistics
        var created = 0
        var updated = 0
        var skipped = 0

        // Process cloud recipes
        for cloudRecipe in cloudRecipes {
            if let localRecipe = localRecipesByID[cloudRecipe.id] {
                // Recipe exists both locally and in cloud - check which is newer
                if cloudRecipe.updatedAt > localRecipe.updatedAt {
                    // Cloud version is newer - update local
                    logger.info("Updating local recipe from cloud: \(cloudRecipe.title)")
                    try await recipeRepository.update(cloudRecipe)
                    updated += 1
                } else if localRecipe.updatedAt > cloudRecipe.updatedAt {
                    // Local version is newer - push to cloud
                    logger.info("Updating cloud recipe from local: \(localRecipe.title)")
                    if let ownerId = localRecipe.ownerId {
                        try await cloudKitService.saveRecipe(localRecipe, ownerId: ownerId)
                    }
                    updated += 1
                } else {
                    // Same timestamp - no update needed
                    skipped += 1
                }
            } else {
                // Recipe exists in cloud but not locally - create local
                logger.info("Creating local recipe from cloud: \(cloudRecipe.title)")
                try await recipeRepository.create(cloudRecipe)
                created += 1
            }
        }

        // Process local-only recipes (push to cloud if non-private and owned by user)
        for localRecipe in localRecipes {
            if cloudRecipesByID[localRecipe.id] == nil {
                // Recipe exists locally but not in cloud
                if localRecipe.visibility != .privateRecipe,
                   let ownerId = localRecipe.ownerId,
                   ownerId == userId {
                    // Push non-private recipes to cloud
                    logger.info("Pushing local recipe to cloud: \(localRecipe.title)")
                    try await cloudKitService.saveRecipe(localRecipe, ownerId: ownerId)
                    created += 1
                }
            }
        }

        logger.info("Merge complete - Created: \(created), Updated: \(updated), Skipped: \(skipped)")
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
}
