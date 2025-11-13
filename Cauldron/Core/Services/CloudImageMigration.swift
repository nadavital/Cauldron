//
//  CloudImageMigration.swift
//  Cauldron
//
//  Created by Claude on 11/5/25.
//

import Foundation
import os
import CloudKit

/// Service to migrate existing local images to CloudKit
actor CloudImageMigration {
    private let recipeRepository: RecipeRepository
    private let imageManager: ImageManager
    private let cloudKitService: CloudKitService
    private let imageSyncManager: ImageSyncManager
    private let logger = Logger(subsystem: "com.cauldron", category: "CloudImageMigration")

    private var migrationTask: Task<Void, Never>?
    private var migrationStatus: MigrationStatus = .notStarted {
        didSet {
            // Emit event when status changes
            Task {
                await imageSyncManager.events.first { _ in
                    // Yield the event
                    return false
                }
            }
        }
    }

    // UserDefaults keys for persistence
    private let migrationCompletedKey = "com.cauldron.imageMigrationCompleted"
    private let lastMigrationAttemptKey = "com.cauldron.lastImageMigrationAttempt"

    init(
        recipeRepository: RecipeRepository,
        imageManager: ImageManager,
        cloudKitService: CloudKitService,
        imageSyncManager: ImageSyncManager
    ) {
        self.recipeRepository = recipeRepository
        self.imageManager = imageManager
        self.cloudKitService = cloudKitService
        self.imageSyncManager = imageSyncManager

        // Load migration status from UserDefaults
        if UserDefaults.standard.bool(forKey: migrationCompletedKey) {
            if let count = UserDefaults.standard.object(forKey: "com.cauldron.imageMigrationCount") as? Int {
                migrationStatus = .completed(migratedCount: count)
            } else {
                migrationStatus = .completed(migratedCount: 0)
            }
        }
    }

    /// Start background migration of existing images to CloudKit
    func startMigration() {
        // Check if migration already completed
        if UserDefaults.standard.bool(forKey: migrationCompletedKey) {
            logger.info("Migration already completed, skipping")
            return
        }

        guard migrationStatus == .notStarted else {
            logger.info("Migration already started")
            return
        }

        migrationStatus = .inProgress(completed: 0, total: 0)

        migrationTask = Task {
            // Wait 5 seconds after app launch to avoid impacting startup
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            guard !Task.isCancelled else { return }

            await performMigration()
        }
    }

    /// Perform the actual migration
    private func performMigration() async {
        logger.info("🔄 Starting cloud image migration...")

        // Check if CloudKit is available
        let isAvailable = await cloudKitService.isCloudKitAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - migration postponed")
            migrationStatus = .failed("CloudKit not available")
            return
        }

        do {
            // Get all recipes
            let recipes = try await recipeRepository.fetchAll()
            let recipesWithImages = recipes.filter { $0.imageURL != nil }

            logger.info("Found \(recipesWithImages.count) recipes with images")

            guard !recipesWithImages.isEmpty else {
                logger.info("No recipes with images to migrate")
                migrationStatus = .completed(migratedCount: 0)
                return
            }

            migrationStatus = .inProgress(completed: 0, total: recipesWithImages.count)

            var migratedCount = 0
            var skippedCount = 0
            var failedCount = 0

            for recipe in recipesWithImages {
                guard !Task.isCancelled else {
                    logger.info("Migration cancelled")
                    return
                }

                // Skip if already migrated (has cloud image record name)
                if recipe.cloudImageRecordName != nil {
                    skippedCount += 1
                    continue
                }

                // Check if image exists locally
                let hasLocalImage = await imageManager.imageExists(recipeId: recipe.id)
                guard hasLocalImage else {
                    skippedCount += 1
                    continue
                }

                // Upload to Private database
                do {
                    let privateDB = try await cloudKitService.getPrivateDatabase()
                    let imageData = try await getImageData(recipeId: recipe.id)

                    logger.info("📤 Migrating image for: \(recipe.title)")

                    let recordName = try await cloudKitService.uploadImageAsset(
                        recipeId: recipe.id,
                        imageData: imageData,
                        to: privateDB
                    )

                    // Update recipe with cloud metadata (migration - don't update timestamp, skip image sync since we just uploaded)
                    let modificationDate = await imageManager.getImageModificationDate(recipeId: recipe.id)
                    let updatedRecipe = recipe.withCloudImageMetadata(
                        recordName: recordName,
                        modifiedAt: modificationDate
                    )

                    try await recipeRepository.update(updatedRecipe, shouldUpdateTimestamp: false, skipImageSync: true)

                    // If recipe is public, also upload to Public database
                    if recipe.visibility == .publicRecipe {
                        let publicDB = try await cloudKitService.getPublicDatabase()
                        _ = try? await cloudKitService.uploadImageAsset(
                            recipeId: recipe.id,
                            imageData: imageData,
                            to: publicDB
                        )
                    }

                    migratedCount += 1
                    migrationStatus = .inProgress(completed: migratedCount + skippedCount, total: recipesWithImages.count)

                    logger.info("✅ Migrated image \(migratedCount)/\(recipesWithImages.count): \(recipe.title)")

                    // Rate limiting: 100ms between uploads to avoid overwhelming CloudKit
                    try? await Task.sleep(nanoseconds: 100_000_000)

                } catch {
                    failedCount += 1
                    logger.error("❌ Failed to migrate image for '\(recipe.title)': \(error.localizedDescription)")
                    // Continue with next recipe
                }
            }

            migrationStatus = .completed(migratedCount: migratedCount)

            // Persist completion status
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.set(migratedCount, forKey: "com.cauldron.imageMigrationCount")
            UserDefaults.standard.set(Date(), forKey: lastMigrationAttemptKey)

            logger.info("✅ Migration complete - Migrated: \(migratedCount), Skipped: \(skippedCount), Failed: \(failedCount)")

        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
            migrationStatus = .failed(error.localizedDescription)
            UserDefaults.standard.set(Date(), forKey: lastMigrationAttemptKey)
        }
    }

    /// Get image data for a recipe
    private func getImageData(recipeId: UUID) async throws -> Data {
        let filename = "\(recipeId.uuidString).jpg"
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw MigrationError.fileNotFound
        }

        let imageURL = documentsURL
            .appendingPathComponent("RecipeImages")
            .appendingPathComponent(filename)

        return try Data(contentsOf: imageURL)
    }

    /// Get current migration progress
    func getMigrationProgress() -> (completed: Int, total: Int)? {
        if case .inProgress(let completed, let total) = migrationStatus {
            return (completed: completed, total: total)
        }
        return nil
    }

    /// Get migration status
    func getStatus() -> MigrationStatus {
        return migrationStatus
    }

    /// Cancel ongoing migration
    func cancelMigration() {
        migrationTask?.cancel()
        migrationTask = nil
        if case .inProgress = migrationStatus {
            migrationStatus = .notStarted
        }
    }

    /// Retry failed migration (clears completed flag to allow re-run)
    func retryMigration() {
        UserDefaults.standard.removeObject(forKey: migrationCompletedKey)
        UserDefaults.standard.removeObject(forKey: "com.cauldron.imageMigrationCount")
        migrationStatus = .notStarted
        startMigration()
    }
}

/// Migration status
enum MigrationStatus: Equatable {
    case notStarted
    case inProgress(completed: Int, total: Int)
    case completed(migratedCount: Int)
    case failed(String)

    var isInProgress: Bool {
        if case .inProgress = self {
            return true
        }
        return false
    }

    var description: String {
        switch self {
        case .notStarted:
            return "Not started"
        case .inProgress(let completed, let total):
            return "Migrating: \(completed)/\(total)"
        case .completed(let count):
            return "Completed: \(count) images migrated"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }
}

/// Migration errors
enum MigrationError: Error {
    case fileNotFound
    case cloudKitNotAvailable
}
