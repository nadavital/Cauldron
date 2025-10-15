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
    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "DeletedRecipeRepository")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Mark a recipe as deleted (create tombstone)
    func markAsDeleted(recipeId: UUID, cloudRecordName: String?) async throws {
        let context = ModelContext(modelContainer)

        // Check if already marked as deleted (fetch all and check manually since no unique constraint)
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let existing = try context.fetch(descriptor).first { $0.recipeId == recipeId }

        if existing != nil {
            logger.info("Recipe \(recipeId) already marked as deleted")
            return
        }

        // Create tombstone
        let tombstone = DeletedRecipeModel(
            recipeId: recipeId,
            deletedAt: Date(),
            cloudRecordName: cloudRecordName
        )
        context.insert(tombstone)
        try context.save()

        logger.info("Marked recipe \(recipeId) as deleted")
    }

    /// Check if a recipe has been deleted
    func isDeleted(recipeId: UUID) async throws -> Bool {
        let context = ModelContext(modelContainer)

        // Fetch all tombstones and check manually since CloudKit doesn't support unique constraints
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)

        return tombstones.contains { $0.recipeId == recipeId }
    }

    /// Remove deletion tombstone (e.g., if user re-adds the recipe)
    func unmarkAsDeleted(recipeId: UUID) async throws {
        let context = ModelContext(modelContainer)

        // Fetch all and find matching tombstone
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)

        var deleted = false
        for tombstone in tombstones where tombstone.recipeId == recipeId {
            context.delete(tombstone)
            deleted = true
        }

        if deleted {
            try context.save()
            logger.info("Removed deletion tombstone for recipe \(recipeId)")
        }
    }

    /// Clean up old tombstones (older than 30 days)
    func cleanupOldTombstones() async throws {
        let context = ModelContext(modelContainer)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)

        // Fetch all and filter manually
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let allTombstones = try context.fetch(descriptor)

        let oldTombstones = allTombstones.filter { tombstone in
            guard let deletedAt = tombstone.deletedAt else { return false }
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
    func fetchAllDeletedRecipeIds() async throws -> [UUID] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<DeletedRecipeModel>()
        let tombstones = try context.fetch(descriptor)
        return tombstones.compactMap { $0.recipeId }
    }
}
