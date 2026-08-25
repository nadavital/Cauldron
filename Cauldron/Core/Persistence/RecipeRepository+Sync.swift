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

enum PublicRecipeSyncResult {
    case success
    case retryNeeded

    nonisolated var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }
}

nonisolated struct RecipeDeleteOperationPayload: Codable, Sendable, Equatable {
    let recipeId: UUID
    let ownerId: UUID?
    let cloudRecordName: String?
    let visibility: RecipeVisibility
    let hadImage: Bool
    let wasPreview: Bool
    let sourceDeviceId: String?

    nonisolated init(
        recipeId: UUID,
        ownerId: UUID?,
        cloudRecordName: String?,
        visibility: RecipeVisibility,
        hadImage: Bool,
        wasPreview: Bool,
        sourceDeviceId: String? = SyncDeviceIdentifier.current()
    ) {
        self.recipeId = recipeId
        self.ownerId = ownerId
        self.cloudRecordName = cloudRecordName
        self.visibility = visibility
        self.hadImage = hadImage
        self.wasPreview = wasPreview
        self.sourceDeviceId = sourceDeviceId
    }
}

nonisolated enum RecipeDeletionSyncPolicy {
    static func canDeleteActiveRecords(tombstoneSaveError: Error?) -> Bool {
        tombstoneSaveError == nil
    }
}

extension RecipeRepository {
    private var publicRecipeMigrationCompletedKey: String {
        // v5 also creates any missing Firebase publication pointer after the
        // public CloudKit record is current.
        "hasMigratedPublicRecipesToPublicDB_v5"
    }

    private var publicRecipeMigrationPendingIDsKey: String {
        "\(publicRecipeMigrationCompletedKey)_pendingRecipeIDs"
    }

    private var publicRecipeSearchMetadataMigrationAttemptedKey: String {
        "hasAttemptedPublicRecipeSearchMetadataBackfill_v1"
    }

    private func loadPendingPublicRecipeMigrationIDs() -> Set<UUID> {
        let storedIds = UserDefaults.standard.stringArray(forKey: publicRecipeMigrationPendingIDsKey) ?? []
        return Set(storedIds.compactMap(UUID.init(uuidString:)))
    }

    private func savePendingPublicRecipeMigrationIDs(_ ids: Set<UUID>) {
        if ids.isEmpty {
            UserDefaults.standard.removeObject(forKey: publicRecipeMigrationPendingIDsKey)
            return
        }

        let storedIds = ids.map(\.uuidString).sorted()
        UserDefaults.standard.set(storedIds, forKey: publicRecipeMigrationPendingIDsKey)
    }

    private func currentUserIdForOwnership() async -> UUID? {
        await MainActor.run(body: { CurrentUserSession.shared.userId })
    }
    
    // MARK: - Local to Cloud Sync
    
    /// Sync a recipe to CloudKit with proper error tracking
    /// Note: ALL recipes are synced to iCloud (including private ones) for backup/sync across devices.
    /// Visibility only controls who else can see the recipe, not whether it syncs.
    @discardableResult
    func syncRecipeToCloudKit(_ recipe: Recipe, cloudKitCore: CloudKitCore, recipeCloudService: RecipeCloudService) async -> Bool {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: recipe.ownerId) else {
            return false
        }
        if await isMarkedDeleted(recipeId: recipe.id, ownerId: recipe.ownerId) {
            logger.info("Skipping private recipe sync because recipe is tombstoned: \(recipe.title)")
            pendingSyncRecipes.remove(recipe.id)
            return await deleteRecipeFromCloudKit(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
        }

        // Only sync if we have an owner ID and CloudKit is available
        guard let ownerId = recipe.ownerId else {
            logger.info("Skipping CloudKit sync - no owner ID for recipe: \(recipe.title)")
            return true
        }

        guard let currentUserId = await currentUserIdForOwnership() else {
            logger.info("CloudKit sync deferred - no current user for recipe: \(recipe.title)")
            pendingSyncRecipes.insert(recipe.id)
            return false
        }

        guard ownerId == currentUserId else {
            logger.warning("Skipping CloudKit sync for recipe not owned by the current user: \(recipe.title)")
            pendingSyncRecipes.remove(recipe.id)
            return true
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - recipe will sync later: \(recipe.title)")
            pendingSyncRecipes.insert(recipe.id)
            return false
        }

        // Sync ALL recipes to iCloud, regardless of visibility
        // Visibility only controls social sharing, not cloud backup
        do {
            guard let authorizationContext = await MainActor.run(body: {
                CurrentUserSession.shared.verifiedMutationContext(ownerID: ownerId)
            }) else {
                pendingSyncRecipes.insert(recipe.id)
                return false
            }
            logger.info("Syncing recipe to CloudKit: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
            try await recipeCloudService.saveRecipe(
                recipe,
                ownerId: ownerId,
                authorizationContext: authorizationContext
            )
            logger.info("✅ Successfully synced recipe to CloudKit: \(recipe.title)")

            // Remove from pending if it was there
            pendingSyncRecipes.remove(recipe.id)
            return true
        } catch {
            logger.error("❌ CloudKit sync failed for recipe '\(recipe.title)': \(error.localizedDescription)")

            // Add to pending sync queue for retry
            pendingSyncRecipes.insert(recipe.id)
            return false
        }
    }
    
    /// Delete a recipe from CloudKit with proper error handling
    @discardableResult
    func deleteRecipeFromCloudKit(_ recipe: Recipe, cloudKitCore: CloudKitCore, recipeCloudService: RecipeCloudService) async -> Bool {
        guard let currentUserId = await currentUserIdForOwnership() else {
            logger.info("CloudKit delete deferred - no current user for recipe: \(recipe.title)")
            return false
        }

        guard recipe.canMutateCloudState(for: currentUserId) else {
            logger.warning("Skipping CloudKit delete for recipe not owned by the current user: \(recipe.title)")
            return true
        }

        // Only try to delete if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - cannot delete recipe from cloud: \(recipe.title)")
            return false
        }

        do {
            try await recipeCloudService.saveDeletedRecipeTombstone(
                DeletedRecipeTombstone(
                    recipeId: recipe.id,
                    ownerId: currentUserId,
                    cloudRecordName: recipe.cloudRecordName,
                    sourceDeviceId: SyncDeviceIdentifier.current()
                )
            )
        } catch {
            logger.error("❌ Deleted recipe tombstone save failed before private delete for '\(recipe.title)': \(error.localizedDescription)")
            return false
        }

        do {
            logger.info("Deleting recipe from CloudKit: \(recipe.title)")
            try await recipeCloudService.deleteRecipe(recipe)
            logger.info("✅ Successfully deleted recipe from CloudKit: \(recipe.title)")
            return true
        } catch {
            logger.error("❌ CloudKit deletion failed for recipe '\(recipe.title)': \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Public Database Sync
    
    /// Sync recipe to PUBLIC database for sharing (if visibility != private)
    @discardableResult
    func syncRecipeToPublicDatabase(_ recipe: Recipe, cloudKitCore: CloudKitCore, recipeCloudService: RecipeCloudService) async -> PublicRecipeSyncResult {
        guard await AccountDeletionGate.shared.permitsWrite(ownerID: recipe.ownerId) else {
            return .retryNeeded
        }
        if await isMarkedDeleted(recipeId: recipe.id, ownerId: recipe.ownerId) {
            logger.info("Skipping PUBLIC recipe sync because recipe is tombstoned: \(recipe.title)")
            let didDeletePublicRecipe = await deleteRecipeFromPublicDatabase(
                recipe,
                cloudKitCore: cloudKitCore,
                recipeCloudService: recipeCloudService
            )
            return didDeletePublicRecipe ? .success : .retryNeeded
        }

        // Don't sync preview recipes to PUBLIC database - they're local-only copies
        guard !recipe.isPreview else {
            logger.info("Skipping PUBLIC database sync for preview recipe: \(recipe.title)")
            return .success
        }

        guard let currentUserId = await currentUserIdForOwnership() else {
            logger.info("PUBLIC database sync deferred - no current user for recipe: \(recipe.title)")
            return .retryNeeded
        }

        guard recipe.canMutateCloudState(for: currentUserId) else {
            logger.warning("Skipping PUBLIC database sync for recipe not owned by the current user: \(recipe.title)")
            return .success
        }

        // Only sync if visibility is public
        guard recipe.visibility != .privateRecipe else {
            // If recipe was made private, delete from PUBLIC database (including image)
            let didDeletePublicRecipe = await deleteRecipeFromPublicDatabase(recipe, cloudKitCore: cloudKitCore, recipeCloudService: recipeCloudService)
            // Delete image from public database
            if recipe.imageURL != nil {
                await deleteRecipeImageFromPublic(recipe)
            }
            return didDeletePublicRecipe ? .success : .retryNeeded
        }

        // Check if CloudKit is available
        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("CloudKit not available - recipe PUBLIC sync will happen later: \(recipe.title)")
            return .retryNeeded
        }

        do {
            logger.info("Syncing recipe to PUBLIC database for sharing: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")
            try await recipeCloudService.copyRecipeToPublic(recipe)
            logger.info("✅ Successfully synced recipe to PUBLIC database")

            // Update share metadata for persistent links
            // This ensures logic is triggered automatically whenever a recipe is made public or updated while public
            guard await externalShareService.updateShareMetadata(for: recipe) else {
                logger.warning("Public recipe synced to CloudKit, but its web snapshot needs a retry: \(recipe.title)")
                return .retryNeeded
            }

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
            return .success
        } catch {
            logger.error("❌ PUBLIC database sync failed for recipe '\(recipe.title)': \(error.localizedDescription)")
            return .retryNeeded
        }
    }
    
    /// Delete recipe from PUBLIC database
    @discardableResult
    func deleteRecipeFromPublicDatabase(_ recipe: Recipe, cloudKitCore: CloudKitCore, recipeCloudService: RecipeCloudService) async -> Bool {
        guard let currentUserId = await currentUserIdForOwnership() else {
            logger.info("PUBLIC database delete deferred - no current user for recipe: \(recipe.title)")
            return false
        }

        guard recipe.canMutateCloudState(for: currentUserId) else {
            logger.warning("Skipping PUBLIC database delete for recipe not owned by the current user: \(recipe.title)")
            return true
        }

        guard let ownerID = recipe.ownerId else {
            logger.warning("Cannot delete from PUBLIC database - missing ownerId: \(recipe.title)")
            return true
        }

        // Remove the web-readable snapshot independently of CloudKit. A user
        // with Firebase connectivity but unavailable iCloud must still be able
        // to make a recipe private immediately.
        do {
            try await externalShareService.removeShareMetadata(for: recipe)
        } catch {
            logger.error("❌ Web recipe unpublish failed for '\(recipe.title)': \(error.localizedDescription)")
            return false
        }

        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.warning("Web recipe unpublished; CloudKit public delete will retry: \(recipe.title)")
            return false
        }

        do {
            logger.info("Deleting recipe from PUBLIC database: \(recipe.title)")
            try await recipeCloudService.deletePublicRecipe(
                recipeId: recipe.id,
                ownerID: ownerID
            )
            logger.info("✅ Successfully deleted recipe from PUBLIC database")
            return true
        } catch {
            logger.error("❌ PUBLIC database deletion failed for recipe '\(recipe.title)': \(error.localizedDescription)")
            return false
        }
    }

    private func isMarkedDeleted(recipeId: UUID, ownerId: UUID?) async -> Bool {
        guard let ownerId else { return false }
        return (try? await deletedRecipeRepository.isDeleted(
            recipeId: recipeId,
            ownerId: ownerId
        )) ?? false
    }
    
    /// Migrate all public recipes to the public database
    /// This ensures that recipes marked as public are actually accessible to others
    func migratePublicRecipesToPublicDatabase() async {
        let defaults = UserDefaults.standard
        let hasCompletedMigration = defaults.bool(forKey: publicRecipeMigrationCompletedKey)
        let persistedPendingIds = loadPendingPublicRecipeMigrationIDs()

        if hasCompletedMigration && persistedPendingIds.isEmpty {
            return
        }

        do {
            guard let currentUserId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
                logger.info("Skipping public recipe migration: no current user")
                return
            }

            let ownedRecipes = try await fetchLibraryRecipes(ownerId: currentUserId)
            let publicRecipes = ownedRecipes.filter { $0.visibility == .publicRecipe && $0.ownerId == currentUserId }
            let eligibleRecipeIds = Set(publicRecipes.map(\.id))

            if eligibleRecipeIds.isEmpty {
                defaults.set(true, forKey: publicRecipeMigrationCompletedKey)
                savePendingPublicRecipeMigrationIDs(Set<UUID>())
                logger.info("✅ Public recipe migration complete: no eligible public recipes found")
                return
            }

            var pendingIds = persistedPendingIds
            if pendingIds.isEmpty {
                pendingIds = eligibleRecipeIds
            } else {
                pendingIds.formIntersection(eligibleRecipeIds)
                if !hasCompletedMigration {
                    pendingIds.formUnion(eligibleRecipeIds)
                }
            }

            guard !pendingIds.isEmpty else {
                defaults.set(true, forKey: publicRecipeMigrationCompletedKey)
                savePendingPublicRecipeMigrationIDs(Set<UUID>())
                logger.info("✅ Public recipe migration already up to date")
                return
            }

            logger.info("🔄 Starting migration of \(pendingIds.count) public recipes to PUBLIC database...")

            var remainingIds = pendingIds
            var successCount = 0

            for recipe in publicRecipes where remainingIds.contains(recipe.id) {
                if Task.isCancelled {
                    break
                }

                let result = await syncRecipeToPublicDatabase(
                    recipe,
                    cloudKitCore: cloudKitCore,
                    recipeCloudService: recipeCloudService
                )

                switch result {
                case .success:
                    remainingIds.remove(recipe.id)
                    successCount += 1
                case .retryNeeded:
                    break
                }

                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            }

            savePendingPublicRecipeMigrationIDs(remainingIds)

            if remainingIds.isEmpty {
                defaults.set(true, forKey: publicRecipeMigrationCompletedKey)
                logger.info("✅ Migration complete: synced \(successCount) public recipes to PUBLIC database")
            } else {
                defaults.removeObject(forKey: publicRecipeMigrationCompletedKey)
                logger.warning("⚠️ Public recipe migration incomplete: synced \(successCount), will retry \(remainingIds.count) recipes later")
            }
        } catch {
            logger.error("❌ Migration failed: \(error.localizedDescription)")
        }
    }

    /// Best-effort migration for public recipe search fields used by tag and text discovery.
    ///
    /// The current user's public recipes are also republished by
    /// `migratePublicRecipesToPublicDatabase()`. This broader pass lets older
    /// public records gain queryable metadata when CloudKit permissions allow it,
    /// without doing a broad compatibility scan during Explore navigation.
    func migratePublicRecipeSearchMetadata() async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: publicRecipeSearchMetadataMigrationAttemptedKey) else {
            return
        }

        guard let (ownerID, authorizationContext) = await MainActor.run(body: {
            guard let ownerID = CurrentUserSession.shared.userId,
                  let context = CurrentUserSession.shared.verifiedMutationContext(ownerID: ownerID) else {
                return nil as (UUID, VerifiedAccountMutationContext)?
            }
            return (ownerID, context)
        }) else {
            logger.info("Account identity is not verified - public recipe search metadata migration will retry later")
            return
        }

        let isAvailable = await cloudKitCore.isAvailable()
        guard isAvailable else {
            logger.info("CloudKit not available - public recipe search metadata migration will retry later")
            return
        }

        do {
            let summary = try await recipeCloudService.backfillPublicRecipeSearchMetadata(
                ownerID: ownerID,
                authorizationContext: authorizationContext
            )
            if Self.shouldMarkPublicRecipeSearchMetadataMigrationAttempted(summary) {
                defaults.set(true, forKey: publicRecipeSearchMetadataMigrationAttemptedKey)
            }
            logger.info("✅ Public recipe search metadata migration attempted: scanned \(summary.scanned), updated \(summary.updated), current \(summary.alreadyCurrent), failed \(summary.failed)")
        } catch {
            logger.error("❌ Public recipe search metadata migration failed: \(error.localizedDescription)")
        }
    }

    nonisolated static func shouldMarkPublicRecipeSearchMetadataMigrationAttempted(
        _ summary: PublicRecipeSearchMetadataBackfillSummary
    ) -> Bool {
        !summary.mayHaveMore
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

    func startOperationQueueReplayTask() {
        operationQueueReplayTask?.cancel()
        operationQueueReplayTask = Task {
            await replayReadyRecipeOperations()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await replayReadyRecipeOperations()
            }
        }
    }

    private func replayReadyRecipeOperations() async {
        let operations = await operationQueueService.getAllOperations()
            .filter { operation in
                operation.entityType == .recipe &&
                (operation.status == .pending || operation.isReadyForRetry)
            }

        guard !operations.isEmpty else { return }

        for operation in operations {
            guard !Task.isCancelled else { break }
            await replayRecipeOperation(operation)
        }
    }

    func replayRecipeOperation(_ operation: SyncOperation) async {
        switch operation.type {
        case .create, .update:
            await replayRecipeUpsertOperation(operation)
        case .delete:
            await replayRecipeDeleteOperation(operation)
        case .acceptConnection, .rejectConnection:
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Unsupported recipe queue operation: \(operation.type.rawValue)"
            )
        }
    }

    private func replayRecipeUpsertOperation(_ operation: SyncOperation) async {
        do {
            guard let recipe = try await fetch(
                id: operation.entityId,
                preferredOwnerId: operation.ownerId
            ) else {
                if let ownerId = operation.ownerId,
                   try await deletedRecipeRepository.isDeleted(
                       recipeId: operation.entityId,
                       ownerId: ownerId
                   ) {
                    logger.info("Completing stale recipe upsert suppressed by deletion tombstone: \(operation.entityId)")
                    await operationQueueService.markCompleted(operationId: operation.id)
                } else {
                    await operationQueueService.markCompleted(operationId: operation.id)
                }
                return
            }

            guard let ownerId = recipe.ownerId else {
                await operationQueueService.quarantineOperation(
                    operationId: operation.id,
                    error: "Recipe operation has no locally validated owner"
                )
                return
            }

            guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }
            await operationQueueService.markInProgress(operationId: operation.id)

            let didSyncPrivate = await syncRecipeToCloudKit(
                recipe,
                cloudKitCore: cloudKitCore,
                recipeCloudService: recipeCloudService
            )
            let publicSyncResult = await syncRecipeToPublicDatabase(
                recipe,
                cloudKitCore: cloudKitCore,
                recipeCloudService: recipeCloudService
            )

            if didSyncPrivate, publicSyncResult.isSuccess {
                await operationQueueService.markCompleted(operationId: operation.id)
            } else {
                await operationQueueService.markFailed(
                    operationId: operation.id,
                    error: "Recipe replay sync incomplete"
                )
            }
        } catch {
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Recipe replay failed: \(error.localizedDescription)"
            )
        }
    }

    private func replayRecipeDeleteOperation(_ operation: SyncOperation) async {
        let payload = operation.payload.flatMap {
            try? JSONDecoder().decode(RecipeDeleteOperationPayload.self, from: $0)
        }

        do {
            if let payload {
                try await replayRecipeDeleteOperation(operation, payload: payload)
                return
            }

            if let recipe = try await fetch(
                id: operation.entityId,
                preferredOwnerId: operation.ownerId
            ) {
                let payload = RecipeDeleteOperationPayload(
                    recipeId: recipe.id,
                    ownerId: recipe.ownerId,
                    cloudRecordName: recipe.cloudRecordName,
                    visibility: recipe.visibility,
                    hadImage: recipe.imageURL != nil,
                    wasPreview: recipe.isPreview
                )
                try await replayRecipeDeleteOperation(operation, payload: payload)
                return
            }

            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Missing recipe delete payload"
            )
        } catch {
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Recipe delete replay failed: \(error.localizedDescription)"
            )
        }
    }

    private func replayRecipeDeleteOperation(
        _ operation: SyncOperation,
        payload: RecipeDeleteOperationPayload
    ) async throws {
        guard !payload.wasPreview else {
            logger.info("Completing queued delete for local-only preview recipe: \(payload.recipeId)")
            await operationQueueService.markCompleted(operationId: operation.id)
            return
        }

        guard let ownerId = payload.ownerId else {
            await operationQueueService.quarantineOperation(
                operationId: operation.id,
                error: "Recipe delete replay missing owner identity"
            )
            return
        }

        guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }
        await operationQueueService.markInProgress(operationId: operation.id)

        var privateDeleteSucceeded = true
        var publicDeleteSucceeded = true
        var tombstoneSaveError: Error?

        let deletionRecipe = Recipe(
            id: payload.recipeId,
            title: "Deleted Recipe",
            ingredients: [],
            steps: [],
            visibility: payload.visibility,
            ownerId: ownerId,
            cloudRecordName: payload.cloudRecordName
        )
        do {
            try await externalShareService.removeShareMetadata(for: deletionRecipe)
        } catch {
            publicDeleteSucceeded = false
        }

        guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }

        do {
            try await recipeCloudService.saveDeletedRecipeTombstone(
                DeletedRecipeTombstone(
                    recipeId: payload.recipeId,
                    ownerId: ownerId,
                    cloudRecordName: payload.cloudRecordName,
                    sourceDeviceId: payload.sourceDeviceId
                )
            )
        } catch {
            tombstoneSaveError = error
        }

        guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }

        guard RecipeDeletionSyncPolicy.canDeleteActiveRecords(tombstoneSaveError: tombstoneSaveError) else {
            throw tombstoneSaveError ?? RepositoryError.saveFailed
        }

        if payload.hadImage {
            await deleteRecipeImageFromPrivate(deletionRecipe)
            guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }
            if payload.visibility == .publicRecipe {
                await deleteRecipeImageFromPublic(deletionRecipe)
                guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }
            }
        }

        if let cloudRecordName = payload.cloudRecordName {
            let deletionRecipe = Recipe(
                id: payload.recipeId,
                title: "Deleted Recipe",
                ingredients: [],
                steps: [],
                ownerId: ownerId,
                cloudRecordName: cloudRecordName
            )
            do {
                try await recipeCloudService.deleteRecipe(deletionRecipe)
            } catch {
                privateDeleteSucceeded = false
            }
            guard await authorizeRecipeReplay(operation, entityOwnerId: ownerId) else { return }
        }

        do {
            try await recipeCloudService.deletePublicRecipe(
                recipeId: payload.recipeId,
                ownerID: ownerId
            )
        } catch {
            publicDeleteSucceeded = false
        }

        if privateDeleteSucceeded, publicDeleteSucceeded {
            await operationQueueService.markCompleted(operationId: operation.id)
        } else {
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Recipe delete replay incomplete"
            )
        }
    }

    func authorizeRecipeReplay(
        _ operation: SyncOperation,
        entityOwnerId: UUID
    ) async -> Bool {
        let currentScope = await MainActor.run {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: entityOwnerId)
        }
        switch SyncOperationAccountPolicy.decision(
            operation: operation,
            entityOwnerId: entityOwnerId,
            currentScope: currentScope
        ) {
        case .allowed:
            return true
        case .migrateLegacy:
            guard let currentScope else { return false }
            guard let migrated = await operationQueueService.bindLegacyOperation(
                operationId: operation.id,
                scope: currentScope
            ), migrated.ownerId == currentScope.ownerId,
               migrated.accountRevision == currentScope.revision else {
                return false
            }
            return true
        case .deferred:
            return false
        case .reject:
            await operationQueueService.quarantineOperation(
                operationId: operation.id,
                error: "Recipe operation belongs to another account generation"
            )
            return false
        }
    }

    func authorizeRecipeReplay(
        operationID: UUID,
        entityOwnerId: UUID
    ) async -> Bool {
        guard let operation = await operationQueueService.getOperation(operationId: operationID) else {
            return false
        }
        return await authorizeRecipeReplay(operation, entityOwnerId: entityOwnerId)
    }

    /// Retry syncing recipes that failed previously
    func retryPendingSyncs() async {
        let hasPendingPublicMigration = !loadPendingPublicRecipeMigrationIDs().isEmpty ||
            !UserDefaults.standard.bool(forKey: publicRecipeMigrationCompletedKey)
        let hasPendingPublicSearchMetadataMigration = !UserDefaults.standard.bool(forKey: publicRecipeSearchMetadataMigrationAttemptedKey)
        guard !self.pendingSyncRecipes.isEmpty ||
            hasPendingPublicMigration ||
            hasPendingPublicSearchMetadataMigration else { return }

        logger.info("Retrying sync for \(self.pendingSyncRecipes.count) pending recipes")

        // Check if CloudKit is available first
        let isAvailable = await cloudKitCore.isAvailable()
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
                await self.syncRecipeToCloudKit(recipe, cloudKitCore: self.cloudKitCore, recipeCloudService: self.recipeCloudService)
            } catch {
                logger.error("Error fetching recipe for retry sync: \(error.localizedDescription)")
            }
        }

        if hasPendingPublicMigration {
            await migratePublicRecipesToPublicDatabase()
        }

        if hasPendingPublicSearchMetadataMigration {
            await migratePublicRecipeSearchMetadata()
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

#if DEBUG
extension RecipeRepository {
    func replayRecipeUpsertOperationForTesting(_ operation: SyncOperation) async {
        await replayRecipeUpsertOperation(operation)
    }
}
#endif
