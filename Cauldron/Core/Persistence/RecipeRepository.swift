//
//  RecipeRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData
import os

/// Thread-safe repository for Recipe operations
actor RecipeRepository {
    private let modelContainer: ModelContainer
    private let cloudKitService: CloudKitService
    private let deletedRecipeRepository: DeletedRecipeRepository
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeRepository")

    // Track recipes pending sync
    private var pendingSyncRecipes = Set<UUID>()
    private var syncRetryTask: Task<Void, Never>?

    init(modelContainer: ModelContainer, cloudKitService: CloudKitService, deletedRecipeRepository: DeletedRecipeRepository) {
        self.modelContainer = modelContainer
        self.cloudKitService = cloudKitService
        self.deletedRecipeRepository = deletedRecipeRepository

        // Start retry mechanism for failed syncs
        startSyncRetryTask()
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
                createdAt: recipe.createdAt,
                updatedAt: recipe.updatedAt
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

        // If visibility is friends-only or public, also copy to PUBLIC database for sharing
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
        model.ownerId = recipe.ownerId  // Preserve owner ID
        model.updatedAt = Date()

        // Log image filename being saved
        if let imageFilename = recipe.imageURL?.lastPathComponent {
            AppLogger.general.debug("💾 Saving recipe '\(recipe.title)' with image filename: \(imageFilename)")
        } else {
            AppLogger.general.debug("💾 Saving recipe '\(recipe.title)' with NO image")
        }

        try context.save()

        // Immediately sync to CloudKit
        await syncRecipeToCloudKit(recipe, cloudKitService: cloudKitService)

        // Update PUBLIC database copy if visibility changed
        await syncRecipeToPublicDatabase(recipe, cloudKitService: cloudKitService)
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

        // Mark as deleted (create tombstone) to prevent re-downloading from CloudKit
        try await deletedRecipeRepository.markAsDeleted(
            recipeId: recipe.id,
            cloudRecordName: recipe.cloudRecordName
        )

        // Remove from pending sync if it was there
        pendingSyncRecipes.remove(id)

        // Immediately delete from CloudKit
        await deleteRecipeFromCloudKit(recipe, cloudKitService: cloudKitService)

        // Also delete from PUBLIC database if it was shared
        await deleteRecipeFromPublicDatabase(recipe, cloudKitService: cloudKitService)

        logger.info("Deleted recipe and created tombstone: \(recipe.title)")
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
        // Only sync if visibility is friends-only or public
        guard recipe.visibility != .privateRecipe else {
            // If recipe was made private, delete from PUBLIC database
            await deleteRecipeFromPublicDatabase(recipe, cloudKitService: cloudKitService)
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
