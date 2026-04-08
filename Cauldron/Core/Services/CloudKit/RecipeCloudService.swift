//
//  RecipeCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for recipe operations.
//

import Foundation
import CloudKit
import os

/// CloudKit service for recipe-related operations.
///
/// Handles:
/// - Saving/fetching recipes to/from private database
/// - Managing public recipe copies for sharing
/// - Image asset upload/download for recipes
/// - Recipe search and discovery
actor RecipeCloudService {
    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeCloudService")

    init(core: CloudKitCore) {
        self.core = core
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Private Database Operations

    /// Save recipe to CloudKit private database
    /// ALL recipes go to PRIVATE database (for owner's backup/sync)
    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()

        // Create record ID in custom zone
        let recordID: CKRecord.ID
        if let cloudRecordName = recipe.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName, zoneID: zoneID)
        } else {
            recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: zoneID)
        }

        let record = try await fetchOrCreateRecord(
            in: db,
            recordID: recordID,
            recordType: CloudKitCore.RecordType.recipe
        )

        // Populate record fields
        populateRecipeRecord(record, from: recipe, ownerId: ownerId)

        do {
            _ = try await db.save(record)
        } catch let error as CKError {
            logger.error("❌ CloudKit save failed for '\(recipe.title)': \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetch user's recipes from private database
    func fetchUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.recipe, predicate: predicate)

        let db = try await core.getPrivateDatabase()
        let results = try await db.records(matching: query)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        return recipes
    }

    /// Sync all recipes for a user from CloudKit private database
    func syncUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        let accountStatus = await core.checkAccountStatus()
        guard accountStatus.isAvailable else {
            logger.error("CloudKit account not available: \(accountStatus)")
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        let zoneID = try await core.getCustomZoneID()
        let db = try await core.getPrivateDatabase()

        var allRecipes: [Recipe] = []

        do {
            let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
            let query = CKQuery(recordType: CloudKitCore.RecordType.recipe, predicate: predicate)

            let results = try await db.records(matching: query, inZoneWith: zoneID)

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
        } catch let error as CKError {
            logger.error("❌ Failed to fetch recipes from CloudKit: \(error.localizedDescription)")
            throw error
        }

        return allRecipes
    }

    /// Delete recipe from private database
    func deleteRecipe(_ recipe: Recipe) async throws {
        guard let cloudRecordName = recipe.cloudRecordName else {
            logger.warning("Cannot delete recipe from CloudKit: no cloud record name")
            return
        }

        let recordID = CKRecord.ID(recordName: cloudRecordName)
        let database = try await core.getPrivateDatabase()

        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("Deleted recipe from CloudKit private database: \(recipe.title)")
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Recipe not found in CloudKit (already deleted): \(recipe.title)")
                return
            }
            throw error
        }
    }

    // MARK: - Public Database Operations

    /// Copy recipe to PUBLIC database when visibility != .private
    func copyRecipeToPublic(_ recipe: Recipe) async throws {
        guard recipe.visibility != .privateRecipe else {
            logger.info("Recipe is private, skipping PUBLIC database copy")
            return
        }

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: recipe.id.uuidString)

        let record = try await fetchOrCreateRecord(
            in: db,
            recordID: recordID,
            recordType: CloudKitCore.RecordType.sharedRecipe
        )

        guard let ownerId = recipe.ownerId else {
            logger.error("Cannot copy recipe to PUBLIC: missing ownerId")
            throw CloudKitError.invalidRecord
        }

        populateRecipeRecord(record, from: recipe, ownerId: ownerId)

        _ = try await db.save(record)
        logger.info("✅ Successfully copied recipe to PUBLIC database")
    }

    /// Fetch public recipes
    func fetchPublicRecipes(limit: Int = 50) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: CloudKitCore.RecordType.recipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let db = try await core.getPublicDatabase()
        let results = try await db.records(matching: query, resultsLimit: limit)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        return recipes
    }

    /// Fetch public recipes for a specific user
    func fetchPublicRecipesForUser(ownerId: UUID, includeDerivedCopies: Bool = true) async throws -> [Recipe] {
        let predicate = NSPredicate(format: "ownerId == %@ AND visibility == %@",
                                   ownerId.uuidString,
                                   RecipeVisibility.publicRecipe.rawValue)
        // Use sharedRecipe record type - public recipes are stored in the public database
        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let db = try await core.getPublicDatabase()
        let results = try await db.records(matching: query)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        return filterDerivedCopies(in: recipes, includeDerivedCopies: includeDerivedCopies)
    }

    /// Fetch a single public recipe by ID
    func fetchPublicRecipe(id: UUID) async throws -> Recipe? {
        logger.info("🔍 Fetching public recipe with ID: \(id.uuidString)")

        let db = try await core.getPublicDatabase()

        // 1. Try fetching directly by Record ID (fastest and most reliable)
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
            }
        } catch {
            logger.error("❌ Unexpected error fetching by ID: \(error.localizedDescription)")
        }

        // 2. Fallback: Query by recipeId field
        let predicate = NSPredicate(format: "recipeId == %@", id.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.recipe, predicate: predicate)

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

    /// Query shared recipes by visibility and optional owner IDs
    func querySharedRecipes(
        ownerIds: [UUID]?,
        visibility: RecipeVisibility,
        requiredTag: String? = nil,
        includeDerivedCopies: Bool = true,
        limit: Int = 100
    ) async throws -> [Recipe] {
        let db = try await core.getPublicDatabase()

        let predicate: NSPredicate
        let normalizedTag = requiredTag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasRequiredTag = !(normalizedTag?.isEmpty ?? true)

        if let ownerIds = ownerIds, !ownerIds.isEmpty {
            let ownerIdStrings = ownerIds.map { $0.uuidString }
            if let normalizedTag, hasRequiredTag {
                predicate = NSPredicate(
                    format: "ownerId IN %@ AND visibility == %@ AND ANY searchableTags == %@",
                    ownerIdStrings,
                    visibility.rawValue,
                    normalizedTag
                )
            } else {
                predicate = NSPredicate(
                    format: "ownerId IN %@ AND visibility == %@",
                    ownerIdStrings,
                    visibility.rawValue
                )
            }
        } else {
            if let normalizedTag, hasRequiredTag {
                predicate = NSPredicate(
                    format: "visibility == %@ AND ANY searchableTags == %@",
                    visibility.rawValue,
                    normalizedTag
                )
            } else {
                predicate = NSPredicate(format: "visibility == %@", visibility.rawValue)
            }
        }

        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query, resultsLimit: limit)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        return filterDerivedCopies(in: recipes, includeDerivedCopies: includeDerivedCopies)
    }

    /// Fetch discoverable public recipes for Search tab results.
    ///
    /// Text and category filtering intentionally remain client-side in
    /// `RecipeGroupingService` for richer matching/ranking semantics.
    func fetchDiscoverablePublicRecipes(limit: Int = 200) async throws -> [Recipe] {
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var cursor: CKQueryOperation.Cursor?
        var recipes: [Recipe] = []
        var canonicalGroupIDs = Set<UUID>()
        var fetchedPageCount = 0

        let batchSize = min(max(limit, 100), 200)
        // Keep paging until we gather enough distinct groups, but cap the total
        // query fan-out so one hot recipe cannot trigger an unbounded scan.
        let maxPageCount = 20

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: batchSize)
            } else {
                results = try await db.records(matching: query, resultsLimit: batchSize)
            }

            for (_, result) in results.matchResults {
                guard let record = try? result.get(),
                      let recipe = try? recipeFromRecord(record) else {
                    continue
                }

                recipes.append(recipe)
                if !recipe.isFollowingSourceUpdates {
                    canonicalGroupIDs.insert(discoveryGroupID(for: recipe))
                }
            }

            fetchedPageCount += 1
            cursor = results.queryCursor
        } while cursor != nil && canonicalGroupIDs.count < limit && fetchedPageCount < maxPageCount

        if cursor != nil && canonicalGroupIDs.count < limit {
            logger.warning("Stopped discovery fetch after \(fetchedPageCount) pages with \(canonicalGroupIDs.count) canonical groups")
        }

        return limitRecipesByGroup(recipes, to: limit)
    }

    func fetchPublicRecipesForSearch(
        filterText: String,
        selectedCategories: Set<RecipeCategory>,
        limit: Int = 200
    ) async throws -> [Recipe] {
        let normalizedQuery = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty || !selectedCategories.isEmpty else {
            return try await fetchDiscoverablePublicRecipes(limit: limit)
        }

        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var cursor: CKQueryOperation.Cursor?
        var matchingRecipes: [Recipe] = []
        var canonicalMatchingGroupIDs = Set<UUID>()
        var fetchedPageCount = 0

        let batchSize = min(max(limit, 100), 200)
        let maxPageCount = 20

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: batchSize)
            } else {
                results = try await db.records(matching: query, resultsLimit: batchSize)
            }

            for (_, result) in results.matchResults {
                guard let record = try? result.get(),
                      let recipe = try? recipeFromRecord(record),
                      RecipeGroupingService.matchesSearchFilters(
                        recipe,
                        filterText: normalizedQuery,
                        selectedCategories: selectedCategories
                      ) else {
                    continue
                }

                matchingRecipes.append(recipe)
                if !recipe.isFollowingSourceUpdates {
                    canonicalMatchingGroupIDs.insert(discoveryGroupID(for: recipe))
                }
            }

            fetchedPageCount += 1
            cursor = results.queryCursor
        } while cursor != nil && canonicalMatchingGroupIDs.count < limit && fetchedPageCount < maxPageCount

        if cursor != nil && canonicalMatchingGroupIDs.count < limit {
            logger.warning("Stopped public search fetch after \(fetchedPageCount) pages with \(canonicalMatchingGroupIDs.count) canonical matching groups")
        }

        return limitRecipesByGroup(matchingRecipes, to: limit)
    }

    func resolveCanonicalRelatedRecipeIDs(for recipe: Recipe) async throws -> [UUID] {
        guard recipe.isFollowingSourceUpdates,
              let sourceRecipeId = recipe.originalRecipeId else {
            return recipe.relatedRecipeIds
        }

        do {
            guard let sourceRecipe = try await fetchPublicRecipe(id: sourceRecipeId) else {
                return recipe.relatedRecipeIds
            }

            return sourceRecipe.relatedRecipeIds
        } catch {
            logger.warning("Falling back to embedded related recipe IDs for \(recipe.id): \(error.localizedDescription)")
            return recipe.relatedRecipeIds
        }
    }

    /// Delete recipe from PUBLIC database
    func deletePublicRecipe(recipeId: UUID) async throws {
        logger.info("🗑️ Deleting recipe from PUBLIC database: \(recipeId)")

        let db = try await core.getPublicDatabase()
        let recordID = CKRecord.ID(recordName: recipeId.uuidString)

        do {
            try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted recipe from PUBLIC database")
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Recipe not found in PUBLIC database (already deleted or was private)")
        }
    }

    /// Batch fetch public recipe counts for multiple owner IDs
    func batchFetchPublicRecipeCounts(forOwnerIds ownerIds: [UUID]) async throws -> [UUID: Int] {
        guard !ownerIds.isEmpty else { return [:] }

        let db = try await core.getPublicDatabase()
        let ownerIdStrings = ownerIds.map { $0.uuidString }

        let predicate = NSPredicate(
            format: "ownerId IN %@ AND visibility == %@",
            ownerIdStrings,
            RecipeVisibility.publicRecipe.rawValue
        )
        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)

        let results = try await db.records(matching: query, resultsLimit: 500)

        var counts: [UUID: Int] = [:]
        for ownerId in ownerIds {
            counts[ownerId] = 0
        }

        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record),
               !recipe.isFollowingSourceUpdates,
               let ownerId = recipe.ownerId {
                counts[ownerId, default: 0] += 1
            }
        }

        return counts
    }

    /// Fetch popular public recipes
    func fetchPopularPublicRecipes(limit: Int = 20) async throws -> [Recipe] {
        let db = try await core.getPublicDatabase()

        let predicate = NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue)
        let query = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query, resultsLimit: limit * 2)

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }

        let filteredRecipes = filterDerivedCopies(in: recipes, includeDerivedCopies: false)
        return Array(filteredRecipes.prefix(limit))
    }

    private func filterDerivedCopies(in recipes: [Recipe], includeDerivedCopies: Bool) -> [Recipe] {
        guard !includeDerivedCopies else {
            return recipes
        }

        return recipes.filter { !$0.isFollowingSourceUpdates }
    }

    private func discoveryGroupID(for recipe: Recipe) -> UUID {
        if recipe.isFollowingSourceUpdates, let originalRecipeId = recipe.originalRecipeId {
            return originalRecipeId
        }

        return recipe.id
    }

    private func limitRecipesByGroup(_ recipes: [Recipe], to limit: Int) -> [Recipe] {
        guard limit > 0 else { return [] }

        var canonicalGroupIDs = Set<UUID>()
        for recipe in recipes where !recipe.isFollowingSourceUpdates {
            canonicalGroupIDs.insert(discoveryGroupID(for: recipe))
        }

        var orderedCanonicalGroupIDs: [UUID] = []
        var orderedFallbackGroupIDs: [UUID] = []
        var seenCanonicalGroupIDs = Set<UUID>()
        var seenFallbackGroupIDs = Set<UUID>()
        for recipe in recipes {
            let groupID = discoveryGroupID(for: recipe)

            if canonicalGroupIDs.contains(groupID) {
                if seenCanonicalGroupIDs.insert(groupID).inserted {
                    orderedCanonicalGroupIDs.append(groupID)
                }
            } else if seenFallbackGroupIDs.insert(groupID).inserted {
                orderedFallbackGroupIDs.append(groupID)
            }
        }

        let allowedGroupIDs = Array(
            (orderedCanonicalGroupIDs + orderedFallbackGroupIDs)
                .prefix(limit)
        )
        let allowedGroupIDSet = Set(allowedGroupIDs)

        return recipes.filter { allowedGroupIDSet.contains(discoveryGroupID(for: $0)) }
    }

    // MARK: - Image Assets

    /// Upload image as CKAsset to CloudKit
    func uploadImageAsset(recipeId: UUID, imageData: Data, toPublic: Bool) async throws -> String {
        let optimizedData = try await core.optimizeImageForCloudKit(imageData)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(recipeId.uuidString)
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let asset = CKAsset(fileURL: tempURL)

        let database: CKDatabase
        let recordID: CKRecord.ID

        if toPublic {
            database = try await core.getPublicDatabase()
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        } else {
            database = try await core.getPrivateDatabase()
            let zoneID = try await core.getCustomZoneID()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zoneID)
        }

        do {
            let record = try await database.record(for: recordID)
            record["imageAsset"] = asset
            record["imageModifiedAt"] = Date() as CKRecordValue

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
    func downloadImageAsset(recipeId: UUID, fromPublic: Bool) async throws -> Data? {
        let database: CKDatabase
        let recordID: CKRecord.ID

        if fromPublic {
            database = try await core.getPublicDatabase()
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        } else {
            database = try await core.getPrivateDatabase()
            let zoneID = try await core.getCustomZoneID()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zoneID)
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
    func deleteImageAsset(recipeId: UUID, fromPublic: Bool) async throws {
        logger.info("🗑️ Deleting image asset for recipe: \(recipeId)")

        let database: CKDatabase
        let recordID: CKRecord.ID

        if fromPublic {
            database = try await core.getPublicDatabase()
            recordID = CKRecord.ID(recordName: recipeId.uuidString)
        } else {
            database = try await core.getPrivateDatabase()
            let zoneID = try await core.getCustomZoneID()
            recordID = CKRecord.ID(recordName: recipeId.uuidString, zoneID: zoneID)
        }

        do {
            let record = try await database.record(for: recordID)
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

    // MARK: - Private Helpers

    private func fetchOrCreateRecord(
        in database: CKDatabase,
        recordID: CKRecord.ID,
        recordType: String
    ) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func populateRecipeRecord(_ record: CKRecord, from recipe: Recipe, ownerId: UUID) {
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        record["ownerId"] = ownerId.uuidString as CKRecordValue
        record["title"] = recipe.title as CKRecordValue
        record["visibility"] = recipe.visibility.rawValue as CKRecordValue

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

        if let relatedIdsData = try? encoder.encode(recipe.relatedRecipeIds) {
            record["relatedRecipeIdsData"] = relatedIdsData as CKRecordValue
        }

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
        if let sourceRecipeUpdatedAt = recipe.sourceRecipeUpdatedAt {
            record["sourceRecipeUpdatedAt"] = sourceRecipeUpdatedAt as CKRecordValue
        }
        record["followsSourceUpdates"] = recipe.followsSourceUpdates as CKRecordValue
        if let notes = recipe.notes {
            record["notes"] = notes as CKRecordValue
        }

        record["isPreview"] = recipe.isPreview as CKRecordValue
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

        let relatedRecipeIds: [UUID]
        if let relatedIdsData = record["relatedRecipeIdsData"] as? Data {
            relatedRecipeIds = (try? decoder.decode([UUID].self, from: relatedIdsData)) ?? []
        } else {
            relatedRecipeIds = []
        }

        let cloudImageRecordName: String? = (record["imageAsset"] as? CKAsset) != nil ? record.recordID.recordName : nil
        let imageModifiedAt = record["imageModifiedAt"] as? Date

        let imageURL: URL? = nil

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
        let sourceRecipeUpdatedAt = record["sourceRecipeUpdatedAt"] as? Date
        let followsSourceUpdates = Recipe.resolvedFollowsSourceUpdates(
            originalRecipeId: originalRecipeId,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            followsSourceUpdates: record["followsSourceUpdates"] as? Bool ?? false
        )
        let notes = record["notes"] as? String

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
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            followsSourceUpdates: followsSourceUpdates,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
}
