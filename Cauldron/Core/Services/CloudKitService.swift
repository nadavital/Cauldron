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
    private let sharedRecipeRecordType = "SharedRecipe"  // PUBLIC database
    private let recipeReferenceRecordType = "RecipeReference"  // PUBLIC database

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
    
    /// Fetch all users from CloudKit PUBLIC database
    func fetchAllUsers() async throws -> [User] {
        let db = try getPublicDatabase()

        // Query all users (no predicate = fetch all)
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "username", ascending: true)]

        let results = try await db.records(matching: query, resultsLimit: 200)

        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record) {
                users.append(user)
            }
        }

        logger.info("Fetched \(users.count) total users from PUBLIC database")
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

    /// Fetch user by their userId (UUID)
    /// This queries the PUBLIC database for a user with the given userId field
    func fetchUser(byUserId userId: UUID) async throws -> User? {
        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)

        let results = try await db.records(matching: query, resultsLimit: 1)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                return try? userFromRecord(record)
            }
        }

        logger.warning("No user found with userId: \(userId)")
        return nil
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

        // All recipes save to private database (visibility controls who can query/share them)
        let db = try getPrivateDatabase()

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing record in CloudKit: \(recipe.title)")
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

    // MARK: - Public Recipe Sharing (NEW Architecture)

    /// Copy recipe to PUBLIC database when visibility != .private
    /// This makes the recipe discoverable by friends or everyone
    func copyRecipeToPublic(_ recipe: Recipe) async throws {
        logger.info("📤 Copying recipe to PUBLIC database: \(recipe.title) (visibility: \(recipe.visibility.rawValue))")

        // Only copy if visibility is friends-only or public
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
        logger.info("🔍 Querying shared recipes with visibility: \(visibility.rawValue)")

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

        logger.info("✅ Found \(recipes.count) shared recipes")
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

    // MARK: - Connections

    /// Accept a connection request
    func acceptConnectionRequest(_ connection: Connection) async throws {
        logger.info("🔄 Accepting connection request: \(connection.id) from \(connection.fromUserId) to \(connection.toUserId)")

        let accepted = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date()
        )

        try await saveConnection(accepted)
        logger.info("✅ Connection accepted and saved: \(connection.id) - new status: \(accepted.status.rawValue)")
    }

    /// Reject a connection request by deleting it
    /// This makes it invisible to both users and allows the sender to try again
    func rejectConnectionRequest(_ connection: Connection) async throws {
        logger.info("🔄 Rejecting connection request: \(connection.id) from \(connection.fromUserId) to \(connection.toUserId)")

        // Delete the connection entirely - cleaner than marking as rejected
        try await deleteConnection(connection)
        logger.info("✅ Connection request rejected and deleted: \(connection.id)")
    }

    /// Save connection to CloudKit PUBLIC database
    /// Uses CKModifyRecordsOperation with .changedKeys save policy to allow updates by any user
    func saveConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try getPublicDatabase()

        // Try to fetch existing record first
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing connection: \(connection.id)")
        } catch {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: connectionRecordType, recordID: recordID)
            logger.info("Creating new connection: \(connection.id)")
        }

        // Update record fields
        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["fromUserId"] = connection.fromUserId.uuidString as CKRecordValue
        record["toUserId"] = connection.toUserId.uuidString as CKRecordValue
        record["status"] = connection.status.rawValue as CKRecordValue
        record["createdAt"] = connection.createdAt as CKRecordValue
        record["updatedAt"] = connection.updatedAt as CKRecordValue

        // Sender info for personalized notifications
        if let fromUsername = connection.fromUsername {
            record["fromUsername"] = fromUsername as CKRecordValue
        }
        if let fromDisplayName = connection.fromDisplayName {
            record["fromDisplayName"] = fromDisplayName as CKRecordValue
        }

        // Use modifyRecords with .changedKeys to allow any authenticated user to update
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys // Allow updates even if not the creator
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.logger.info("Successfully saved connection to PUBLIC database: \(connection.id)")
                    continuation.resume()
                case .failure(let error):
                    self.logger.error("Failed to save connection: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            operation.database = db
            operation.start()
        }
    }
    
    /// Fetch connections for a user from CloudKit PUBLIC database
    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        logger.info("📡 Fetching connections for user: \(userId)")
        let db = try getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>() // Track IDs to avoid duplicates

        // Query 1: Connections where user is the sender (fromUserId)
        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: connectionRecordType, predicate: fromPredicate)
        let fromResults = try await db.records(matching: fromQuery)

        for (_, result) in fromResults.matchResults {
            if let record = try? result.get(),
               let connection = try? connectionFromRecord(record),
               !connectionIds.contains(connection.id) {
                connections.append(connection)
                connectionIds.insert(connection.id)
                logger.debug("  Found connection (from): \(connection.id) - status: \(connection.status.rawValue)")
            }
        }

        // Query 2: Connections where user is the receiver (toUserId)
        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: connectionRecordType, predicate: toPredicate)
        let toResults = try await db.records(matching: toQuery)

        for (_, result) in toResults.matchResults {
            if let record = try? result.get(),
               let connection = try? connectionFromRecord(record),
               !connectionIds.contains(connection.id) {
                connections.append(connection)
                connectionIds.insert(connection.id)
                logger.debug("  Found connection (to): \(connection.id) - status: \(connection.status.rawValue)")
            }
        }

        logger.info("✅ Fetched \(connections.count) total connections for user from PUBLIC database")
        logger.info("  Status breakdown: \(connections.filter { $0.status == .pending }.count) pending, \(connections.filter { $0.status == .accepted }.count) accepted, \(connections.filter { $0.status == .rejected }.count) rejected")

        // Clean up duplicates - remove duplicate connections between same two users
        let cleanedConnections = try await removeDuplicateConnections(connections)

        // Filter out rejected connections - they should be invisible to users
        let filteredConnections = cleanedConnections.filter { $0.status != .rejected }
        logger.info("Returning \(filteredConnections.count) connections (excluded \(connections.count - filteredConnections.count) rejected/duplicates)")
        return filteredConnections
    }

    /// Remove duplicate connections between the same two users
    /// Keeps the most recent one (by updatedAt), deletes older duplicates
    private func removeDuplicateConnections(_ connections: [Connection]) async throws -> [Connection] {
        // Group connections by user pair (regardless of direction)
        var connectionsByPair: [Set<UUID>: [Connection]] = [:]

        for connection in connections {
            let userPair = Set([connection.fromUserId, connection.toUserId])
            connectionsByPair[userPair, default: []].append(connection)
        }

        var connectionsToKeep: [Connection] = []
        let db = try getPublicDatabase()

        // For each user pair, keep only the most recent connection
        for (userPair, pairConnections) in connectionsByPair {
            if pairConnections.count > 1 {
                // Sort by updatedAt descending (newest first)
                let sorted = pairConnections.sorted { $0.updatedAt > $1.updatedAt }
                let toKeep = sorted.first!
                let toDelete = Array(sorted.dropFirst())

                logger.warning("🧹 Found \(pairConnections.count) duplicate connections for users \(Array(userPair))")
                logger.info("  Keeping: \(toKeep.id) (status: \(toKeep.status.rawValue), updated: \(toKeep.updatedAt))")

                // Delete the older duplicates from CloudKit
                for duplicate in toDelete {
                    logger.info("  Deleting duplicate: \(duplicate.id) (status: \(duplicate.status.rawValue), updated: \(duplicate.updatedAt))")
                    do {
                        let recordID = CKRecord.ID(recordName: duplicate.id.uuidString)
                        try await db.deleteRecord(withID: recordID)
                        logger.info("  ✅ Deleted duplicate connection: \(duplicate.id)")
                    } catch {
                        logger.error("  ❌ Failed to delete duplicate: \(error.localizedDescription)")
                    }
                }

                connectionsToKeep.append(toKeep)
            } else {
                // No duplicates for this pair
                connectionsToKeep.append(pairConnections[0])
            }
        }

        return connectionsToKeep
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

        // Optional sender info for notifications
        let fromUsername = record["fromUsername"] as? String
        let fromDisplayName = record["fromDisplayName"] as? String

        return Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fromUsername: fromUsername,
            fromDisplayName: fromDisplayName
        )
    }
    
    // MARK: - Push Notifications & Subscriptions

    /// Subscribe to connection requests for push notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone sends them a connection request
    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"

        // Delete existing subscription first (if any) to ensure we use the latest notification format
        let db = try getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Deleted old connection request subscription")
        } catch {
            // Subscription doesn't exist yet, that's fine
            logger.info("No existing subscription to delete (creating fresh)")
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

        // Configure notification with personalized message
        let notification = CKSubscription.NotificationInfo()

        // Use CloudKit field substitution to show sender's display name
        // Format: "DisplayName wants to connect with you"
        // The %[fieldName]@ syntax directly substitutes the field value without requiring localization
        notification.alertBody = "%[fromDisplayName]@ wants to connect with you"

        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo for navigation
        notification.desiredKeys = ["connectionId", "fromUserId", "fromUsername", "fromDisplayName"]

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

    // MARK: - Recipe References (NEW Architecture)

    /// Save recipe reference to PUBLIC database
    /// This creates a lightweight pointer to a shared recipe that the user has saved
    func saveRecipeReference(_ reference: RecipeReference) async throws {
        logger.info("💾 Saving recipe reference: \(reference.recipeTitle)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: reference.id.uuidString)
        let record = CKRecord(recordType: recipeReferenceRecordType, recordID: recordID)

        // Core fields
        record["userId"] = reference.userId.uuidString as CKRecordValue
        record["originalRecipeId"] = reference.originalRecipeId.uuidString as CKRecordValue
        record["originalOwnerId"] = reference.originalOwnerId.uuidString as CKRecordValue
        record["savedAt"] = reference.savedAt as CKRecordValue
        record["isCopy"] = reference.isCopy as CKRecordValue

        // Cached metadata for display without fetching full recipe
        record["recipeTitle"] = reference.recipeTitle as CKRecordValue
        if !reference.recipeTags.isEmpty {
            // Store tags as JSON string for CloudKit PUBLIC database compatibility
            if let tagsJSON = try? JSONEncoder().encode(reference.recipeTags),
               let tagsString = String(data: tagsJSON, encoding: .utf8) {
                record["recipeTags"] = tagsString as CKRecordValue
            }
        }

        _ = try await db.save(record)
        logger.info("✅ Saved recipe reference to PUBLIC database")
    }

    /// Fetch user's saved recipe references
    func fetchRecipeReferences(forUserId userId: UUID) async throws -> [RecipeReference] {
        logger.info("📥 Fetching recipe references for user: \(userId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: recipeReferenceRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]

        let results = try await db.records(matching: query)

        var references: [RecipeReference] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let reference = try? recipeReferenceFromRecord(record) {
                references.append(reference)
            }
        }

        logger.info("✅ Fetched \(references.count) recipe references")
        return references
    }

    /// Delete a recipe reference
    func deleteRecipeReference(_ referenceId: UUID) async throws {
        logger.info("🗑️ Deleting recipe reference: \(referenceId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: referenceId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted recipe reference")
    }

    // MARK: - Private Helpers for RecipeReference

    private func recipeReferenceFromRecord(_ record: CKRecord) throws -> RecipeReference {
        guard let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let originalRecipeIdString = record["originalRecipeId"] as? String,
              let originalRecipeId = UUID(uuidString: originalRecipeIdString),
              let originalOwnerIdString = record["originalOwnerId"] as? String,
              let originalOwnerId = UUID(uuidString: originalOwnerIdString),
              let savedAt = record["savedAt"] as? Date,
              let isCopy = record["isCopy"] as? Bool,
              let recipeTitle = record["recipeTitle"] as? String else {
            throw CloudKitError.invalidRecord
        }

        // Parse tags from JSON string
        let recipeTags: [String]
        if let tagsString = record["recipeTags"] as? String,
           let tagsData = tagsString.data(using: .utf8),
           let tags = try? JSONDecoder().decode([String].self, from: tagsData) {
            recipeTags = tags
        } else {
            recipeTags = []
        }

        return RecipeReference(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            userId: userId,
            originalRecipeId: originalRecipeId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            isCopy: isCopy,
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
