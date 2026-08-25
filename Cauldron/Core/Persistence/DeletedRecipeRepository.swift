//
//  DeletedRecipeRepository.swift
//  Cauldron
//
//  Created by Claude on 10/14/25.
//

import Foundation
import SwiftData
import os

/// Repository for tracking deleted recipes (tombstones)
actor DeletedRecipeRepository {
    nonisolated static let legacyOwnerMigrationVersion = 1
    nonisolated static let legacyOwnerMigrationVersionKey = "deletedRecipeOwnerMigrationVersion"
    nonisolated static let legacyOwnerMigrationOwnerKey = "deletedRecipeOwnerMigrationOwner"

    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "DeletedRecipeRepository")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Mark a recipe as deleted (create tombstone)
    func markAsDeleted(
        recipeId: UUID,
        ownerId: UUID,
        cloudRecordName: String?,
        deletedAt: Date = Date(),
        sourceDeviceId: String? = SyncDeviceIdentifier.current()
    ) async throws {
        let context = ModelContext(modelContainer)

        // Check if already marked as deleted (fetch all and check manually since no unique constraint)
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let existing = try context.fetch(descriptor).first {
            $0.recipeId == recipeId && $0.ownerId == ownerId
        }

        if let existing {
            if existing.deletedAt == nil || existing.deletedAt! <= deletedAt {
                existing.deletedAt = deletedAt
                existing.cloudRecordName = existing.cloudRecordName ?? cloudRecordName
                existing.sourceDeviceId = existing.sourceDeviceId ?? sourceDeviceId
                try context.save()
            }
            logger.info("Recipe \(recipeId) already marked as deleted")
            return
        }

        // Create tombstone
        let tombstone = DeletedRecipeModel(
            recipeId: recipeId,
            ownerId: ownerId,
            deletedAt: deletedAt,
            cloudRecordName: cloudRecordName,
            sourceDeviceId: sourceDeviceId
        )
        context.insert(tombstone)
        try context.save()

        logger.info("Marked recipe \(recipeId) as deleted")
    }

    /// Check if a recipe has been deleted
    func isDeleted(recipeId: UUID, ownerId: UUID) async throws -> Bool {
        let context = ModelContext(modelContainer)

        // Fetch all tombstones and check manually since CloudKit doesn't support unique constraints
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)

        return tombstones.contains { $0.recipeId == recipeId && $0.ownerId == ownerId }
    }

    /// Remove deletion tombstone (e.g., if user re-adds the recipe)
    func unmarkAsDeleted(recipeId: UUID, ownerId: UUID) async throws {
        let context = ModelContext(modelContainer)

        // Fetch all and find matching tombstone
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)

        var deleted = false
        for tombstone in tombstones where tombstone.recipeId == recipeId && tombstone.ownerId == ownerId {
            context.delete(tombstone)
            deleted = true
        }

        if deleted {
            try context.save()
            logger.info("Removed deletion tombstone for recipe \(recipeId)")
        }
    }

    /// Clean up old tombstones (older than 30 days)
    func cleanupOldTombstones(ownerId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        // Fetch all and filter manually
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let allTombstones = try context.fetch(descriptor)

        let oldTombstones = allTombstones.filter { tombstone in
            guard tombstone.ownerId == ownerId, let deletedAt = tombstone.deletedAt else { return false }
            return deletedAt < thirtyDaysAgo
        }

        for tombstone in oldTombstones {
            context.delete(tombstone)
        }

        if !oldTombstones.isEmpty {
            try context.save()
            logger.info("Cleaned up \(oldTombstones.count) old deletion tombstones")
        }
    }

    /// Get all deleted recipe IDs (for debugging)
    func fetchAllDeletedRecipeIds(ownerId: UUID) async throws -> [UUID] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)
        return tombstones.compactMap { $0.ownerId == ownerId ? $0.recipeId : nil }
    }

    /// Adopts ownerless tombstones from pre-account-scoping stores exactly once.
    /// A global version marker is intentional: after any account boundary, a
    /// retained store's legacy rows must never be re-adopted by the next user.
    func migrateLegacyOwnerlessTombstones(
        to ownerId: UUID,
        defaults: UserDefaults = .standard
    ) async throws {
        guard defaults.integer(forKey: Self.legacyOwnerMigrationVersionKey)
                < Self.legacyOwnerMigrationVersion else { return }

        let context = ModelContext(modelContainer)
        let tombstones = try context.fetch(FetchDescriptor<DeletedRecipeModel>())
        var ownedByRecipeID: [UUID: DeletedRecipeModel] = [:]
        var changed = false
        for tombstone in tombstones where tombstone.ownerId == ownerId {
            guard let recipeId = tombstone.recipeId else { continue }
            if let existing = ownedByRecipeID[recipeId] {
                merge(tombstone, into: existing)
                context.delete(tombstone)
                changed = true
            } else {
                ownedByRecipeID[recipeId] = tombstone
            }
        }

        for tombstone in tombstones where tombstone.ownerId == nil {
            if let recipeId = tombstone.recipeId,
               let existing = ownedByRecipeID[recipeId] {
                merge(tombstone, into: existing)
                context.delete(tombstone)
            } else {
                tombstone.ownerId = ownerId
                if let recipeId = tombstone.recipeId {
                    ownedByRecipeID[recipeId] = tombstone
                }
            }
            changed = true
        }
        if changed {
            try context.save()
        }
        defaults.set(Self.legacyOwnerMigrationVersion, forKey: Self.legacyOwnerMigrationVersionKey)
        defaults.set(ownerId.uuidString, forKey: Self.legacyOwnerMigrationOwnerKey)
    }

    private func merge(_ source: DeletedRecipeModel, into destination: DeletedRecipeModel) {
        if destination.deletedAt == nil || (source.deletedAt ?? .distantPast) > (destination.deletedAt ?? .distantPast) {
            destination.deletedAt = source.deletedAt
        }
        destination.cloudRecordName = destination.cloudRecordName ?? source.cloudRecordName
        destination.sourceDeviceId = destination.sourceDeviceId ?? source.sourceDeviceId
    }
}
