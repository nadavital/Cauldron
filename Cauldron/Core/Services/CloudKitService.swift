//
//  CloudKitService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

/// Service for syncing data with CloudKit
/// Note: CloudKit capability must be enabled in Xcode for this to work
actor CloudKitService {
    private let container: CKContainer?
    private let privateDatabase: CKDatabase?
    private let publicDatabase: CKDatabase?
    private let logger = Logger(subsystem: "com.cauldron", category: "CloudKitService")
    private let isEnabled: Bool
    
    // Record type names
    private let userRecordType = "User"
    private let recipeRecordType = "Recipe"
    private let connectionRecordType = "Connection"
    private let sharedRecipeRecordType = "SharedRecipe"
    
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
    
    // MARK: - User Identity
    
    /// Get the current user's CloudKit record ID
    func getCurrentUserRecordID() async throws -> CKRecord.ID {
        try checkEnabled()
        guard let container = container else {
            throw CloudKitError.notEnabled
        }
        return try await container.userRecordID()
    }
    
    /// Fetch or create current user profile
    func fetchOrCreateCurrentUser(username: String, displayName: String) async throws -> User {
        let userRecordID = try await getCurrentUserRecordID()
        
        // Try to fetch existing user record
        do {
            let db = try getPrivateDatabase()
            let record = try await db.record(for: userRecordID)
            return try userFromRecord(record)
        } catch {
            // User doesn't exist, create new one
            logger.info("Creating new user profile")
            let user = User(
                username: username,
                displayName: displayName,
                cloudRecordName: userRecordID.recordName
            )
            try await saveUser(user)
            return user
        }
    }
    
    // MARK: - Users
    
    /// Save user to CloudKit
    func saveUser(_ user: User) async throws {
        let recordID: CKRecord.ID
        if let cloudRecordName = user.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName)
        } else {
            recordID = try await getCurrentUserRecordID()
        }
        
        let record = CKRecord(recordType: userRecordType, recordID: recordID)
        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = user.username as CKRecordValue
        record["displayName"] = user.displayName as CKRecordValue
        if let email = user.email {
            record["email"] = email as CKRecordValue
        }
        record["createdAt"] = user.createdAt as CKRecordValue
        
        let db = try getPrivateDatabase()
        _ = try await db.save(record)
        logger.info("Saved user: \(user.username)")
    }
    
    /// Search for users by username (public search)
    func searchUsers(query: String) async throws -> [User] {
        let predicate = NSPredicate(format: "username CONTAINS[c] %@ OR displayName CONTAINS[c] %@", query, query)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
        
        let db = try getPublicDatabase()
        let results = try await db.records(matching: query)
        
        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let user = try? userFromRecord(record) {
                    users.append(user)
                }
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
              let displayName = record["displayName"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }
        
        let email = record["email"] as? String
        
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
    
    /// Save recipe to CloudKit
    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        let recordID: CKRecord.ID
        if let cloudRecordName = recipe.cloudRecordName {
            recordID = CKRecord.ID(recordName: cloudRecordName)
        } else {
            recordID = CKRecord.ID(recordName: recipe.id.uuidString)
        }
        
        let record = CKRecord(recordType: recipeRecordType, recordID: recordID)
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
        
        record["yields"] = recipe.yields as CKRecordValue
        if let totalMinutes = recipe.totalMinutes {
            record["totalMinutes"] = totalMinutes as CKRecordValue
        }
        record["createdAt"] = recipe.createdAt as CKRecordValue
        record["updatedAt"] = recipe.updatedAt as CKRecordValue
        
        // Save to appropriate database based on visibility
        let database = try recipe.visibility == .publicRecipe ? getPublicDatabase() : getPrivateDatabase()
        _ = try await database.save(record)
        
        logger.info("Saved recipe: \(recipe.title) with visibility: \(recipe.visibility.rawValue)")
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
    
    /// Save connection to CloudKit
    private func saveConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let record = CKRecord(recordType: connectionRecordType, recordID: recordID)
        
        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["fromUserId"] = connection.fromUserId.uuidString as CKRecordValue
        record["toUserId"] = connection.toUserId.uuidString as CKRecordValue
        record["status"] = connection.status.rawValue as CKRecordValue
        record["createdAt"] = connection.createdAt as CKRecordValue
        record["updatedAt"] = connection.updatedAt as CKRecordValue
        
        let db = try getPrivateDatabase()
        _ = try await db.save(record)
        logger.info("Saved connection: \(connection.id)")
    }
    
    /// Fetch connections for a user
    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        let predicate = NSPredicate(format: "fromUserId == %@ OR toUserId == %@", 
                                   userId.uuidString, userId.uuidString)
        let query = CKQuery(recordType: connectionRecordType, predicate: predicate)
        
        let db = try getPrivateDatabase()
        let results = try await db.records(matching: query)
        
        var connections: [Connection] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                if let connection = try? connectionFromRecord(record) {
                    connections.append(connection)
                }
            }
        }
        
        return connections
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
    
    // MARK: - Share Recipe
    
    /// Share a recipe with another user
    func shareRecipe(_ recipe: Recipe, with userId: UUID, from ownerId: UUID) async throws {
        let sharedRecipe = SharedRecipe(
            recipe: recipe,
            sharedBy: User(id: ownerId, username: "", displayName: ""),
            sharedAt: Date()
        )
        
        let recordID = CKRecord.ID(recordName: sharedRecipe.id.uuidString)
        let record = CKRecord(recordType: sharedRecipeRecordType, recordID: recordID)
        
        record["sharedRecipeId"] = sharedRecipe.id.uuidString as CKRecordValue
        record["recipeId"] = recipe.id.uuidString as CKRecordValue
        record["sharedWithUserId"] = userId.uuidString as CKRecordValue
        record["sharedByUserId"] = ownerId.uuidString as CKRecordValue
        record["sharedAt"] = sharedRecipe.sharedAt as CKRecordValue
        
        let db = try getPrivateDatabase()
        _ = try await db.save(record)
        logger.info("Shared recipe: \(recipe.title)")
    }
}

// MARK: - Errors

enum CloudKitError: LocalizedError {
    case invalidRecord
    case notAuthenticated
    case permissionDenied
    case notEnabled
    
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
        }
    }
}
