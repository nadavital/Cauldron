//
//  RecipeRepository+Images.swift
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
    
    // MARK: - Image Sync Methods
    
    /// Database type enum for clarity
    internal enum DatabaseType {
        case `private`
        case `public`
    }
    
    /// Upload recipe image to CloudKit
    /// - Parameters:
    ///   - recipe: The recipe whose image to upload
    ///   - databaseType: Which database to upload to
    internal func uploadRecipeImage(_ recipe: Recipe, to databaseType: DatabaseType) async {
        guard recipe.imageURL != nil else { return }

        let hasLocalImage = await imageManager.imageExists(recipeId: recipe.id)
        guard hasLocalImage else {
            logger.warning("⚠️ Skipping image upload for recipe '\(recipe.title)' because local image file is missing")
            await imageSyncManager.removePendingUpload(recipe.id)
            return
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - image will sync later")
            await imageSyncManager.addPendingUpload(recipe.id)
            return
        }

        do {
            let toPublic = databaseType == .public
            let recordName = try await imageManager.uploadImageToCloud(recipeId: recipe.id, toPublic: toPublic)

            // Update recipe with cloud metadata
            let modificationDate = await imageManager.getImageModificationDate(recipeId: recipe.id)
            let updatedRecipe = recipe.withCloudImageMetadata(recordName: recordName, modifiedAt: modificationDate)
            try await updateRecipeInDatabase(updatedRecipe)

            // Remove from pending uploads
            await imageSyncManager.removePendingUpload(recipe.id)

            // Notify views that recipe was updated (so RecipeDetailView can refresh and show the image)
            NotificationCenter.default.post(
                name: NSNotification.Name("RecipeUpdated"),
                object: recipe.id
            )

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
    internal func deleteRecipeImageFromPrivate(_ recipe: Recipe) async {
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete image from PRIVATE database")
            return
        }

        do {
            logger.info("🗑️ Deleting image from PRIVATE database for recipe: \(recipe.title)")
            try await recipeCloudService.deleteImageAsset(recipeId: recipe.id, fromPublic: false)
            logger.info("✅ Image deleted from PRIVATE database")
        } catch {
            logger.error("❌ Failed to delete image from PRIVATE database: \(error.localizedDescription)")
        }
    }

    /// Delete recipe image from Public database
    /// - Parameter recipe: The recipe whose image to delete
    internal func deleteRecipeImageFromPublic(_ recipe: Recipe) async {
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete image from PUBLIC database")
            return
        }

        do {
            logger.info("🗑️ Deleting image from PUBLIC database for recipe: \(recipe.title)")
            try await recipeCloudService.deleteImageAsset(recipeId: recipe.id, fromPublic: true)
            logger.info("✅ Image deleted from PUBLIC database")
        } catch {
            logger.error("❌ Failed to delete image from PUBLIC database: \(error.localizedDescription)")
        }
    }
    
    /// Sync image changes between old and new recipe state
    /// - Parameters:
    ///   - oldRecipe: The recipe state before update
    ///   - newRecipe: The recipe state after update
    /// - Returns: Updated recipe with correct cloud image metadata
    internal func syncImageChanges(oldRecipe: Recipe, newRecipe: Recipe) async throws -> Recipe {
         let hadImage = oldRecipe.imageURL != nil
         let hasImage = newRecipe.imageURL != nil
         let imageWasRemoved = hadImage && !hasImage

         // Early return: If image URL is unchanged AND file hasn't been modified, skip image processing
         if oldRecipe.imageURL == newRecipe.imageURL && hasImage {
             // Check if the image file was actually modified (e.g., user edited recipe and changed image)
             if let imageModifiedAt = newRecipe.imageModifiedAt,
                let fileModifiedAt = await imageManager.getImageModificationDate(recipeId: newRecipe.id),
                fileModifiedAt <= imageModifiedAt {
                 // File hasn't changed since last upload
                 AppLogger.general.debug("⏭️ Skipping image sync - image URL and file unchanged")
                 return newRecipe
             }
             // File was modified - fall through to upload
             AppLogger.general.debug("📤 Image file was modified - uploading to CloudKit")
         }

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
     internal func handleImageRemoval(oldRecipe: Recipe, newRecipe: Recipe) async throws -> Recipe {
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
     internal func handleImageUpdate(_ recipe: Recipe) async throws -> Recipe {
         // Verify image file exists
         let hasLocalImage = await imageManager.imageExists(recipeId: recipe.id)

         guard hasLocalImage else {
             // File missing - clean up metadata
             logger.warning("⚠️ Image file missing for recipe '\(recipe.title)' - cleaning up metadata")
             let cleanedRecipe = recipe.withImageURL(nil).withCloudImageMetadata(recordName: nil, modifiedAt: nil)
             try await updateRecipeInDatabase(cleanedRecipe)
             return cleanedRecipe
         }

         // IMPORTANT: Upload to PRIVATE database to ensure owner can download after reinstalling.
         // Only upload if:
         // 1. No cloud metadata exists (never uploaded), OR
         // 2. Local image was modified after last upload
         let shouldUploadToPrivate: Bool
         if let cloudImageRecordName = recipe.cloudImageRecordName,
            let imageModifiedAt = recipe.imageModifiedAt,
            let localImageModifiedAt = await imageManager.getImageModificationDate(recipeId: recipe.id) {
             // We have cloud metadata - check if local file is newer
             shouldUploadToPrivate = localImageModifiedAt > imageModifiedAt
         } else {
             // No cloud metadata - need to upload
             shouldUploadToPrivate = true
         }

         if shouldUploadToPrivate {
             await uploadRecipeImage(recipe, to: .private)
         }

         // Public recipes are handled by syncRecipeToPublicDatabase() separately

         // Fetch updated recipe with cloud metadata
         if let updatedRecipe = try await fetch(id: recipe.id) {
             return updatedRecipe
         }

         return recipe
     }
    
    /// Check if image should be uploaded to PUBLIC database
    /// Returns true if image needs to be uploaded (doesn't exist or has been modified)
    internal func shouldUploadImageToPublic(_ recipe: Recipe) async -> Bool {
        // Check if recipe exists in PUBLIC database and already has an image
        guard let ownerId = recipe.ownerId else {
            return true
        }

        do {
            // Fetch the recipe from PUBLIC database to check if image already exists
            guard let publicRecipe = try await recipeCloudService.fetchPublicRecipe(id: recipe.id) else {
                return true  // Recipe doesn't exist in public DB - needs upload
            }

            // If PUBLIC recipe has an image record name, image already exists
            if publicRecipe.cloudImageRecordName != nil {
                // Check if local image has been modified since last upload
                // Use a 1-second tolerance to avoid false positives from date precision differences
                if let imageModifiedAt = publicRecipe.imageModifiedAt,
                   let localImageModifiedAt = await imageManager.getImageModificationDate(recipeId: recipe.id) {
                    let timeDifference = localImageModifiedAt.timeIntervalSince(imageModifiedAt)
                    if timeDifference > 1.0 {
                        // Local image is more than 1 second newer - needs upload
                        return true
                    }
                }

                // Image already exists and hasn't been modified
                return false
            } else {
                // PUBLIC recipe exists but has no image
                return true
            }
        } catch {
            // If we can't fetch the PUBLIC recipe, assume we need to upload
            // (recipe might not exist yet, or there's a network error)
            return true
        }
    }


    /// Start background task to retry failed image uploads with exponential backoff
    internal func startImageSyncRetryTask() {
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
    internal func retryPendingImageUploads() async -> Bool {
        let pendingUploads = await imageSyncManager.pendingUploads
        guard !pendingUploads.isEmpty else { return true }

        logger.info("Retrying image upload for \(pendingUploads.count) recipes")

        // Check if CloudKit is available first
        let isAvailable = await cloudKitCore.isAvailable()
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
    
    // MARK: - Image Filename Migration

    /// Fix corrupted image filenames that may have CloudKit version suffixes
    /// This migration removes any non-.jpg suffixes and ensures proper filename format
    func fixCorruptedImageFilenames() async throws {
        let migrationKey = "hasFixedCorruptedImageFilenames_v2"  // Changed from v1 to v2 to re-run migration

        // Check if already migrated
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        logger.info("🔧 Starting image filename corruption fix...")

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>()
        let models = try context.fetch(descriptor)

        var fixedCount = 0

        for model in models {
            // Check if imageURL has a corrupted filename (contains extra suffix after .jpg)
            guard let imageURLString = model.imageURL,
                  !imageURLString.isEmpty,
                  imageURLString.contains(".") else {
                continue
            }

            // Extract just the filename (handle full URLs or filenames)
            let filename: String
            if imageURLString.contains("/") {
                // Full URL - extract last component
                if let url = URL(string: imageURLString) {
                    filename = url.lastPathComponent
                } else {
                    continue
                }
            } else {
                // Already a filename
                filename = imageURLString
            }

            // Expected correct filename format: {UUID}.jpg
            let correctFilename = "\(model.id.uuidString).jpg"

            // Check if filename is corrupted (doesn't match expected format)
            // Corrupted files have CloudKit version suffixes like: 4F973D88-8DF3-42E6-94B6-92A22F41C44D.01c2c398ff072c0fc6bae69cd0f05d8031707ed35f
            if filename != correctFilename {
                // Filename is corrupted or incorrect!
                logger.info("🔧 Fixing corrupted/incorrect image filename for recipe '\(model.title)'")
                logger.info("   Old: \(filename)")
                logger.info("   New: \(correctFilename)")

                // Check if correct file exists
                let imageURL = await imageManager.imageURL(for: correctFilename)
                let fileExists = await imageManager.imageExists(recipeId: model.id)
                
                // Note: using model.id which is already UUID, no need to decode

                if fileExists {
                    // Correct file exists - just update the database
                    model.imageURL = correctFilename
                    fixedCount += 1
                } else {
                    // Correct file doesn't exist - clear imageURL (will be re-downloaded on next sync)
                    logger.warning("   Image file not found - clearing imageURL (will re-download on next sync)")
                    model.imageURL = nil
                    fixedCount += 1
                }
            }
        }

        if fixedCount > 0 {
            try context.save()
            logger.info("✅ Fixed \(fixedCount) corrupted image filenames")
        } else {
            logger.info("✅ No corrupted image filenames found")
        }

        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
