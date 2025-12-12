//
//  RecipeRepository+Sync.swift
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
    
    // MARK: - Local to Cloud Sync
    
    /// Sync a recipe to CloudKit with proper error tracking
    /// Note: ALL recipes are synced to iCloud (including private ones) for backup/sync across devices.
    /// Visibility only controls who else can see the recipe, not whether it syncs.
    func syncRecipeToCloudKit(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only sync if we have an owner ID and CloudKit is available
        guard let ownerId = recipe.ownerId else {
            logger.info("Skipping CloudKit sync - no owner ID for recipe: \(recipe.title)")
            return
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isAvailable()
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
    
    /// Delete a recipe from CloudKit with proper error handling
    func deleteRecipeFromCloudKit(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only try to delete if CloudKit is available
        let isAvailable = await cloudKitService.isAvailable()
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
    
    // MARK: - Public Database Sync
    
    /// Sync recipe to PUBLIC database for sharing (if visibility != private)
    func syncRecipeToPublicDatabase(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Don't sync preview recipes to PUBLIC database - they're local-only copies
        guard !recipe.isPreview else {
            logger.info("Skipping PUBLIC database sync for preview recipe: \(recipe.title)")
            return
        }

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
        let isAvailable = await cloudKitService.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - recipe PUBLIC sync will happen later: \(recipe.title)")
            return
        }

        do {
            logger.info("Syncing recipe to PUBLIC database for sharing: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
            try await cloudKitService.copyRecipeToPublic(recipe)
            logger.info("✅ Successfully synced recipe to PUBLIC database")

            // Update share metadata for persistent links
            // This ensures logic is triggered automatically whenever a recipe is made public or updated while public
            await externalShareService.updateShareMetadata(for: recipe)

            // Upload image to PUBLIC database only if it needs to be uploaded
            // Check if image exists and if it's been modified since last upload
            if recipe.imageURL != nil {
                let shouldUpload = await shouldUploadImageToPublic(recipe)
                if shouldUpload {
                    await uploadRecipeImage(recipe, to: .public)
                } else {
                    logger.debug("⏭️ Skipping image upload - already synced to PUBLIC database")
                }
            }
        } catch {
            logger.error("❌ PUBLIC database sync failed for recipe '\(recipe.title)': \(error.localizedDescription)")
        }
    }
    
    /// Delete recipe from PUBLIC database
    func deleteRecipeFromPublicDatabase(_ recipe: Recipe, cloudKitService: CloudKitService) async {
        // Only try to delete if CloudKit is available
        let isAvailable = await cloudKitService.isAvailable()
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
    
    /// Migrate all public recipes to the public database
    /// This ensures that recipes marked as public are actually accessible to others
    func migratePublicRecipesToPublicDatabase() async {
        let migrationKey = "hasMigratedPublicRecipesToPublicDB_v2" // Bumped to v2 to ensure share metadata sync
        
        // Check if already migrated (don't log - it's the common case)
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }
        
        logger.info("🔄 Starting migration of public recipes to PUBLIC database...")
        
        do {
            // 1. Fetch all local recipes
            let allRecipes = try await fetchAll()
            
            // 2. Filter for public recipes
            let publicRecipes = allRecipes.filter { $0.visibility == .publicRecipe }
            logger.info("Found \(publicRecipes.count) public recipes to check")
            
            // 3. Sync each one to public database
            var successCount = 0
            for recipe in publicRecipes {
                // Skip if no owner ID (can't sync)
                guard recipe.ownerId != nil else { continue }
                
                // Trigger sync to public DB
                await syncRecipeToPublicDatabase(recipe, cloudKitService: cloudKitService)
                successCount += 1
                
                // Small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }
            
            // Mark migration as complete
            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("✅ Migration complete: Synced \(successCount) public recipes to PUBLIC database")
        } catch {
            logger.error("❌ Migration failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Retry Logic
    
    /// Start background task to retry failed syncs
    func startSyncRetryTask() {
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
    func retryPendingSyncs() async {
        guard !self.pendingSyncRecipes.isEmpty else { return }

        logger.info("Retrying sync for \(self.pendingSyncRecipes.count) pending recipes")

        // Check if CloudKit is available first
        let isAvailable = await cloudKitService.isAvailable()
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
}
