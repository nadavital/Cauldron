//
//  CloudKitService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

/// Account status for iCloud/CloudKit
enum CloudKitAccountStatus: CustomStringConvertible {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable

    init(from ckStatus: CKAccountStatus) {
        switch ckStatus {
        case .available:
            self = .available
        case .noAccount:
            self = .noAccount
        case .restricted:
            self = .restricted
        case .couldNotDetermine:
            self = .couldNotDetermine
        case .temporarilyUnavailable:
            self = .temporarilyUnavailable
        @unknown default:
            self = .couldNotDetermine
        }
    }

    var isAvailable: Bool {
        self == .available
    }

    var description: String {
        switch self {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        }
    }
}

/// Service for syncing data with CloudKit
/// Note: CloudKit capability must be enabled in Xcode for this to work
actor CloudKitService {
    private let container: CKContainer?
    private let privateDatabase: CKDatabase?
    private let publicDatabase: CKDatabase?
    private let logger = Logger(subsystem: "com.cauldron", category: "CloudKitService")
    private let isEnabled: Bool
    private var cachedAccountStatus: CloudKitAccountStatus?

    // Custom zone for sharing (required for CKShare)
    private let customZoneID = CKRecordZone.ID(zoneName: "CauldronRecipes", ownerName: CKCurrentUserDefaultName)
    private var customZone: CKRecordZone?

    // Record type names
    private let userRecordType = "User"
    private let recipeRecordType = "Recipe"
    private let connectionRecordType = "Connection"
    private let sharedRecipeRecordType = "SharedRecipe"
    private let sharedRecipeReferenceRecordType = "SharedRecipeReference"

    init() {
        // Try to initialize CloudKit, but don't crash if it fails
        do {
            let testContainer = CKContainer.default()
            self.container = testContainer
            self.privateDatabase = testContainer.privateCloudDatabase
            self.publicDatabase = testContainer.publicCloudDatabase
            self.isEnabled = true
            logger.info("CloudKit initialized successfully")
        } catch {
            logger.warning("CloudKit not available: \(error.localizedDescription)")
            logger.warning("Enable CloudKit capability in Xcode to use cloud features")
            self.container = nil
            self.privateDatabase = nil
            self.publicDatabase = nil
            self.isEnabled = false
        }
    }

    // MARK: - Account Status

    /// Check if the user is signed into iCloud and has CloudKit access
    func checkAccountStatus() async -> CloudKitAccountStatus {
        guard isEnabled, let container = container else {
            logger.warning("CloudKit not enabled")
            return .couldNotDetermine
        }

        do {
            let status = try await container.accountStatus()
            let accountStatus = CloudKitAccountStatus(from: status)
            cachedAccountStatus = accountStatus

            logger.info("iCloud account status: \(String(describing: accountStatus))")

            return accountStatus
        } catch {
            logger.error("Failed to check account status: \(error.localizedDescription)")
            return .couldNotDetermine
        }
    }

    /// Get cached account status or check if not cached
    func getAccountStatus() async -> CloudKitAccountStatus {
        if let cached = cachedAccountStatus {
            return cached
        }
        return await checkAccountStatus()
    }

    /// Check if CloudKit is available and user is signed in
    func isCloudKitAvailable() async -> Bool {
        let status = await checkAccountStatus()
        return status.isAvailable
    }
    
    // MARK: - Helper

    private func checkEnabled() throws {
        guard isEnabled, let _ = container else {
            throw CloudKitError.notEnabled
        }
    }

    private func getPrivateDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notEnabled
        }
        return privateDatabase
    }

    private func getPublicDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let publicDatabase = publicDatabase else {
            throw CloudKitError.notEnabled
        }
        return publicDatabase
    }

    // MARK: - Custom Zone Management

    /// Create or fetch the custom zone (required for sharing)
    private func ensureCustomZone() async throws -> CKRecordZone {
        // Return cached zone if available
        if let zone = customZone {
            return zone
        }

        let db = try getPrivateDatabase()

        // Try to fetch existing zone first
        do {
            let zone = try await db.recordZone(for: customZoneID)
            self.customZone = zone
            logger.info("Fetched existing custom zone: \(self.customZoneID.zoneName)")
            return zone
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist, create it
            logger.info("Custom zone not found, creating: \(self.customZoneID.zoneName)")
            let newZone = CKRecordZone(zoneID: customZoneID)
            let savedZone = try await db.save(newZone)
            self.customZone = savedZone
            logger.info("Created custom zone: \(self.customZoneID.zoneName)")
            return savedZone
        }
    }
    
    // MARK: - User Identity
    
    /// Get the current user's CloudKit record ID
    func getCurrentUserRecordID() async throws -> CKRecord.ID {
        try checkEnabled()
        guard let container = container else {
            throw CloudKitError.notEnabled
        }
        return try await container.userRecordID()
    }
    
    /// Fetch existing user profile from CloudKit (returns nil if not found)
    func fetchCurrentUserProfile() async throws -> User? {
        // First check account status
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        // Fetch from PUBLIC database since that's where user profiles are stored
        let db = try getPublicDatabase()
        let systemUserRecordID = try await getCurrentUserRecordID()

        // Try to fetch using the custom record name pattern we use
        let customRecordName = "user_\(systemUserRecordID.recordName)"

        do {
            let record = try await db.record(for: CKRecord.ID(recordName: customRecordName))
            let user = try userFromRecord(record)
            logger.info("Fetched existing user profile: \(user.username)")
            return user
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("No user record found with custom record ID in PUBLIC database")
            // Continue to fallback
        } catch {
            logger.warning("Error fetching user by custom ID: \(error.localizedDescription)")
        }

        // Fallback: Try the old system record ID (for backwards compatibility)
        do {
            let record = try await db.record(for: systemUserRecordID)
            // Check if this record has valid User fields
            if record["userId"] != nil {
                let user = try userFromRecord(record)
                logger.info("Fetched existing user profile from system ID: \(user.username)")
                return user
            } else {
                logger.info("Found record at system ID but it's invalid (missing userId)")
            }
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("No user record found with system record ID in PUBLIC database")
        } catch {
            logger.warning("Error fetching user by system ID: \(error.localizedDescription)")
        }

        // No valid user profile found
        logger.info("No existing user profile found in CloudKit PUBLIC database")
        return nil
    }

    /// Migrate user from PRIVATE database to PUBLIC database (backward compatibility)
    private func migrateUserFromPrivateToPublic() async throws -> User? {
        logger.info("Checking for user in PRIVATE database (migration)...")

        let privateDB = try getPrivateDatabase()
        let systemUserRecordID = try await getCurrentUserRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"

        // Try custom record name first
        do {
            let record = try await privateDB.record(for: CKRecord.ID(recordName: customRecordName))
            if let user = try? userFromRecord(record) {
                logger.info("Found user in PRIVATE database, migrating to PUBLIC: \(user.username)")

                // Save to PUBLIC database
                try await saveUser(user)

                // Delete from PRIVATE database
                try? await privateDB.deleteRecord(withID: record.recordID)
                logger.info("Migration complete: \(user.username) now in PUBLIC database")

                return user
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found with custom name, try system ID
        }

        // Try system record ID
        do {
            let record = try await privateDB.record(for: systemUserRecordID)
            if record["userId"] != nil, let user = try? userFromRecord(record) {
                logger.info("Found user at system ID in PRIVATE database, migrating to PUBLIC: \(user.username)")

                // Save to PUBLIC database
                try await saveUser(user)

                // Delete from PRIVATE database
                try? await privateDB.deleteRecord(withID: record.recordID)
                logger.info("Migration complete: \(user.username) now in PUBLIC database")

                return user
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found in private database
        }

        logger.info("No user found in PRIVATE database to migrate")
        return nil
    }

    /// Fetch or create current user profile
    func fetchOrCreateCurrentUser(username: String, displayName: String) async throws -> User {
        // First check account status
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        // Try to fetch existing user record from PUBLIC database
        if let existingUser = try await fetchCurrentUserProfile() {
            logger.info("Found existing user profile in PUBLIC database: \(existingUser.username)")
            return existingUser
        }

        // Check if user exists in PRIVATE database (old location) and migrate
        if let migratedUser = try await migrateUserFromPrivateToPublic() {
            logger.info("Successfully migrated user from PRIVATE to PUBLIC database")
            return migratedUser
        }

        // No valid user exists, create new one with a custom record name
        // Use a predictable record name based on the system user record ID
        // but with a prefix to avoid conflicts
        let systemUserRecordID = try await getCurrentUserRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"

        logger.info("Creating new user profile in PUBLIC database with custom record ID")
        let user = User(
            username: username,
            displayName: displayName,
            cloudRecordName: customRecordName
        )
        try await saveUser(user)
        return user
    }
    
    // MARK: - Users
    
    /// Save user to CloudKit
    func saveUser(_ user: User) async throws {
        // Use custom record name if provided, otherwise create one
        let recordName: String
        if let cloudRecordName = user.cloudRecordName {
            recordName = cloudRecordName
        } else {
            // Create a custom record name to avoid conflicts with system records
            let systemUserRecordID = try await getCurrentUserRecordID()
            recordName = "user_\(systemUserRecordID.recordName)"
        }

        let recordID = CKRecord.ID(recordName: recordName)
        let record = CKRecord(recordType: userRecordType, recordID: recordID)
        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = user.username as CKRecordValue
        record["displayName"] = user.displayName as CKRecordValue
        if let email = user.email {
            record["email"] = email as CKRecordValue
        }
        record["createdAt"] = user.createdAt as CKRecordValue

        // Save to PUBLIC database so other users can discover this user
        let db = try getPublicDatabase()
        _ = try await db.save(record)
        logger.info("Saved user: \(user.username) to PUBLIC database")
    }
    
    /// Search for users by username (public search)
    /// Note: CloudKit has limited predicate support. We use BEGINSWITH for prefix matching.
    /// For better UX, we search both fields separately and combine results.
    func searchUsers(query: String) async throws -> [User] {
        let db = try getPublicDatabase()
        let lowercaseQuery = query.lowercased()

        // CloudKit doesn't support CONTAINS, so we use BEGINSWITH on both fields
        // We need to search both username and displayName separately
        let usernamePredicate = NSPredicate(format: "username BEGINSWITH %@", lowercaseQuery)
        let usernameQuery = CKQuery(recordType: userRecordType, predicate: usernamePredicate)

        let displayNamePredicate = NSPredicate(format: "displayName BEGINSWITH %@", query)
        let displayNameQuery = CKQuery(recordType: userRecordType, predicate: displayNamePredicate)

        var users: [User] = []
        var userIds = Set<UUID>() // To avoid duplicates

        // Search by username
        let usernameResults = try await db.records(matching: usernameQuery)
        for (_, result) in usernameResults.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record),
               !userIds.contains(user.id) {
                users.append(user)
                userIds.insert(user.id)
            }
        }

        // Search by displayName
        let displayNameResults = try await db.records(matching: displayNameQuery)
        for (_, result) in displayNameResults.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record),
               !userIds.contains(user.id) {
                users.append(user)
                userIds.insert(user.id)
            }
        }

        return users
    }
    
    /// Fetch user by record name
    func fetchUser(cloudRecordName: String) async throws -> User? {
        let recordID = CKRecord.ID(recordName: cloudRecordName)
        do {
            let db = try getPublicDatabase()
            let record = try await db.record(for: recordID)
            return try userFromRecord(record)
        } catch {
            logger.error("Failed to fetch user: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func userFromRecord(_ record: CKRecord) throws -> User {
        guard let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let username = record["username"] as? String,
              let displayName = record["displayName"] as? String else {
            logger.error("Invalid user record - missing required fields. Record: \(record)")
            throw CloudKitError.invalidRecord
        }

        let email = record["email"] as? String
        let createdAt = record["createdAt"] as? Date ?? Date()

        return User(
            id: userId,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: record.recordID.recordName,
            createdAt: createdAt
        )
    }
    
    // MARK: - Recipes
    
    /// Save recipe to CloudKit (always uses custom zone for sharing support)
    /// Note: ALL recipes are saved to iCloud regardless of visibility.
    /// Visibility controls social sharing/discovery, not cloud storage.
    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        logger.info("📤 Starting CloudKit save for recipe: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")

        // Ensure custom zone exists (required for sharing and proper sync)
        let zone = try await ensureCustomZone()
        logger.info("Using custom zone: \(zone.zoneID.zoneName)")

        // Always use custom zone for recipes to support sharing
        let recordID: CKRecord.ID
        if let cloudRecordName = recipe.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName, zoneID: zone.zoneID)
        } else {
            recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: zone.zoneID)
        }

        let record = CKRecord(recordType: recipeRecordType, recordID: recordID)
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        record["ownerId"] = ownerId.uuidString as CKRecordValue
        record["title"] = recipe.title as CKRecordValue
        record["visibility"] = recipe.visibility.rawValue as CKRecordValue  // Controls social sharing, not storage

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

        // All recipes save to private database (visibility controls who can query/share them)
        let db = try getPrivateDatabase()

        logger.info("Saving recipe to CloudKit private database...")
        do {
            let savedRecord = try await db.save(record)
            logger.info("✅ Successfully saved recipe to CloudKit: \(recipe.title)")
            logger.info("Record ID: \(savedRecord.recordID.recordName), Zone: \(savedRecord.recordID.zoneID.zoneName)")
        } catch let error as CKError {
            logger.error("❌ CloudKit save failed: \(error.localizedDescription)")
            logger.error("Error code: \(error.code.rawValue), User info: \(error.userInfo)")
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
    
    /// Delete recipe from CloudKit
    func deleteRecipe(_ recipe: Recipe) async throws {
        guard let cloudRecordName = recipe.cloudRecordName else {
            logger.warning("Cannot delete recipe from CloudKit: no cloud record name")
            return
        }

        let recordID = CKRecord.ID(recordName: cloudRecordName)
        let database = try recipe.visibility == .publicRecipe ? getPublicDatabase() : getPrivateDatabase()

        do {
            try await database.deleteRecord(withID: recordID)
            logger.info("Deleted recipe from CloudKit: \(recipe.title)")
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
        logger.info("🔄 Syncing recipes from CloudKit for owner: \(ownerId)")

        // Check account status first
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            logger.error("CloudKit account not available: \(accountStatus)")
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        // Ensure custom zone exists
        let zone = try await ensureCustomZone()
        logger.info("Using custom zone for sync: \(zone.zoneID.zoneName)")

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

            logger.info("✅ Fetched \(allRecipes.count) recipes from CloudKit custom zone")
        } catch let error as CKError {
            logger.error("❌ Failed to fetch recipes from CloudKit: \(error.localizedDescription)")
            logger.error("Error code: \(error.code.rawValue)")
            throw error
        }

        logger.info("Total recipes synced from CloudKit: \(allRecipes.count)")
        return allRecipes
    }

    private func recipeFromRecord(_ record: CKRecord) throws -> Recipe {
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

        return Recipe(
            id: recipeId,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: record.recordID.recordName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Recipe Sharing (CKShare)

    /// Create a shareable iCloud link for a recipe
    func createShareLink(for recipe: Recipe, ownerId: UUID) async throws -> URL {
        logger.info("🔗 Creating share link for recipe: \(recipe.title)")
        logger.info("📍 Recipe ID: \(recipe.id), Owner ID: \(ownerId)")

        // Ensure custom zone exists (required for sharing)
        logger.info("📦 Ensuring custom zone exists...")
        let zone = try await ensureCustomZone()
        logger.info("✅ Custom zone ready: \(zone.zoneID.zoneName)")

        // Determine the record ID in the custom zone
        let recordID: CKRecord.ID
        if let cloudRecordName = recipe.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName, zoneID: zone.zoneID)
            logger.info("📝 Using existing CloudKit record name: \(cloudRecordName)")
        } else {
            recordID = CKRecord.ID(recordName: recipe.id.uuidString, zoneID: zone.zoneID)
            logger.info("📝 Using recipe ID as record name: \(recipe.id.uuidString)")
        }

        let db = try getPrivateDatabase()
        logger.info("🔒 Using PRIVATE database for recipe storage")

        // Fetch or create the recipe record
        let recipeRecord: CKRecord
        do {
            // Try to fetch existing record first
            logger.info("🔍 Checking for existing recipe record in CloudKit...")
            recipeRecord = try await db.record(for: recordID)
            logger.info("✅ Fetched existing recipe record for sharing")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create it
            logger.info("⚠️ Recipe not in CloudKit yet, creating new record in custom zone")
            recipeRecord = CKRecord(recordType: recipeRecordType, recordID: recordID)
            recipeRecord["recipeId"] = recipe.id.uuidString as CKRecordValue
            recipeRecord["ownerId"] = ownerId.uuidString as CKRecordValue
            recipeRecord["title"] = recipe.title as CKRecordValue
            recipeRecord["visibility"] = recipe.visibility.rawValue as CKRecordValue

            // Encode complex data as JSON
            let encoder = JSONEncoder()
            if let ingredientsData = try? encoder.encode(recipe.ingredients) {
                recipeRecord["ingredientsData"] = ingredientsData as CKRecordValue
            }
            if let stepsData = try? encoder.encode(recipe.steps) {
                recipeRecord["stepsData"] = stepsData as CKRecordValue
            }
            if let tagsData = try? encoder.encode(recipe.tags) {
                recipeRecord["tagsData"] = tagsData as CKRecordValue
            }

            recipeRecord["yields"] = recipe.yields as CKRecordValue
            if let totalMinutes = recipe.totalMinutes {
                recipeRecord["totalMinutes"] = totalMinutes as CKRecordValue
            }
            recipeRecord["createdAt"] = recipe.createdAt as CKRecordValue
            recipeRecord["updatedAt"] = recipe.updatedAt as CKRecordValue
            logger.info("📋 Populated recipe record with all fields")
        }

        // Check if share already exists
        if let shareReference = recipeRecord.share {
            logger.info("🔍 Found existing share reference on recipe record")
            do {
                let shareRecord = try await db.record(for: shareReference.recordID)
                if let existingShare = shareRecord as? CKShare,
                   let shareURL = existingShare.url {
                    logger.info("✅ Returning existing share URL: \(shareURL.absoluteString)")

                    // Create or update SharedRecipeReference for tracking
                    let reference = SharedRecipeReference.linkShare(
                        recipeId: recipe.id,
                        ownerId: ownerId,
                        shareURL: shareURL,
                        recipeTitle: recipe.title,
                        recipeTags: recipe.tags.map { $0.name }
                    )
                    do {
                        try await saveSharedRecipeReference(reference)
                        logger.info("✅ Updated SharedRecipeReference for existing link share")
                    } catch {
                        logger.warning("⚠️ Failed to save SharedRecipeReference: \(error.localizedDescription)")
                    }

                    return shareURL
                }
            } catch {
                logger.warning("⚠️ Failed to fetch existing share, will create new one: \(error.localizedDescription)")
                // Continue to create new share
            }
        }

        // Create CKShare
        logger.info("🆕 Creating new CKShare object...")
        let share = CKShare(rootRecord: recipeRecord)
        share[CKShare.SystemFieldKey.title] = recipe.title as CKRecordValue
        share.publicPermission = .readOnly
        logger.info("✅ CKShare configured with public read-only permission")

        // Save both the share and the record using modern async API
        let savedShare: CKShare
        do {
            logger.info("💾 Saving recipe record and share to CloudKit...")
            let savedRecords = try await db.modifyRecords(
                saving: [recipeRecord, share],
                deleting: [],
                savePolicy: .changedKeys
            )
            logger.info("✅ Successfully created share for recipe, saved \(savedRecords.saveResults.count) records")

            // Log all saved record IDs and check for errors
            var hasErrors = false
            for (recordID, result) in savedRecords.saveResults {
                switch result {
                case .success(let savedRecord):
                    logger.info("  ✓ Saved record: \(recordID.recordName), type: \(savedRecord.recordType)")
                case .failure(let error):
                    logger.error("  ✗ Failed to save record \(recordID.recordName): \(error.localizedDescription)")
                    if let ckError = error as? CKError {
                        logger.error("    CKError code: \(ckError.code.rawValue)")
                    }
                    hasErrors = true
                }
            }

            // If any record failed, throw an error
            if hasErrors {
                throw CloudKitError.invalidRecord
            }

            // Extract the saved share from the results - look for CKShare type
            var foundShare: CKShare?
            for (recordID, result) in savedRecords.saveResults {
                if case .success(let savedRecord) = result,
                   let shareRecord = savedRecord as? CKShare {
                    logger.info("✅ Found saved share with ID: \(recordID.recordName)")
                    foundShare = shareRecord
                    break
                }
            }

            guard let shareRecord = foundShare else {
                logger.error("❌ Could not find CKShare in save results")
                throw CloudKitError.invalidRecord
            }
            savedShare = shareRecord
        } catch {
            logger.error("❌ Failed to save share: \(error.localizedDescription)")
            if let ckError = error as? CKError {
                logger.error("CKError code: \(ckError.code.rawValue)")
            }
            throw error
        }

        // Now get the URL from the saved share
        guard let shareURL = savedShare.url else {
            logger.error("❌ Share was saved but URL is still nil")
            throw CloudKitError.invalidRecord
        }

        logger.info("🎉 Share URL created successfully: \(shareURL.absoluteString)")

        // Create SharedRecipeReference for tracking
        let reference = SharedRecipeReference.linkShare(
            recipeId: recipe.id,
            ownerId: ownerId,
            shareURL: shareURL,
            recipeTitle: recipe.title,
            recipeTags: recipe.tags.map { $0.name }
        )

        do {
            try await saveSharedRecipeReference(reference)
            logger.info("✅ Created SharedRecipeReference for link share tracking")
        } catch {
            logger.warning("⚠️ Failed to save SharedRecipeReference (non-critical): \(error.localizedDescription)")
            // Non-critical error - link still works
        }

        return shareURL
    }

    /// Accept a shared recipe from a CKShare URL
    func acceptSharedRecipe(from metadata: CKShare.Metadata) async throws -> Recipe {
        logger.info("📥 Accepting shared recipe from CKShare metadata")
        logger.info("📍 Root record ID: \(metadata.rootRecordID.recordName)")
        logger.info("📍 Zone: \(metadata.rootRecordID.zoneID.zoneName)")
        logger.info("👤 Participant role: \(metadata.participantRole == .owner ? "owner" : "participant")")

        guard let container = container else {
            logger.error("❌ CloudKit not enabled")
            throw CloudKitError.notEnabled
        }

        // Check if the user is the owner of the share
        let isOwner = metadata.participantRole == .owner
        if isOwner {
            logger.info("👤 User is the owner of this share, fetching from PRIVATE database")

            // Owner doesn't need to accept - just fetch from their private database
            let db = try getPrivateDatabase()
            let rootRecordID = metadata.rootRecordID

            do {
                logger.info("🔍 Fetching own recipe from PRIVATE database...")
                let record = try await db.record(for: rootRecordID)
                let recipe = try recipeFromRecord(record)
                logger.info("✅ Successfully fetched own recipe: \(recipe.title)")
                return recipe
            } catch {
                logger.error("❌ Failed to fetch own recipe: \(error.localizedDescription)")
                if let ckError = error as? CKError {
                    logger.error("CKError code: \(ckError.code.rawValue)")
                }
                throw error
            }
        }

        // Accept the share first (for non-owners)
        logger.info("🤝 Accepting CloudKit share (non-owner participant)...")
        do {
            let acceptedShare = try await container.accept(metadata)
            logger.info("✅ Successfully accepted share: \(acceptedShare.recordID.recordName)")
        } catch let error as CKError {
            // If already accepted, that's okay - continue
            if error.code == .serverRecordChanged {
                logger.info("ℹ️ Share already accepted, continuing...")
            } else {
                logger.error("❌ Failed to accept share: \(error.localizedDescription)")
                logger.error("CKError code: \(error.code.rawValue)")
                throw error
            }
        }

        // Fetch the root record from the shared database
        logger.info("🗄️ Fetching recipe from SHARED CloudKit database...")
        let sharedDatabase = container.sharedCloudDatabase
        let rootRecordID = metadata.rootRecordID

        do {
            let record = try await sharedDatabase.record(for: rootRecordID)
            logger.info("✅ Fetched recipe record from shared database")
            let recipe = try recipeFromRecord(record)
            logger.info("🎉 Successfully accepted and fetched shared recipe: \(recipe.title)")
            logger.info("📊 Recipe has \(recipe.ingredients.count) ingredients and \(recipe.steps.count) steps")
            return recipe
        } catch {
            logger.error("❌ Failed to fetch shared recipe from shared database: \(error.localizedDescription)")
            if let ckError = error as? CKError {
                logger.error("CKError code: \(ckError.code.rawValue)")
                switch ckError.code {
                case .unknownItem:
                    logger.error("💡 Recipe not found - may have been deleted by owner")
                case .networkFailure, .networkUnavailable:
                    logger.error("💡 Network issue - check internet connection")
                case .notAuthenticated:
                    logger.error("💡 Not signed into iCloud")
                case .permissionFailure:
                    logger.error("💡 Permission denied - share may have been revoked")
                default:
                    logger.error("💡 Unknown CloudKit error")
                }
            }
            throw error
        }
    }

    // MARK: - Connections
    
    /// Send a connection request
    func sendConnectionRequest(from fromUserId: UUID, to toUserId: UUID) async throws -> Connection {
        let connection = Connection(
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .pending
        )
        
        try await saveConnection(connection)
        return connection
    }
    
    /// Accept a connection request
    func acceptConnectionRequest(_ connection: Connection) async throws {
        let accepted = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date()
        )
        
        try await saveConnection(accepted)
    }
    
    /// Save connection to CloudKit PUBLIC database
    private func saveConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let record = CKRecord(recordType: connectionRecordType, recordID: recordID)

        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["fromUserId"] = connection.fromUserId.uuidString as CKRecordValue
        record["toUserId"] = connection.toUserId.uuidString as CKRecordValue
        record["status"] = connection.status.rawValue as CKRecordValue
        record["createdAt"] = connection.createdAt as CKRecordValue
        record["updatedAt"] = connection.updatedAt as CKRecordValue

        // Save to PUBLIC database so both users can see the connection
        let db = try getPublicDatabase()
        _ = try await db.save(record)
        logger.info("Saved connection to PUBLIC database: \(connection.id)")
    }
    
    /// Fetch connections for a user from CloudKit PUBLIC database
    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        let predicate = NSPredicate(format: "fromUserId == %@ OR toUserId == %@",
                                   userId.uuidString, userId.uuidString)
        let query = CKQuery(recordType: connectionRecordType, predicate: predicate)

        // Fetch from PUBLIC database where connections are stored
        let db = try getPublicDatabase()
        let results = try await db.records(matching: query)

        var connections: [Connection] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let connection = try? connectionFromRecord(record) {
                    connections.append(connection)
                }
            }
        }

        logger.info("Fetched \(connections.count) connections for user from PUBLIC database")
        return connections
    }
    
    /// Delete a connection from CloudKit PUBLIC database
    func deleteConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try getPublicDatabase()

        try await db.deleteRecord(withID: recordID)
        logger.info("Deleted connection from PUBLIC database: \(connection.id)")
    }

    private func connectionFromRecord(_ record: CKRecord) throws -> Connection {
        guard let connectionIdString = record["connectionId"] as? String,
              let connectionId = UUID(uuidString: connectionIdString),
              let fromUserIdString = record["fromUserId"] as? String,
              let fromUserId = UUID(uuidString: fromUserIdString),
              let toUserIdString = record["toUserId"] as? String,
              let toUserId = UUID(uuidString: toUserIdString),
              let statusString = record["status"] as? String,
              let status = ConnectionStatus(rawValue: statusString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        return Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    
    // MARK: - Push Notifications & Subscriptions

    /// Subscribe to connection requests for push notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone sends them a connection request
    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"

        // Check if subscription already exists
        let db = try getPublicDatabase()
        do {
            _ = try await db.subscription(for: subscriptionID)
            logger.info("Connection request subscription already exists")
            return
        } catch {
            // Subscription doesn't exist, create it
        }

        // Create predicate: toUserId == current user AND status == pending
        let predicate = NSPredicate(format: "toUserId == %@ AND status == %@", userId.uuidString, "pending")

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: connectionRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        // Configure notification
        let notification = CKSubscription.NotificationInfo()
        notification.alertBody = "You have a new connection request!"
        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
            logger.info("Successfully subscribed to connection requests")
        } catch {
            logger.error("Failed to save connection request subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection request notifications
    func unsubscribeFromConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection requests")
        } catch {
            logger.warning("Failed to unsubscribe: \(error.localizedDescription)")
        }
    }

    /// Subscribe to shared recipe notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone shares a recipe with them
    func subscribeToSharedRecipes(forUserId userId: UUID) async throws {
        logger.info("🔔 Setting up push notifications for shared recipes")
        let subscriptionID = "shared-recipes-\(userId.uuidString)"

        // Check if subscription already exists
        let db = try getPublicDatabase()
        do {
            _ = try await db.subscription(for: subscriptionID)
            logger.info("Shared recipe subscription already exists")
            return
        } catch {
            // Subscription doesn't exist, create it
        }

        // Create predicate: sharedWithUserId == current user AND shareType == direct
        let predicate = NSPredicate(
            format: "sharedWithUserId == %@ AND shareType == %@",
            userId.uuidString,
            ShareType.direct.rawValue
        )

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: sharedRecipeReferenceRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        // Configure notification
        let notification = CKSubscription.NotificationInfo()
        notification.alertBody = "A friend shared a recipe with you!"
        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
            logger.info("✅ Successfully subscribed to shared recipe notifications")
        } catch {
            logger.error("Failed to save shared recipe subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from shared recipe notifications
    func unsubscribeFromSharedRecipes(forUserId userId: UUID) async throws {
        let subscriptionID = "shared-recipes-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from shared recipes")
        } catch {
            logger.warning("Failed to unsubscribe from shared recipes: \(error.localizedDescription)")
        }
    }

    // MARK: - Share Recipe

    /// Share a recipe with another user (direct friend-to-friend sharing)
    /// Creates a SharedRecipeReference in PUBLIC database so recipient can access it
    func shareRecipe(_ recipe: Recipe, with userId: UUID, from ownerId: UUID) async throws {
        logger.info("📤 Sharing recipe '\(recipe.title)' with user: \(userId)")
        logger.info("📍 Recipe ID: \(recipe.id), Owner: \(ownerId)")

        // Create SharedRecipeReference pointing to the original recipe
        let reference = SharedRecipeReference.directShare(
            recipeId: recipe.id,
            ownerId: ownerId,
            sharedWithUserId: userId,
            sharedByUserId: ownerId,
            recipeTitle: recipe.title,
            recipeTags: recipe.tags.map { $0.name }
        )

        // Save reference to PUBLIC database (recipient can query this!)
        try await saveSharedRecipeReference(reference)

        logger.info("✅ Successfully shared recipe with friend via PUBLIC database")
        logger.info("📋 SharedRecipeReference ID: \(reference.id)")
    }

    // MARK: - Shared Recipe References

    /// Save a shared recipe reference to PUBLIC database
    /// This creates a lightweight pointer to the original recipe instead of duplicating it
    func saveSharedRecipeReference(_ reference: SharedRecipeReference) async throws {
        logger.info("💾 Saving shared recipe reference: \(reference.recipeTitle) (type: \(reference.shareType.rawValue))")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: reference.id.uuidString)
        let record = CKRecord(recordType: sharedRecipeReferenceRecordType, recordID: recordID)

        // Core fields
        record["referenceId"] = reference.id.uuidString as CKRecordValue
        record["originalRecipeId"] = reference.originalRecipeId.uuidString as CKRecordValue
        record["originalOwnerId"] = reference.originalOwnerId.uuidString as CKRecordValue
        record["sharedByUserId"] = reference.sharedByUserId.uuidString as CKRecordValue
        record["sharedAt"] = reference.sharedAt as CKRecordValue
        record["shareType"] = reference.shareType.rawValue as CKRecordValue

        // Optional recipient (for direct shares)
        if let sharedWithUserId = reference.sharedWithUserId {
            record["sharedWithUserId"] = sharedWithUserId.uuidString as CKRecordValue
        }

        // Optional share URL (for link shares)
        if let shareURL = reference.shareURL {
            record["shareURL"] = shareURL.absoluteString as CKRecordValue
        }

        // Cached metadata for display without fetching full recipe
        record["recipeTitle"] = reference.recipeTitle as CKRecordValue
        if !reference.recipeTags.isEmpty {
            record["recipeTags"] = reference.recipeTags as CKRecordValue
        }

        _ = try await db.save(record)
        logger.info("✅ Saved shared recipe reference to PUBLIC database")
    }

    /// Fetch shared recipe references for a user
    /// This fetches all recipes shared with this user via direct shares, friends-only, or public
    func fetchSharedRecipeReferences(forUserId userId: UUID, includePublic: Bool = true) async throws -> [SharedRecipeReference] {
        logger.info("📥 Fetching shared recipe references for user: \(userId)")

        let db = try getPublicDatabase()

        // Build predicate to get:
        // 1. Direct shares to this user
        // 2. Friends-only recipes (if user has connections - we'll filter client-side)
        // 3. Public recipes (if includePublic is true)
        var predicates: [NSPredicate] = []

        // Direct shares
        predicates.append(NSPredicate(format: "sharedWithUserId == %@", userId.uuidString))

        // Friends-only recipes (we'll filter by connection on client side)
        predicates.append(NSPredicate(format: "shareType == %@", ShareType.friendsOnly.rawValue))

        // Public recipes
        if includePublic {
            predicates.append(NSPredicate(format: "shareType == %@", ShareType.publicRecipe.rawValue))
        }

        let compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let query = CKQuery(recordType: sharedRecipeReferenceRecordType, predicate: compoundPredicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sharedAt", ascending: false)]

        let results = try await db.records(matching: query)

        var references: [SharedRecipeReference] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                if let reference = try? sharedRecipeReferenceFromRecord(record) {
                    references.append(reference)
                } else {
                    logger.warning("Failed to parse shared recipe reference from record: \(record.recordID.recordName)")
                }
            case .failure(let error):
                logger.error("Failed to fetch record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Fetched \(references.count) shared recipe references")
        return references
    }

    /// Fetch shared recipe references that this user has shared with others
    /// Useful for showing "My Shared Recipes"
    func fetchOutgoingSharedRecipeReferences(forUserId userId: UUID) async throws -> [SharedRecipeReference] {
        logger.info("📤 Fetching outgoing shared recipe references for user: \(userId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "sharedByUserId == %@", userId.uuidString)
        let query = CKQuery(recordType: sharedRecipeReferenceRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "sharedAt", ascending: false)]

        let results = try await db.records(matching: query)

        var references: [SharedRecipeReference] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                if let reference = try? sharedRecipeReferenceFromRecord(record) {
                    references.append(reference)
                }
            case .failure(let error):
                logger.error("Failed to fetch record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Fetched \(references.count) outgoing shared recipe references")
        return references
    }

    /// Delete a shared recipe reference
    func deleteSharedRecipeReference(_ referenceId: UUID) async throws {
        logger.info("🗑️ Deleting shared recipe reference: \(referenceId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: referenceId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted shared recipe reference")
    }

    /// Delete all shared recipe references for a specific recipe
    /// Useful when a user deletes their recipe or changes visibility to private
    func deleteAllReferencesForRecipe(recipeId: UUID, ownerId: UUID) async throws {
        logger.info("🗑️ Deleting all references for recipe: \(recipeId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(
            format: "originalRecipeId == %@ AND originalOwnerId == %@",
            recipeId.uuidString,
            ownerId.uuidString
        )
        let query = CKQuery(recordType: sharedRecipeReferenceRecordType, predicate: predicate)

        let results = try await db.records(matching: query)
        var recordIDsToDelete: [CKRecord.ID] = []

        for (recordID, result) in results.matchResults {
            if case .success = result {
                recordIDsToDelete.append(recordID)
            }
        }

        if !recordIDsToDelete.isEmpty {
            let deleteResults = try await db.modifyRecords(saving: [], deleting: recordIDsToDelete)
            logger.info("✅ Deleted \(deleteResults.deleteResults.count) recipe references")
        } else {
            logger.info("No references found to delete")
        }
    }

    // MARK: - Private Helpers for SharedRecipeReference

    private func sharedRecipeReferenceFromRecord(_ record: CKRecord) throws -> SharedRecipeReference {
        guard let referenceIdString = record["referenceId"] as? String,
              let referenceId = UUID(uuidString: referenceIdString),
              let originalRecipeIdString = record["originalRecipeId"] as? String,
              let originalRecipeId = UUID(uuidString: originalRecipeIdString),
              let originalOwnerIdString = record["originalOwnerId"] as? String,
              let originalOwnerId = UUID(uuidString: originalOwnerIdString),
              let sharedByUserIdString = record["sharedByUserId"] as? String,
              let sharedByUserId = UUID(uuidString: sharedByUserIdString),
              let sharedAt = record["sharedAt"] as? Date,
              let shareTypeString = record["shareType"] as? String,
              let shareType = ShareType(rawValue: shareTypeString),
              let recipeTitle = record["recipeTitle"] as? String else {
            throw CloudKitError.invalidRecord
        }

        // Optional fields
        let sharedWithUserId = (record["sharedWithUserId"] as? String).flatMap { UUID(uuidString: $0) }
        let shareURL = (record["shareURL"] as? String).flatMap { URL(string: $0) }
        let recipeTags = (record["recipeTags"] as? [String]) ?? []

        return SharedRecipeReference(
            id: referenceId,
            originalRecipeId: originalRecipeId,
            originalOwnerId: originalOwnerId,
            sharedWithUserId: sharedWithUserId,
            sharedByUserId: sharedByUserId,
            sharedAt: sharedAt,
            shareType: shareType,
            shareURL: shareURL,
            recipeTitle: recipeTitle,
            recipeTags: recipeTags
        )
    }
}

// MARK: - Errors

enum CloudKitError: LocalizedError {
    case invalidRecord
    case notAuthenticated
    case permissionDenied
    case notEnabled
    case accountNotAvailable(CloudKitAccountStatus)
    case networkError
    case quotaExceeded
    case syncConflict

    var errorDescription: String? {
        switch self {
        case .invalidRecord:
            return "Invalid CloudKit record"
        case .notAuthenticated:
            return "Not signed in to iCloud"
        case .permissionDenied:
            return "Permission denied"
        case .notEnabled:
            return "CloudKit is not enabled. Please enable CloudKit capability in Xcode project settings."
        case .accountNotAvailable(let status):
            switch status {
            case .noAccount:
                return "Please sign in to iCloud in Settings to use cloud features"
            case .restricted:
                return "iCloud access is restricted on this device"
            case .temporarilyUnavailable:
                return "iCloud is temporarily unavailable. Please try again later"
            default:
                return "Could not verify iCloud account status"
            }
        case .networkError:
            return "Network connection error. Please check your internet connection"
        case .quotaExceeded:
            return "iCloud storage is full. Please free up space in Settings"
        case .syncConflict:
            return "Sync conflict detected. Your changes may need to be merged manually"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .accountNotAvailable(.noAccount):
            return "Go to Settings > [Your Name] > iCloud to sign in"
        case .accountNotAvailable(.restricted):
            return "Check Settings > Screen Time > Content & Privacy Restrictions"
        case .notEnabled:
            return "This is a developer configuration issue"
        case .quotaExceeded:
            return "Go to Settings > [Your Name] > iCloud > Manage Storage"
        case .networkError:
            return "Check your Wi-Fi or cellular connection"
        default:
            return nil
        }
    }
}
