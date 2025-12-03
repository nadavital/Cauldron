//
//  CloudKitService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os
import UIKit

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
    private let collectionRecordType = "Collection"  // PUBLIC database
    private let collectionReferenceRecordType = "CollectionReference"  // PUBLIC database

    init() {
        // Try to initialize CloudKit, but don't crash if it fails
        do {
            // Use explicit container identifier to support multiple bundle IDs (dev/production)
            // This ensures both Nadav.Cauldron and Nadav.Cauldron.dev use the same CloudKit container
            let testContainer = CKContainer(identifier: "iCloud.Nadav.Cauldron")
            self.container = testContainer
            self.privateDatabase = testContainer.privateCloudDatabase
            self.publicDatabase = testContainer.publicCloudDatabase
            self.isEnabled = true
            // CloudKit initialized successfully (don't log routine operations)
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

            // Only log if account is NOT available (routine check otherwise)
            if !accountStatus.isAvailable {
                logger.warning("iCloud account status: \(String(describing: accountStatus))")
            }

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

    func getPrivateDatabase() throws -> CKDatabase {
        try checkEnabled()
        guard let privateDatabase = privateDatabase else {
            throw CloudKitError.notEnabled
        }
        return privateDatabase
    }

    func getPublicDatabase() throws -> CKDatabase {
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
            // Fetched existing custom zone (don't log routine operations)
            return zone
        } catch let error as CKError where error.code == .zoneNotFound {
            // Zone doesn't exist, create it
            logger.info("Custom zone not found, creating: \(self.customZoneID.zoneName)")
            let newZone = CKRecordZone(zoneID: customZoneID)
            let savedZone = try await db.save(newZone)
            self.customZone = savedZone
            logger.info("✅ Created custom zone: \(self.customZoneID.zoneName)")
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
    func fetchOrCreateCurrentUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil
    ) async throws -> User {
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
            cloudRecordName: customRecordName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
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
        let db = try getPublicDatabase()

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing user record in CloudKit: \(user.username)")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: userRecordType, recordID: recordID)
            logger.info("Creating new user record in CloudKit: \(user.username)")
        } catch {
            // Other error, rethrow
            logger.error("Error fetching existing user record: \(error.localizedDescription)")
            throw error
        }

        // Update/set all fields
        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = user.username as CKRecordValue
        record["displayName"] = user.displayName as CKRecordValue
        if let email = user.email {
            record["email"] = email as CKRecordValue
        }
        if let emoji = user.profileEmoji {
            record["profileEmoji"] = emoji as CKRecordValue
        }
        if let color = user.profileColor {
            record["profileColor"] = color as CKRecordValue
        }
        if let cloudImageRecordName = user.cloudProfileImageRecordName {
            record["cloudProfileImageRecordName"] = cloudImageRecordName as CKRecordValue
        }
        if let imageModifiedAt = user.profileImageModifiedAt {
            record["profileImageModifiedAt"] = imageModifiedAt as CKRecordValue
        }
        record["createdAt"] = user.createdAt as CKRecordValue

        // Save to PUBLIC database so other users can discover this user
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

    /// Fetch multiple users by their userIds (UUID)
    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }
        
        let db = try getPublicDatabase()
        let userIdStrings = userIds.map { $0.uuidString }
        
        // Use IN predicate to fetch all users at once
        let predicate = NSPredicate(format: "userId IN %@", userIdStrings)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
        
        let results = try await db.records(matching: query, resultsLimit: userIds.count)
        
        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record) {
                users.append(user)
            }
        }
        
        return users
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
        let profileEmoji = record["profileEmoji"] as? String
        let profileColor = record["profileColor"] as? String
        let cloudProfileImageRecordName = record["cloudProfileImageRecordName"] as? String
        let profileImageModifiedAt = record["profileImageModifiedAt"] as? Date

        return User(
            id: userId,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: record.recordID.recordName,
            createdAt: createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: nil,  // Will be set after downloading image
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt
        )
    }
    
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

        // Note: Image asset is uploaded separately via uploadImageAsset()
        // We preserve existing imageAsset and imageModifiedAt if they exist
        // This allows recipe data sync to happen independently from image sync

        do {
            let savedRecord = try await db.save(record)
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
            notes: nil,
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
            savedAt: savedAt
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

    /// Search public recipes by query and/or categories
    /// - Parameters:
    ///   - query: The search text (searches title and tags)
    ///   - categories: Optional list of category names to filter by (AND logic)
    ///   - limit: Maximum number of results
    func searchPublicRecipes(query: String, categories: [String]?, limit: Int = 50) async throws -> [Recipe] {
        let db = try getPublicDatabase()
        var predicates: [NSPredicate] = []
        
        // 1. Visibility Predicate
        predicates.append(NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue))
        
        // 2. Text Search Predicate
        if !query.isEmpty {
            // Search title OR tags
            // Note: CloudKit doesn't support complex OR queries well with other AND clauses in some cases,
            // but (A OR B) AND C is generally supported.
            let titlePredicate = NSPredicate(format: "title BEGINSWITH %@", query) // BEGINSWITH is often faster/better supported than CONTAINS for tokenized fields, but let's try CONTAINS[cd] if possible or stick to simple token matching.
            // Actually, for "Self-Service Search", CloudKit recommends using `allTokens` or `self` for tokenized search if configured.
            // But since we don't know the index configuration, let's use `allTokens` tokenized search if possible, or fall back to standard text matching.
            // Let's use a simple approach first: Title contains query OR tags contains query
            
            // Note: CONTAINS[cd] requires a "Queryable" index on the field.
            // We'll assume "title" and "searchableTags" are queryable.
            
            let textPredicate = NSPredicate(format: "title BEGINSWITH %@ OR searchableTags CONTAINS %@", query, query)
            // Using BEGINSWITH for title as it's often a default index. CONTAINS might require explicit index.
            // For tags, CONTAINS checks if the array contains the element.
            
            predicates.append(textPredicate)
        }
        
        // 3. Category Filter Predicate
        if let categories = categories, !categories.isEmpty {
            for category in categories {
                // For each category, the recipe's tags must contain it
                let categoryPredicate = NSPredicate(format: "searchableTags CONTAINS %@", category)
                predicates.append(categoryPredicate)
            }
        }
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let queryObj = CKQuery(recordType: recipeRecordType, predicate: compoundPredicate)
        queryObj.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let results = try await db.records(matching: queryObj, resultsLimit: limit)
        
        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }
        
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

        // Acceptor info for acceptance notifications
        if let toUsername = connection.toUsername {
            record["toUsername"] = toUsername as CKRecordValue
        }
        if let toDisplayName = connection.toDisplayName {
            record["toDisplayName"] = toDisplayName as CKRecordValue
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
        // Fetching connections (don't log routine operations)
        let db = try getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>() // Track IDs to avoid duplicates

        // Query 1: Connections where user is the sender (fromUserId)
        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: connectionRecordType, predicate: fromPredicate)
        let fromResults = try await db.records(matching: fromQuery)

        for (_, result) in fromResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy connections (rejected/blocked) - they should be deleted
                    logger.info("⏭️ Skipping legacy connection record (likely rejected/blocked): \(record.recordID.recordName)")
                }
            }
        }

        // Query 2: Connections where user is the receiver (toUserId)
        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: connectionRecordType, predicate: toPredicate)
        let toResults = try await db.records(matching: toQuery)

        for (_, result) in toResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy connections (rejected/blocked) - they should be deleted
                    logger.info("⏭️ Skipping legacy connection record (likely rejected/blocked): \(record.recordID.recordName)")
                }
            }
        }

        // Fetched connections from CloudKit (don't log routine operations)

        // Clean up duplicates - remove duplicate connections between same two users
        let cleanedConnections = try await removeDuplicateConnections(connections)

        // Return cleaned connections (don't log count - routine operation)
        return cleanedConnections
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

        // Optional acceptor/receiver info for acceptance notifications
        let toUsername = record["toUsername"] as? String
        let toDisplayName = record["toDisplayName"] as? String

        return Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fromUsername: fromUsername,
            fromDisplayName: fromDisplayName,
            toUsername: toUsername,
            toDisplayName: toDisplayName
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
        } catch {
            // Subscription doesn't exist yet, that's fine (routine)
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

        // Use localization with field substitution to show sender's display name
        // This requires a Localizable.strings file with the key "CONNECTION_REQUEST_ALERT"
        // The %@ placeholder will be replaced with the value from the fromDisplayName field
        notification.alertLocalizationKey = "CONNECTION_REQUEST_ALERT"
        notification.alertLocalizationArgs = ["fromDisplayName"]

        // Fallback message if localization fails (shouldn't happen if Localizable.strings exists)
        notification.alertBody = "You have a new friend request!"

        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo for navigation
        notification.desiredKeys = ["connectionId", "fromUserId", "fromUsername", "fromDisplayName"]

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
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

    /// Subscribe to connection acceptances for push notifications
    /// This sets up a CloudKit subscription so the user gets notified when someone accepts their friend request
    func subscribeToConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"

        // Delete existing subscription first (if any) to ensure we use the latest notification format
        let db = try getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet, that's fine (routine)
        }

        // Create predicate: fromUserId == current user AND status == accepted
        let predicate = NSPredicate(format: "fromUserId == %@ AND status == %@", userId.uuidString, "accepted")

        // Create query subscription
        let subscription = CKQuerySubscription(
            recordType: connectionRecordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]  // Fires when status changes to accepted
        )

        // Configure notification with personalized message
        let notification = CKSubscription.NotificationInfo()

        // Use simple alert message (can't rely on optional fields like toUsername being present)
        notification.alertBody = "Your friend request was accepted!"

        notification.soundName = "default"
        notification.shouldBadge = false  // Don't badge for acceptances, only for incoming requests
        notification.shouldSendContentAvailable = true

        // Include connection data in userInfo for navigation
        // Only request fields that are guaranteed to exist (avoid optional fields that may cause errors)
        notification.desiredKeys = ["connectionId", "fromUserId", "toUserId", "status"]

        subscription.notificationInfo = notification

        // Save subscription
        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save connection acceptance subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection acceptance notifications
    func unsubscribeFromConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"
        let db = try getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection acceptances")
        } catch {
            logger.warning("Failed to unsubscribe from acceptances: \(error.localizedDescription)")
        }
    }

    // MARK: - Collections

    /// Save collection to PUBLIC database (for sharing)
    func saveCollection(_ collection: Collection) async throws {
        logger.info("💾 Saving collection: \(collection.name)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collection.id.uuidString)

        // Try to fetch existing record first, create new if doesn't exist
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing collection record")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: collectionRecordType, recordID: recordID)
            logger.info("Creating new collection record")
        }

        // Core fields
        record["collectionId"] = collection.id.uuidString as CKRecordValue
        record["name"] = collection.name as CKRecordValue
        record["userId"] = collection.userId.uuidString as CKRecordValue
        record["visibility"] = collection.visibility.rawValue as CKRecordValue
        record["createdAt"] = collection.createdAt as CKRecordValue
        record["updatedAt"] = collection.updatedAt as CKRecordValue

        // Optional fields
        if let description = collection.description {
            record["description"] = description as CKRecordValue
        }
        if let emoji = collection.emoji {
            record["emoji"] = emoji as CKRecordValue
        }
        if let color = collection.color {
            record["color"] = color as CKRecordValue
        }
        record["coverImageType"] = collection.coverImageType.rawValue as CKRecordValue

        // Recipe IDs stored as JSON string
        if let recipeIdsJSON = try? JSONEncoder().encode(collection.recipeIds),
           let recipeIdsString = String(data: recipeIdsJSON, encoding: .utf8) {
            record["recipeIds"] = recipeIdsString as CKRecordValue
        }

        _ = try await db.save(record)
        logger.info("✅ Saved collection to PUBLIC database")
    }

    /// Fetch user's own collections
    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        logger.info("📥 Fetching collections for user: \(userId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        let results = try await db.records(matching: query)

        var collections: [Collection] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let collection = try? collectionFromRecord(record) {
                collections.append(collection)
            }
        }

        logger.info("✅ Fetched \(collections.count) collections")
        return collections
    }

    /// Fetch shared collections from friends (friends-only and public visibility)
    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        // Fetching shared collections (don't log routine operations)

        guard !friendIds.isEmpty else { return [] }

        let db = try getPublicDatabase()

        // Query for collections where:
        // - userId is in friendIds AND
        // - visibility is NOT private
        let friendIdStrings = friendIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility != %@",
            friendIdStrings,
            RecipeVisibility.privateRecipe.rawValue
        )
        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query)

            var collections: [Collection] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let collection = try? collectionFromRecord(record) {
                    collections.append(collection)
                }
            }

            // Return shared collections (don't log routine operations)
            return collections
        } catch let error as CKError {
            // Handle schema not yet deployed - record type doesn't exist until first save
            if error.code == .unknownItem || error.errorCode == 11 { // 11 = unknown record type
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Query collections by owner and visibility (similar to querySharedRecipes)
    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        logger.info("🔍 Querying collections from \(ownerIds.count) owners with visibility: \(visibility.rawValue)")

        guard !ownerIds.isEmpty else { return [] }

        let db = try getPublicDatabase()

        // Build predicate for userId and visibility
        let ownerIdStrings = ownerIds.map { $0.uuidString }
        let predicate = NSPredicate(
            format: "userId IN %@ AND visibility == %@",
            ownerIdStrings,
            visibility.rawValue
        )

        let query = CKQuery(recordType: collectionRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query, resultsLimit: 100)

            var collections: [Collection] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let collection = try? collectionFromRecord(record) {
                    collections.append(collection)
                }
            }

            logger.info("✅ Found \(collections.count) collections")
            return collections
        } catch let error as CKError {
            // Handle schema not yet deployed - record type doesn't exist until first save
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Delete collection from PUBLIC database
    func deleteCollection(_ collectionId: UUID) async throws {
        logger.info("🗑️ Deleting collection: \(collectionId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted collection")
    }

    // MARK: - Collection References

    /// Save collection reference to PUBLIC database
    func saveCollectionReference(_ reference: CollectionReference) async throws {
        logger.info("💾 Saving collection reference: \(reference.collectionName)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: reference.id.uuidString)
        let record = CKRecord(recordType: collectionReferenceRecordType, recordID: recordID)

        // Core fields
        record["userId"] = reference.userId.uuidString as CKRecordValue
        record["originalCollectionId"] = reference.originalCollectionId.uuidString as CKRecordValue
        record["originalOwnerId"] = reference.originalOwnerId.uuidString as CKRecordValue
        record["savedAt"] = reference.savedAt as CKRecordValue

        // Cached metadata
        record["collectionName"] = reference.collectionName as CKRecordValue
        if let emoji = reference.collectionEmoji {
            record["collectionEmoji"] = emoji as CKRecordValue
        }
        record["recipeCount"] = reference.recipeCount as CKRecordValue

        // Staleness tracking
        record["lastValidatedAt"] = reference.lastValidatedAt as CKRecordValue
        record["cachedVisibility"] = reference.cachedVisibility as CKRecordValue

        _ = try await db.save(record)
        logger.info("✅ Saved collection reference to PUBLIC database")
    }

    /// Fetch user's saved collection references
    func fetchCollectionReferences(forUserId userId: UUID) async throws -> [CollectionReference] {
        logger.info("📥 Fetching collection references for user: \(userId)")

        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: collectionReferenceRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "savedAt", ascending: false)]

        do {
            let results = try await db.records(matching: query)

            var references: [CollectionReference] = []
            for (_, result) in results.matchResults {
                if let record = try? result.get(),
                   let reference = try? collectionReferenceFromRecord(record) {
                    references.append(reference)
                }
            }

            logger.info("✅ Fetched \(references.count) collection references")
            return references
        } catch let error as CKError {
            // Handle schema not yet deployed - record type doesn't exist until first save
            if error.code == .unknownItem || error.errorCode == 11 { // 11 = unknown record type
                logger.info("CollectionReference record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Delete a collection reference
    func deleteCollectionReference(_ referenceId: UUID) async throws {
        logger.info("🗑️ Deleting collection reference: \(referenceId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: referenceId.uuidString)

        try await db.deleteRecord(withID: recordID)
        logger.info("✅ Deleted collection reference")
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

    // MARK: - User Profile Image Methods

    /// Upload user profile image to CloudKit
    /// - Parameters:
    ///   - userId: The user ID this image belongs to
    ///   - imageData: The image data to upload
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadUserProfileImage(userId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading profile image for user: \(userId)")

        // Optimize image before upload
        let optimizedData = try await optimizeImageForCloudKit(imageData)

        // Create temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile_\(userId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create CKAsset
        let asset = CKAsset(fileURL: tempURL)

        // Get public database
        let db = try getPublicDatabase()

        // Create a separate ProfileImage record instead of storing in User record
        // This avoids schema issues and is cleaner architecture
        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            // Try to fetch existing image record first
            let imageRecord: CKRecord
            do {
                imageRecord = try await db.record(for: imageRecordID)
                logger.info("Updating existing profile image record")
            } catch let error as CKError where error.code == .unknownItem {
                // Create new image record
                imageRecord = CKRecord(recordType: "ProfileImage", recordID: imageRecordID)
                logger.info("Creating new profile image record")
            }

            // Set the asset and metadata
            imageRecord["imageAsset"] = asset
            imageRecord["userId"] = userId.uuidString as CKRecordValue
            imageRecord["modifiedAt"] = Date() as CKRecordValue

            // Save the image record
            let savedImageRecord = try await db.save(imageRecord)
            logger.info("✅ Uploaded profile image to separate record")

            return savedImageRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload profile image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download user profile image from CloudKit
    /// - Parameter userId: The user ID to download image for
    /// - Returns: The image data, or nil if no image exists
    func downloadUserProfileImage(userId: UUID) async throws -> Data? {
        logger.info("📥 Downloading profile image for user: \(userId)")

        let db = try getPublicDatabase()

        // Look for ProfileImage record using the userId-based naming convention
        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            let imageRecord = try await db.record(for: imageRecordID)

            guard let asset = imageRecord["imageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.info("No profile image asset found for user: \(userId)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            logger.info("✅ Downloaded profile image (\(data.count) bytes)")
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("No profile image record found for user: \(userId)")
                return nil
            }
            throw error
        }
    }

    /// Delete user profile image from CloudKit
    /// - Parameter userId: The user ID to delete image for
    func deleteUserProfileImage(userId: UUID) async throws {
        logger.info("🗑️ Deleting profile image for user: \(userId)")

        let db = try getPublicDatabase()

        // Delete the separate ProfileImage record
        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            try await db.deleteRecord(withID: imageRecordID)
            logger.info("✅ Deleted profile image record")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("No profile image record found to delete for user: \(userId)")
                return
            }
            throw error
        }
    }

    /// Delete user profile from CloudKit (for account deletion)
    /// - Parameter userId: The user ID to delete
    func deleteUserProfile(userId: UUID) async throws {
        logger.info("🗑️ Deleting user profile from CloudKit: \(userId)")

        let db = try getPublicDatabase()

        // Get user's CloudKit record
        let systemUserRecordID = try await getCurrentUserRecordID()
        let recordName = "user_\(systemUserRecordID.recordName)"
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            // Delete user profile image first if exists
            try await deleteUserProfileImage(userId: userId)

            // Delete the user record itself
            _ = try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted user profile from CloudKit")
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("User record not found: \(userId)")
                // Not an error - already deleted
                return
            }
            logger.error("Failed to delete user profile: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Collection Cover Image Methods

    /// Upload collection cover image to CloudKit
    /// - Parameters:
    ///   - collectionId: The collection ID this image belongs to
    ///   - imageData: The image data to upload
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadCollectionCoverImage(collectionId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading collection cover image for collection: \(collectionId)")

        // Optimize image before upload
        let optimizedData = try await optimizeImageForCloudKit(imageData)

        // Create temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection_\(collectionId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create CKAsset
        let asset = CKAsset(fileURL: tempURL)

        // Get collection's CloudKit record
        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            // Fetch existing collection record
            let record = try await db.record(for: recordID)

            // Add cover image asset and modification timestamp
            record["coverImageAsset"] = asset
            record["coverImageModifiedAt"] = Date() as CKRecordValue

            // Save updated record
            let savedRecord = try await db.save(record)
            logger.info("✅ Uploaded collection cover image asset")
            return savedRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.error("Collection record not found in CloudKit: \(collectionId)")
                throw CloudKitError.invalidRecord
            } else if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload collection cover image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download collection cover image from CloudKit
    /// - Parameter collectionId: The collection ID to download image for
    /// - Returns: The image data, or nil if no image exists
    func downloadCollectionCoverImage(collectionId: UUID) async throws -> Data? {
        logger.info("📥 Downloading collection cover image for collection: \(collectionId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            guard let asset = record["coverImageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.info("No collection cover image asset found for collection: \(collectionId)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            logger.info("✅ Downloaded collection cover image (\(data.count) bytes)")
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return nil
            }
            throw error
        }
    }

    /// Delete collection cover image from CloudKit
    /// - Parameter collectionId: The collection ID to delete image for
    func deleteCollectionCoverImage(collectionId: UUID) async throws {
        logger.info("🗑️ Deleting collection cover image for collection: \(collectionId)")

        let db = try getPublicDatabase()
        let recordID = CKRecord.ID(recordName: collectionId.uuidString)

        do {
            let record = try await db.record(for: recordID)

            // Remove cover image asset fields
            record["coverImageAsset"] = nil
            record["coverImageModifiedAt"] = nil

            _ = try await db.save(record)
            logger.info("✅ Deleted collection cover image asset")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return
            }
            throw error
        }
    }

    // MARK: - Image Optimization

    /// Optimize image data for CloudKit upload
    /// - Parameter imageData: Original image data
    /// - Returns: Optimized image data
    /// - Throws: CloudKitError if optimization fails or image is too large
    private func optimizeImageForCloudKit(_ imageData: Data) async throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: imageData) else {
            throw CloudKitError.compressionFailed
        }

        let maxSizeBytes = 10_000_000 // 10MB max for CloudKit
        let compressionThreshold = 5_000_000 // 5MB - compress if larger

        // Try 80% quality compression first
        if let data = image.jpegData(compressionQuality: 0.8) {
            if data.count <= compressionThreshold {
                return data
            }
            if data.count <= maxSizeBytes {
                return data
            }
        }

        // Try 60% compression
        if let compressedData = image.jpegData(compressionQuality: 0.6),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        // If still too large, resize and compress
        let maxDimension: CGFloat = 2000
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let resizedImage = resizedImage,
               let compressedData = resizedImage.jpegData(compressionQuality: 0.8),
               compressedData.count <= maxSizeBytes {
                return compressedData
            }
        }

        throw CloudKitError.assetTooLarge
        #else
        // macOS or other platforms
        throw CloudKitError.compressionFailed
        #endif
    }

    // MARK: - Private Helpers for Collections

    private func collectionFromRecord(_ record: CKRecord) throws -> Collection {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let name = record["name"] as? String,
              let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let visibilityString = record["visibility"] as? String,
              let visibility = RecipeVisibility(rawValue: visibilityString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        // Parse recipe IDs from JSON string
        let recipeIds: [UUID]
        if let recipeIdsString = record["recipeIds"] as? String,
           let recipeIdsData = recipeIdsString.data(using: .utf8),
           let ids = try? JSONDecoder().decode([UUID].self, from: recipeIdsData) {
            recipeIds = ids
        } else {
            recipeIds = []
        }

        let description = record["description"] as? String
        let emoji = record["emoji"] as? String
        let color = record["color"] as? String
        let coverImageTypeString = record["coverImageType"] as? String
        let coverImageType = coverImageTypeString.flatMap { CoverImageType(rawValue: $0) } ?? .recipeGrid

        return Collection(
            id: collectionId,
            name: name,
            description: description,
            userId: userId,
            recipeIds: recipeIds,
            visibility: visibility,
            emoji: emoji,
            color: color,
            coverImageType: coverImageType,
            cloudRecordName: record.recordID.recordName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func collectionReferenceFromRecord(_ record: CKRecord) throws -> CollectionReference {
        guard let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let originalCollectionIdString = record["originalCollectionId"] as? String,
              let originalCollectionId = UUID(uuidString: originalCollectionIdString),
              let originalOwnerIdString = record["originalOwnerId"] as? String,
              let originalOwnerId = UUID(uuidString: originalOwnerIdString),
              let savedAt = record["savedAt"] as? Date,
              let collectionName = record["collectionName"] as? String,
              let recipeCount = record["recipeCount"] as? Int else {
            throw CloudKitError.invalidRecord
        }

        let collectionEmoji = record["collectionEmoji"] as? String
        // Optional fields with defaults for backward compatibility
        let lastValidatedAt = record["lastValidatedAt"] as? Date ?? savedAt
        let cachedVisibility = record["cachedVisibility"] as? String ?? "public"

        return CollectionReference(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            userId: userId,
            originalCollectionId: originalCollectionId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            collectionName: collectionName,
            collectionEmoji: collectionEmoji,
            recipeCount: recipeCount,
            lastValidatedAt: lastValidatedAt,
            cachedVisibility: cachedVisibility,
            cloudRecordName: record.recordID.recordName
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
    case assetNotFound
    case assetTooLarge
    case compressionFailed

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
        case .assetNotFound:
            return "Image not found in iCloud"
        case .assetTooLarge:
            return "Image is too large to upload (max 10MB)"
        case .compressionFailed:
            return "Failed to compress image for upload"
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
