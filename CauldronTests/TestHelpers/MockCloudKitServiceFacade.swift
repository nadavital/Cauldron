//
//  MockCloudKitServiceFacade.swift
//  CauldronTests
//
//  Mock implementation of CloudKitServiceFacade for testing.
//  Provides in-memory storage and configurable failure modes.
//

import Foundation
import CloudKit
@testable import Cauldron

/// Mock CloudKitServiceFacade for unit testing without real CloudKit calls
actor MockCloudKitServiceFacade {

    // MARK: - In-Memory Storage

    private(set) var recipes: [UUID: Recipe] = [:]
    private(set) var publicRecipes: [UUID: Recipe] = [:]
    private(set) var users: [UUID: User] = [:]
    private(set) var collections: [UUID: Collection] = [:]
    private(set) var collectionReferences: [UUID: CollectionReference] = [:]
    private(set) var connections: [UUID: Connection] = [:]
    private(set) var profileImages: [UUID: Data] = [:]
    private(set) var recipeImages: [UUID: Data] = [:]
    private(set) var collectionImages: [UUID: Data] = [:]

    // MARK: - Configuration

    var accountStatus: CloudKitAccountStatus = .available
    var shouldFailWithError: CloudKitError?
    var networkDelay: TimeInterval = 0

    // MARK: - Call Tracking

    private(set) var saveRecipeCalls: [(Recipe, UUID)] = []
    private(set) var fetchRecipesCalls: [UUID] = []
    private(set) var deleteRecipeCalls: [Recipe] = []
    private(set) var saveUserCalls: [User] = []
    private(set) var fetchUserCalls: [UUID] = []
    private(set) var saveConnectionCalls: [Connection] = []
    private(set) var deleteConnectionCalls: [Connection] = []
    private(set) var saveCollectionCalls: [Collection] = []
    private(set) var deleteCollectionCalls: [UUID] = []

    // MARK: - Initialization

    init() {}

    // MARK: - Test Helpers

    func reset() {
        recipes.removeAll()
        publicRecipes.removeAll()
        users.removeAll()
        collections.removeAll()
        collectionReferences.removeAll()
        connections.removeAll()
        profileImages.removeAll()
        recipeImages.removeAll()
        collectionImages.removeAll()

        accountStatus = .available
        shouldFailWithError = nil
        networkDelay = 0

        saveRecipeCalls.removeAll()
        fetchRecipesCalls.removeAll()
        deleteRecipeCalls.removeAll()
        saveUserCalls.removeAll()
        fetchUserCalls.removeAll()
        saveConnectionCalls.removeAll()
        deleteConnectionCalls.removeAll()
        saveCollectionCalls.removeAll()
        deleteCollectionCalls.removeAll()
    }

    /// Seed test data
    func seedRecipe(_ recipe: Recipe) {
        recipes[recipe.id] = recipe
        if recipe.visibility == .publicRecipe {
            publicRecipes[recipe.id] = recipe
        }
    }

    func seedUser(_ user: User) {
        users[user.id] = user
    }

    func seedCollection(_ collection: Collection) {
        collections[collection.id] = collection
    }

    func seedConnection(_ connection: Connection) {
        connections[connection.id] = connection
    }

    // MARK: - Helper

    private func simulateNetworkDelay() async {
        if networkDelay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
    }

    private func checkForError() throws {
        if let error = shouldFailWithError {
            throw error
        }
    }

    // MARK: - Account Status

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await simulateNetworkDelay()
        return accountStatus
    }

    func isAvailable() async -> Bool {
        return accountStatus.isAvailable
    }

    // MARK: - Recipe Operations

    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        saveRecipeCalls.append((recipe, ownerId))
        recipes[recipe.id] = recipe
    }

    func fetchUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        await simulateNetworkDelay()
        try checkForError()
        fetchRecipesCalls.append(ownerId)
        return recipes.values.filter { $0.ownerId == ownerId }
    }

    func syncUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        return try await fetchUserRecipes(ownerId: ownerId)
    }

    func deleteRecipe(_ recipe: Recipe) async throws {
        await simulateNetworkDelay()
        try checkForError()
        deleteRecipeCalls.append(recipe)
        recipes.removeValue(forKey: recipe.id)
        publicRecipes.removeValue(forKey: recipe.id)
    }

    func copyRecipeToPublic(_ recipe: Recipe) async throws {
        await simulateNetworkDelay()
        try checkForError()
        publicRecipes[recipe.id] = recipe
    }

    func fetchPublicRecipes(limit: Int = 50) async throws -> [Recipe] {
        await simulateNetworkDelay()
        try checkForError()
        return Array(publicRecipes.values.prefix(limit))
    }

    func fetchPublicRecipesForUser(ownerId: UUID) async throws -> [Recipe] {
        await simulateNetworkDelay()
        try checkForError()
        return publicRecipes.values.filter { $0.ownerId == ownerId }
    }

    func fetchPublicRecipe(id: UUID) async throws -> Recipe? {
        await simulateNetworkDelay()
        try checkForError()
        return publicRecipes[id]
    }

    func fetchPublicRecipe(recipeId: UUID, ownerId: UUID) async throws -> Recipe {
        guard let recipe = try await fetchPublicRecipe(id: recipeId) else {
            throw CloudKitError.invalidRecord
        }
        return recipe
    }

    func querySharedRecipes(ownerIds: [UUID]?, visibility: RecipeVisibility) async throws -> [Recipe] {
        await simulateNetworkDelay()
        try checkForError()
        var result = Array(publicRecipes.values)
        if let ownerIds = ownerIds {
            result = result.filter { recipe in
                recipe.ownerId.map { ownerIds.contains($0) } ?? false
            }
        }
        return result.filter { $0.visibility == visibility }
    }

    func deletePublicRecipe(recipeId: UUID, ownerId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        publicRecipes.removeValue(forKey: recipeId)
    }

    func batchFetchPublicRecipeCounts(forOwnerIds ownerIds: [UUID]) async throws -> [UUID: Int] {
        await simulateNetworkDelay()
        try checkForError()
        var counts: [UUID: Int] = [:]
        for ownerId in ownerIds {
            counts[ownerId] = publicRecipes.values.filter { $0.ownerId == ownerId }.count
        }
        return counts
    }

    func fetchPopularPublicRecipes(limit: Int = 20) async throws -> [Recipe] {
        return try await fetchPublicRecipes(limit: limit)
    }

    func searchPublicRecipes(query: String, categories: [String]?, limit: Int = 50) async throws -> [Recipe] {
        await simulateNetworkDelay()
        try checkForError()
        let lowercaseQuery = query.lowercased()
        return publicRecipes.values.filter { recipe in
            recipe.title.lowercased().contains(lowercaseQuery) ||
            recipe.notes?.lowercased().contains(lowercaseQuery) == true
        }
    }

    // MARK: - User Operations

    func fetchCurrentUserProfile() async throws -> User? {
        await simulateNetworkDelay()
        try checkForError()
        return users.values.first
    }

    func fetchOrCreateCurrentUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil
    ) async throws -> User {
        await simulateNetworkDelay()
        try checkForError()
        if let existing = users.values.first {
            return existing
        }
        let user = User(
            id: UUID(),
            username: username,
            displayName: displayName,
            profileEmoji: profileEmoji ?? "🧙‍♀️",
            profileColor: profileColor ?? "#7B68EE"
        )
        users[user.id] = user
        return user
    }

    func saveUser(_ user: User) async throws {
        await simulateNetworkDelay()
        try checkForError()
        saveUserCalls.append(user)
        users[user.id] = user
    }

    func searchUsers(query: String) async throws -> [User] {
        await simulateNetworkDelay()
        try checkForError()
        let lowercaseQuery = query.lowercased()
        return users.values.filter {
            $0.username.lowercased().contains(lowercaseQuery) ||
            $0.displayName.lowercased().contains(lowercaseQuery)
        }
    }

    func fetchAllUsers() async throws -> [User] {
        await simulateNetworkDelay()
        try checkForError()
        return Array(users.values)
    }

    func fetchUser(cloudRecordName: String) async throws -> User? {
        await simulateNetworkDelay()
        try checkForError()
        return users.values.first { $0.cloudRecordName == cloudRecordName }
    }

    func fetchUser(byUserId userId: UUID) async throws -> User? {
        await simulateNetworkDelay()
        try checkForError()
        fetchUserCalls.append(userId)
        return users[userId]
    }

    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        await simulateNetworkDelay()
        try checkForError()
        return userIds.compactMap { users[$0] }
    }

    func deleteUserProfile(userId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        users.removeValue(forKey: userId)
    }

    func uploadUserProfileImage(userId: UUID, imageData: Data) async throws -> String {
        await simulateNetworkDelay()
        try checkForError()
        profileImages[userId] = imageData
        return "profile_\(userId.uuidString)"
    }

    func downloadUserProfileImage(userId: UUID) async throws -> Data? {
        await simulateNetworkDelay()
        try checkForError()
        return profileImages[userId]
    }

    func deleteUserProfileImage(userId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        profileImages.removeValue(forKey: userId)
    }

    func lookupUserByReferralCode(_ code: String) async throws -> User? {
        await simulateNetworkDelay()
        try checkForError()
        return users.values.first { $0.referralCode == code }
    }

    func recordReferralSignup(referrerId: UUID, newUserId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        // Mock implementation - just track the call
    }

    func fetchReferralCount(for userId: UUID) async throws -> Int {
        await simulateNetworkDelay()
        try checkForError()
        return 0 // Mock returns 0
    }

    // MARK: - Collection Operations

    func saveCollection(_ collection: Collection) async throws {
        await simulateNetworkDelay()
        try checkForError()
        saveCollectionCalls.append(collection)
        collections[collection.id] = collection
    }

    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        await simulateNetworkDelay()
        try checkForError()
        return collections.values.filter { $0.userId == userId }
    }

    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        await simulateNetworkDelay()
        try checkForError()
        return collections.values.filter { collection in
            friendIds.contains(collection.userId) && collection.visibility != .privateRecipe
        }
    }

    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        await simulateNetworkDelay()
        try checkForError()
        return collections.values.filter { collection in
            ownerIds.contains(collection.userId) && collection.visibility == visibility
        }
    }

    func deleteCollection(_ collectionId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        deleteCollectionCalls.append(collectionId)
        collections.removeValue(forKey: collectionId)
    }

    func saveCollectionReference(_ reference: CollectionReference) async throws {
        await simulateNetworkDelay()
        try checkForError()
        collectionReferences[reference.id] = reference
    }

    func fetchCollectionReferences(forUserId userId: UUID) async throws -> [CollectionReference] {
        await simulateNetworkDelay()
        try checkForError()
        return collectionReferences.values.filter { $0.userId == userId }
    }

    func deleteCollectionReference(_ referenceId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        collectionReferences.removeValue(forKey: referenceId)
    }

    func uploadCollectionCoverImage(collectionId: UUID, imageData: Data) async throws -> String {
        await simulateNetworkDelay()
        try checkForError()
        collectionImages[collectionId] = imageData
        return "collection_\(collectionId.uuidString)"
    }

    func downloadCollectionCoverImage(collectionId: UUID) async throws -> Data? {
        await simulateNetworkDelay()
        try checkForError()
        return collectionImages[collectionId]
    }

    // MARK: - Connection Operations

    func saveConnection(_ connection: Connection) async throws {
        await simulateNetworkDelay()
        try checkForError()
        saveConnectionCalls.append(connection)
        connections[connection.id] = connection
    }

    func acceptConnectionRequest(_ connection: Connection) async throws {
        await simulateNetworkDelay()
        try checkForError()
        let updated = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            fromDisplayName: connection.fromDisplayName,
            toDisplayName: connection.toDisplayName
        )
        connections[connection.id] = updated
    }

    func rejectConnectionRequest(_ connection: Connection) async throws {
        await simulateNetworkDelay()
        try checkForError()
        connections.removeValue(forKey: connection.id)
    }

    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        await simulateNetworkDelay()
        try checkForError()
        return connections.values.filter { $0.fromUserId == userId || $0.toUserId == userId }
    }

    func connectionExists(between userA: UUID, and userB: UUID) async throws -> Bool {
        await simulateNetworkDelay()
        try checkForError()
        return connections.values.contains { connection in
            (connection.fromUserId == userA && connection.toUserId == userB) ||
            (connection.fromUserId == userB && connection.toUserId == userA)
        }
    }

    func fetchConnections(forUserIds userIds: [UUID]) async throws -> [Connection] {
        await simulateNetworkDelay()
        try checkForError()
        return connections.values.filter { connection in
            userIds.contains(connection.fromUserId) || userIds.contains(connection.toUserId)
        }
    }

    func deleteConnection(_ connection: Connection) async throws {
        await simulateNetworkDelay()
        try checkForError()
        deleteConnectionCalls.append(connection)
        connections.removeValue(forKey: connection.id)
    }

    func deleteAllConnectionsForUser(userId: UUID) async throws {
        await simulateNetworkDelay()
        try checkForError()
        let toRemove = connections.values.filter { $0.fromUserId == userId || $0.toUserId == userId }
        for conn in toRemove {
            connections.removeValue(forKey: conn.id)
        }
    }

    func createAutoFriendConnection(
        referrerId: UUID,
        newUserId: UUID,
        referrerDisplayName: String?,
        newUserDisplayName: String?
    ) async throws {
        await simulateNetworkDelay()
        try checkForError()
        let connection = Connection(
            id: UUID(),
            fromUserId: referrerId,
            toUserId: newUserId,
            status: .accepted,
            fromDisplayName: referrerDisplayName,
            toDisplayName: newUserDisplayName
        )
        connections[connection.id] = connection
    }

    // MARK: - Subscription Operations (No-op for mock)

    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {}
    func unsubscribeFromConnectionRequests(forUserId userId: UUID) async throws {}
    func subscribeToConnectionAcceptances(forUserId userId: UUID) async throws {}
    func unsubscribeFromConnectionAcceptances(forUserId userId: UUID) async throws {}
    func subscribeToReferralSignups(forUserId userId: UUID) async throws {}
    func unsubscribeFromReferralSignups(forUserId userId: UUID) async throws {}

    // MARK: - Image Operations

    func uploadImageAsset(recipeId: UUID, imageData: Data, toPublic: Bool) async throws -> String {
        await simulateNetworkDelay()
        try checkForError()
        recipeImages[recipeId] = imageData
        return "recipe_\(recipeId.uuidString)"
    }

    func downloadImageAsset(recipeId: UUID, fromPublic: Bool) async throws -> Data? {
        await simulateNetworkDelay()
        try checkForError()
        return recipeImages[recipeId]
    }

    func deleteImageAsset(recipeId: UUID, fromPublic: Bool) async throws {
        await simulateNetworkDelay()
        try checkForError()
        recipeImages.removeValue(forKey: recipeId)
    }

    func optimizeImageForCloudKit(_ imageData: Data) async throws -> Data {
        // Just return the data as-is for mock
        return imageData
    }
}
