//
//  CloudKitService+Recipes.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os
#if canImport(UIKit)
import UIKit
#endif

extension CloudKitService {
    // MARK: - Recipes
    
    /// Save recipe to CloudKit
    /// ALL recipes go to PRIVATE database (for owner's backup/sync)
    /// Public recipes ALSO go to PUBLIC database (for sharing/discovery) - handled separately
    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        // ALL recipes go to PRIVATE database in custom zone for owner's backup
        // This ensures recipes (and their images) survive app reinstalls
        let db = try getPrivateDatabase()
        let zone = try await ensureCustomZone()
        let zoneID = zone.zoneID

        // Create record ID in custom zone
        let recordID: CKRecord.ID
        if let cloudRecordName = recipe.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: zoneID)
        }

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: recipeRecordType, recordID: recordID)
            logger.info("Creating new record in CloudKit: \(recipe.title)")
        } catch {
            // Other error, rethrow
            logger.error("Error fetching existing record: \(error.localizedDescription)")
            throw error
        }

        // Update/set all fields
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        record["ownerId"] = ownerId.uuidString as CKRecordValue
        record["title"] = recipe.title as CKRecordValue
        record["visibility"] = recipe.visibility.rawValue as CKRecordValue

        // Encode complex data as JSON
        let encoder = JSONEncoder()
        if let ingredientsData = try? encoder.encode(recipe.ingredients) {
            record["ingredientsData"] = ingredientsData as CKRecordValue
        }
        if let stepsData = try? encoder.encode(recipe.steps) {
            record["stepsData"] = stepsData as CKRecordValue
        }
        if let tagsData = try? encoder.encode(recipe.tags) {
            record["tagsData"] = tagsData as CKRecordValue
        }
        
        // Add searchable tags for server-side search
        let searchableTags = recipe.tags.map { $0.name }
        if !searchableTags.isEmpty {
            record["searchableTags"] = searchableTags as CKRecordValue
        }

        record["yields"] = recipe.yields as CKRecordValue
        if let totalMinutes = recipe.totalMinutes {
            record["totalMinutes"] = totalMinutes as CKRecordValue
        }
        record["createdAt"] = recipe.createdAt as CKRecordValue
        record["updatedAt"] = recipe.updatedAt as CKRecordValue

        // Related Recipes - always save (even empty array) to allow clearing
        if let relatedIdsData = try? encoder.encode(recipe.relatedRecipeIds) {
            record["relatedRecipeIdsData"] = relatedIdsData as CKRecordValue
        }

        // Attribution fields for recipe sync
        if let originalRecipeId = recipe.originalRecipeId {
            record["originalRecipeId"] = originalRecipeId.uuidString as CKRecordValue
        }
        if let originalCreatorId = recipe.originalCreatorId {
            record["originalCreatorId"] = originalCreatorId.uuidString as CKRecordValue
        }
        if let originalCreatorName = recipe.originalCreatorName {
            record["originalCreatorName"] = originalCreatorName as CKRecordValue
        }
        if let savedAt = recipe.savedAt {
            record["savedAt"] = savedAt as CKRecordValue
        }
        if let notes = recipe.notes {
            record["notes"] = notes as CKRecordValue
        }

        // Preview status (for local-only preview recipes)
        record["isPreview"] = recipe.isPreview as CKRecordValue

        // Note: Image asset is uploaded separately via uploadImageAsset()
        // We preserve existing imageAsset and imageModifiedAt if they exist
        // This allows recipe data sync to happen independently from image sync

        do {
            _ = try await db.save(record)
        } catch let error as CKError {
            logger.error("❌ CloudKit save failed for '\(recipe.title)': \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Save recipe to public database for external sharing
    /// - Parameter recipe: The recipe to save to public database
    /// - Returns: The CloudKit record name
    func saveRecipeToPublicDatabase(_ recipe: Recipe) async throws -> String {
        logger.info("📤 Saving recipe '\(recipe.title)' to CloudKit public database")

        let db = try getPublicDatabase()

        // Create record ID in public database's default zone
        // Use recipe UUID as record name for easy lookup
        let recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: .default)

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing public record: \(recipe.title)")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: recipeRecordType, recordID: recordID)
            logger.info("Creating new public record: \(recipe.title)")
        } catch {
            // Other error, rethrow
            logger.error("Error fetching existing public record: \(error.localizedDescription)")
            throw error
        }

        // Update/set all fields (same as private database save)
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        record["ownerId"] = (recipe.ownerId?.uuidString ?? "") as CKRecordValue
        record["title"] = recipe.title as CKRecordValue
        record["visibility"] = recipe.visibility.rawValue as CKRecordValue

        // Encode complex data as JSON
        let encoder = JSONEncoder()
        if let ingredientsData = try? encoder.encode(recipe.ingredients) {
            record["ingredientsData"] = ingredientsData as CKRecordValue
        }
        if let stepsData = try? encoder.encode(recipe.steps) {
            record["stepsData"] = stepsData as CKRecordValue
        }
        if let tagsData = try? encoder.encode(recipe.tags) {
            record["tagsData"] = tagsData as CKRecordValue
        }
        
        // Add searchable tags for server-side search
        let searchableTags = recipe.tags.map { $0.name }
        if !searchableTags.isEmpty {
            record["searchableTags"] = searchableTags as CKRecordValue
        }

        record["yields"] = recipe.yields as CKRecordValue
        if let totalMinutes = recipe.totalMinutes {
            record["totalMinutes"] = totalMinutes as CKRecordValue
        }
        record["createdAt"] = recipe.createdAt as CKRecordValue
        record["updatedAt"] = recipe.updatedAt as CKRecordValue

        // Related Recipes - always save (even empty array) to allow clearing
        if let relatedIdsData = try? encoder.encode(recipe.relatedRecipeIds) {
            record["relatedRecipeIdsData"] = relatedIdsData as CKRecordValue
        }

        // Attribution fields
        if let originalRecipeId = recipe.originalRecipeId {
            record["originalRecipeId"] = originalRecipeId.uuidString as CKRecordValue
        }
        if let originalCreatorId = recipe.originalCreatorId {
            record["originalCreatorId"] = originalCreatorId.uuidString as CKRecordValue
        }
        if let originalCreatorName = recipe.originalCreatorName {
            record["originalCreatorName"] = originalCreatorName as CKRecordValue
        }

        // Preview status (for local-only preview recipes)
        record["isPreview"] = recipe.isPreview as CKRecordValue

        // Save to public database
        do {
            let savedRecord = try await db.save(record)
            logger.info("✅ Recipe '\(recipe.title)' saved to public database")
            return savedRecord.recordID.recordName
        } catch let error as CKError {
            logger.error("❌ CloudKit public save failed for '\(recipe.title)': \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch user's recipes from CloudKit
    func fetchUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
        let query = CKQuery(recordType: recipeRecordType, predicate: predicate)
        
        let db = try getPrivateDatabase()
        let results = try await db.records(matching: query)
        
        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let recipe = try? recipeFromRecord(record) {
                    recipes.append(recipe)
                }
            }
        }
        
        return recipes
    }
    
    /// Fetch public recipes
    func fetchPublicRecipes(limit: Int = 50) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: recipeRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let db = try getPublicDatabase()
        let results = try await db.records(matching: query, resultsLimit: limit)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let recipe = try? recipeFromRecord(record) {
                    recipes.append(recipe)
                }
            }
        }

        return recipes
    }

    /// Fetch public recipes for a specific user from the public database
    func fetchPublicRecipesForUser(ownerId: UUID) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "ownerId == %@ AND visibility == %@",
                                   ownerId.uuidString,
                                   RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: recipeRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let db = try getPublicDatabase()
        let results = try await db.records(matching: query)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let recipe = try? recipeFromRecord(record) {
                    recipes.append(recipe)
                }
            }
        }

        return recipes
    }

    /// Fetch a single public recipe by ID
    func fetchPublicRecipe(id: UUID) async throws -> Recipe? {
        logger.info("🔍 Fetching public recipe with ID: \(id.uuidString)")
        
        let db = try getPublicDatabase()
        
        // 1. Try fetching directly by Record ID (fastest and most reliable)
        // We use the UUID string as the record name in copyRecipeToPublic
        let recordID = CKRecord.ID(recordName: id.uuidString)
        
        do {
            let record = try await db.record(for: recordID)
            logger.info("✅ Found public recipe by Record ID: \(record.recordID.recordName)")
            return try? recipeFromRecord(record)
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("ℹ️ Record not found by ID, trying query fallback...")
            } else {
                logger.error("❌ Error fetching by ID: \(error.localizedDescription)")
                // Don't throw yet, try query
            }
        } catch {
            logger.error("❌ Unexpected error fetching by ID: \(error.localizedDescription)")
        }
        
        // 2. Fallback: Query by recipeId field (slower, depends on indexing)
        let predicate = NSPredicate(format: "recipeId == %@", id.uuidString)
        let query = CKQuery(recordType: recipeRecordType, predicate: predicate)
        
        do {
            let results = try await db.records(matching: query, resultsLimit: 1)
            
            for (_, result) in results.matchResults {
                switch result {
                case .success(let record):
                    logger.info("✅ Found public recipe by Query: \(record.recordID.recordName)")
                    return try? recipeFromRecord(record)
                case .failure(let error):
                    logger.error("❌ Error fetching record from query: \(error.localizedDescription)")
                }
            }
            
            logger.warning("⚠️ No public recipe found with ID: \(id.uuidString)")
            return nil
        } catch {
            logger.error("❌ Query failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Delete recipe from CloudKit
    func deleteRecipe(_ recipe: Recipe) async throws {
        guard let cloudRecordName = recipe.cloudRecordName else {
            logger.warning("Cannot delete recipe from CloudKit: no cloud record name")
            return
        }

        let recordID = CKRecord.ID(recordName: cloudRecordName)
        // Always delete from private database (where the master copy lives)
        let database = try getPrivateDatabase()

        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("Deleted recipe from CloudKit private database: \(recipe.title)")
        } catch let error as CKError {
            if error.code == .unknownItem {
                // Recipe doesn't exist in CloudKit - that's okay
                logger.info("Recipe not found in CloudKit (already deleted): \(recipe.title)")
                return
            }
            throw error
        }
    }
    
    /// Sync all recipes for a user - fetch from CloudKit and return for local merge
    func syncUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        // Syncing recipes from CloudKit (don't log routine operations)

        // Check account status first
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            logger.error("CloudKit account not available: \(accountStatus)")
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        // Ensure custom zone exists
        let zone = try await ensureCustomZone()
        // Using custom zone for sync (don't log routine operations)

        var allRecipes: [Recipe] = []
        let db = try getPrivateDatabase()

        // Fetch all recipes from the custom zone (they're all in private database now)
        do {
            let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
            let query = CKQuery(recordType: recipeRecordType, predicate: predicate)

            // Fetch from custom zone
            let results = try await db.records(matching: query, inZoneWith: zone.zoneID)

            for (_, result) in results.matchResults {
                if let record = try? result.get() {
                    do {
                        let recipe = try recipeFromRecord(record)
                        allRecipes.append(recipe)
                    } catch {
                        logger.error("Failed to decode recipe from record: \(error.localizedDescription)")
                    }
                }
            }

            // Fetched recipes from CloudKit (don't log routine operations)
        } catch let error as CKError {
            logger.error("❌ Failed to fetch recipes from CloudKit: \(error.localizedDescription)")
            logger.error("Error code: \(error.code.rawValue)")
            throw error
        }

        // Return recipes (don't log count - routine operation)
        return allRecipes
    }
    
    func recipeFromRecord(_ record: CKRecord) throws -> Recipe {
        guard let recipeIdString = record["recipeId"] as? String,
              let recipeId = UUID(uuidString: recipeIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let title = record["title"] as? String,
              let visibilityString = record["visibility"] as? String,
              let visibility = RecipeVisibility(rawValue: visibilityString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        let decoder = JSONDecoder()

        let ingredients: [Ingredient]
        if let ingredientsData = record["ingredientsData"] as? Data {
            ingredients = (try? decoder.decode([Ingredient].self, from: ingredientsData)) ?? []
        } else {
            ingredients = []
        }

        let steps: [CookStep]
        if let stepsData = record["stepsData"] as? Data {
            steps = (try? decoder.decode([CookStep].self, from: stepsData)) ?? []
        } else {
            steps = []
        }

        let tags: [Tag]
        if let tagsData = record["tagsData"] as? Data {
            tags = (try? decoder.decode([Tag].self, from: tagsData)) ?? []
        } else {
            tags = []
        }

        let yields = record["yields"] as? String ?? "4 servings"
        let totalMinutes = record["totalMinutes"] as? Int

        // Decode related recipes
        let relatedRecipeIds: [UUID]
        if let relatedIdsData = record["relatedRecipeIdsData"] as? Data {
            relatedRecipeIds = (try? decoder.decode([UUID].self, from: relatedIdsData)) ?? []
        } else {
            relatedRecipeIds = []
        }

        // Cloud image metadata (optional)
        let cloudImageRecordName: String? = (record["imageAsset"] as? CKAsset) != nil ? record.recordID.recordName : nil
        let imageModifiedAt = record["imageModifiedAt"] as? Date

        // IMPORTANT: Do NOT extract imageURL from CloudKit asset's fileURL!
        // The asset.fileURL is a temporary CloudKit cache path with version suffixes.
        // The imageURL should only be set AFTER downloading and saving the image locally.
        // During sync, RecipeSyncService.downloadImageIfNeeded() will handle downloading
        // and setting the correct local imageURL.
        let imageURL: URL? = nil

        // Attribution fields (optional)
        let originalRecipeId: UUID? = {
            if let idString = record["originalRecipeId"] as? String {
                return UUID(uuidString: idString)
            }
            return nil
        }()
        let originalCreatorId: UUID? = {
            if let idString = record["originalCreatorId"] as? String {
                return UUID(uuidString: idString)
            }
            return nil
        }()
        let originalCreatorName = record["originalCreatorName"] as? String
        let savedAt = record["savedAt"] as? Date
        let notes = record["notes"] as? String

        // Preview status - defaults to false if not present (for backward compatibility)
        let isPreview = record["isPreview"] as? Bool ?? false

        return Recipe(
            id: recipeId,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: notes,
            imageURL: imageURL,
            isFavorite: false,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: record.recordID.recordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }

    // MARK: - Public Recipe Sharing (NEW Architecture)

    /// Copy recipe to PUBLIC database when visibility != .private
    /// This makes the recipe discoverable by everyone
    func copyRecipeToPublic(_ recipe: Recipe) async throws {

        // Only copy if visibility is public
        guard recipe.visibility != .privateRecipe else {
            logger.info("Recipe is private, skipping PUBLIC database copy")
            return
        }

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: recipe.id.uuidString)

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing record in PUBLIC database: \(recipe.title)")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: sharedRecipeRecordType, recordID: recordID)
            logger.info("Creating new record in PUBLIC database: \(recipe.title)")
        } catch {
            // Other error, rethrow
            logger.error("Error fetching existing PUBLIC record: \(error.localizedDescription)")
            throw error
        }

        // Store all recipe data in PUBLIC database
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        guard let ownerId = recipe.ownerId else {
            logger.error("Cannot copy recipe to PUBLIC: missing ownerId")
            throw CloudKitError.invalidRecord
        }
        record["ownerId"] = ownerId.uuidString as CKRecordValue
        record["visibility"] = recipe.visibility.rawValue as CKRecordValue
        record["title"] = recipe.title as CKRecordValue

        // Encode complex data as JSON
        let encoder = JSONEncoder()
        if let ingredientsData = try? encoder.encode(recipe.ingredients) {
            record["ingredientsData"] = ingredientsData as CKRecordValue
        }
        if let stepsData = try? encoder.encode(recipe.steps) {
            record["stepsData"] = stepsData as CKRecordValue
        }
        if let tagsData = try? encoder.encode(recipe.tags) {
            record["tagsData"] = tagsData as CKRecordValue
        }

        record["yields"] = recipe.yields as CKRecordValue
        if let totalMinutes = recipe.totalMinutes {
            record["totalMinutes"] = totalMinutes as CKRecordValue
        }
        record["createdAt"] = recipe.createdAt as CKRecordValue
        record["updatedAt"] = recipe.updatedAt as CKRecordValue

        // Related Recipes - always save (even empty array) to allow clearing
        if let relatedIdsData = try? encoder.encode(recipe.relatedRecipeIds) {
            record["relatedRecipeIdsData"] = relatedIdsData as CKRecordValue
        }

        // Attribution fields for recipe sync (optional - only present on copied recipes)
        if let originalRecipeId = recipe.originalRecipeId {
            record["originalRecipeId"] = originalRecipeId.uuidString as CKRecordValue
        }
        if let originalCreatorId = recipe.originalCreatorId {
            record["originalCreatorId"] = originalCreatorId.uuidString as CKRecordValue
        }
        if let originalCreatorName = recipe.originalCreatorName {
            record["originalCreatorName"] = originalCreatorName as CKRecordValue
        }
        if let savedAt = recipe.savedAt {
            record["savedAt"] = savedAt as CKRecordValue
        }
        if let notes = recipe.notes {
            record["notes"] = notes as CKRecordValue
        }

        // Preview status (for local-only preview recipes)
        record["isPreview"] = recipe.isPreview as CKRecordValue

        _ = try await db.save(record)
        logger.info("✅ Successfully copied recipe to PUBLIC database")
    }

    /// Fetch recipe from PUBLIC database
    func fetchPublicRecipe(recipeId: UUID, ownerId: UUID) async throws -> Recipe {
        logger.info("📥 Fetching public recipe: \(recipeId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: recipeId.uuidString)

        do {
            let record = try await db.record(for: recordID)
            let recipe = try recipeFromRecord(record)
            logger.info("✅ Fetched public recipe: \(recipe.title)")
            return recipe
        } catch {
            logger.error("Failed to fetch public recipe: \(error.localizedDescription)")
            throw error
        }
    }

    /// Query shared recipes by visibility and optional owner IDs
    func querySharedRecipes(ownerIds: [UUID]?, visibility: RecipeVisibility) async throws -> [Recipe] {
        // Querying shared recipes (don't log routine operations)

        let db = try getPublicDatabase()

        // Build predicate
        let predicate: NSPredicate
        if let ownerIds = ownerIds, !ownerIds.isEmpty {
            let ownerIdStrings = ownerIds.map { $0.uuidString }
            predicate = NSPredicate(
                format: "ownerId IN %@ AND visibility == %@",
                ownerIdStrings,
                visibility.rawValue
            )
        } else {
            predicate = NSPredicate(format: "visibility == %@", visibility.rawValue)
        }

        let query = CKQuery(recordType: sharedRecipeRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query, resultsLimit: 100)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        // Return shared recipes (don't log routine operations)
        return recipes
    }
    
    /// Delete recipe from PUBLIC database
    func deletePublicRecipe(recipeId: UUID, ownerId: UUID) async throws {
        logger.info("🗑️ Deleting recipe from PUBLIC database: \(recipeId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: recipeId.uuidString)

        do {
            try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted recipe from PUBLIC database")
        } catch let error as CKError where error.code == .unknownItem {
            // Recipe doesn't exist in PUBLIC database - that's okay
            logger.info("Recipe not found in PUBLIC database (already deleted or was private)")
        }
    }
    
    // MARK: - Image Assets

    /// Upload image as CKAsset to CloudKit
    /// - Parameters:
    ///   - recipeId: The recipe ID this image belongs to
    ///   - imageData: The image data to upload
    ///   - database: The database to upload to (private or public)
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageAsset(recipeId: UUID, imageData: Data, to database: CKDatabase) async throws -> String {
        // Optimize image before upload
        let optimizedData = try await optimizeImageForCloudKit(imageData)

        // Create temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(recipeId.uuidString)
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create CKAsset
        let asset = CKAsset(fileURL: tempURL)

        // Find existing recipe record to attach asset to
        // For PRIVATE database, we need to use the custom zone
        let recordID: CKRecord.ID
        if database == self.container?.privateCloudDatabase {
            // PRIVATE database - use custom zone
            let zone = try await ensureCustomZone()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zone.zoneID)
        } else {
            // PUBLIC database - use default zone
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        }

        do {
            // Fetch existing record
            let record = try await database.record(for: recordID)

            // Add image asset and modification timestamp
            record["imageAsset"] = asset
            record["imageModifiedAt"] = Date() as CKRecordValue

            // Save updated record
            let savedRecord = try await database.save(record)
            return savedRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.error("Recipe record not found in CloudKit: \(recipeId)")
                throw CloudKitError.invalidRecord
            } else if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download image asset from CloudKit
    /// - Parameters:
    ///   - recipeId: The recipe ID to download image for
    ///   - database: The database to download from (private or public)
    /// - Returns: The image data, or nil if no image exists
    func downloadImageAsset(recipeId: UUID, from database: CKDatabase) async throws -> Data? {

        // For PRIVATE database, we need to use the custom zone
        let recordID: CKRecord.ID
        if database == self.container?.privateCloudDatabase {
            // PRIVATE database - use custom zone
            let zone = try await ensureCustomZone()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zone.zoneID)
        } else {
            // PUBLIC database - use default zone
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        }

        do {
            let record = try await database.record(for: recordID)

            guard let asset = record["imageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    /// Delete image asset from CloudKit
    /// - Parameters:
    ///   - recipeId: The recipe ID to delete image for
    ///   - database: The database to delete from (private or public)
    func deleteImageAsset(recipeId: UUID, from database: CKDatabase) async throws {
        logger.info("🗑️ Deleting image asset for recipe: \(recipeId)")

        // For PRIVATE database, we need to use the custom zone
        let recordID: CKRecord.ID
        if database == self.container?.privateCloudDatabase {
            // PRIVATE database - use custom zone
            let zone = try await ensureCustomZone()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zone.zoneID)
        } else {
            // PUBLIC database - use default zone
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        }

        do {
            let record = try await database.record(for: recordID)

            // Remove image asset fields
            record["imageAsset"] = nil
            record["imageModifiedAt"] = nil

            _ = try await database.save(record)
            logger.info("✅ Deleted image asset")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Recipe record not found: \(recipeId)")
                return
            }
            throw error
        }
    }

    // MARK: - Popular Recipes

    /// Fetch popular public recipes (for discovery)
    /// - Parameter limit: Maximum number of recipes to return
    /// - Returns: Array of popular public recipes sorted by saveCount
    func fetchPopularPublicRecipes(limit: Int = 20) async throws -> [Recipe] {
        let db = try getPublicDatabase()

        // Query all public recipes
        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: sharedRecipeRecordType, predicate: predicate)
        // Sort by updatedAt as a fallback (saveCount index may not exist)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query, resultsLimit: limit * 2) // Fetch more to account for filtering

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        // Return the recipes (limit applied later after tier boost sorting)
        return Array(recipes.prefix(limit))
    }
}
