//
//  CloudKitServiceFacade.swift
//  Cauldron
//
//  Facade that wraps the new domain-specific CloudKit services
//  while maintaining backwards compatibility with the old CloudKitService interface.
//
//  This allows gradual migration of consumers to the new services.
//

import Foundation
import CloudKit
import os

/// Facade that maintains backwards compatibility with the old CloudKitService
/// while delegating to the new domain-specific services.
///
/// Usage:
/// - During migration: Use this as a drop-in replacement for CloudKitService
/// - After migration: Access domain services directly via cloudKitCore
///
/// Migration path:
/// 1. Replace CloudKitService with CloudKitServiceFacade in DependencyContainer
/// 2. Gradually update consumers to use domain services directly
/// 3. Remove facade when all consumers are migrated
actor CloudKitServiceFacade {
    // Core infrastructure
    let core: CloudKitCore

    // Domain services
    let recipeService: RecipeCloudService
    let userService: UserCloudService
    let collectionService: CollectionCloudService
    let connectionService: ConnectionCloudService
    let searchService: SearchCloudService

    private let logger = Logger(subsystem: "com.cauldron", category: "CloudKitServiceFacade")

    // Legacy constants (for backwards compatibility during migration)
    internal let customZoneName = "CauldronZone"
    internal let userRecordType = "User"
    internal let recipeRecordType = "Recipe"
    internal let sharedRecipeRecordType = "SharedRecipe"
    internal let collectionRecordType = "Collection"
    internal let connectionRecordType = "Connection"

    init() {
        self.core = CloudKitCore()
        self.recipeService = RecipeCloudService(core: core)
        self.userService = UserCloudService(core: core)
        self.collectionService = CollectionCloudService(core: core)
        self.connectionService = ConnectionCloudService(core: core)
        self.searchService = SearchCloudService(core: core)
    }

    // MARK: - Account Status

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Database Access (for legacy compatibility)

    func getPrivateDatabase() async throws -> CKDatabase {
        try await core.getPrivateDatabase()
    }

    func getPublicDatabase() async throws -> CKDatabase {
        try await core.getPublicDatabase()
    }

    // MARK: - Recipes (delegated to RecipeCloudService)

    func saveRecipe(_ recipe: Recipe, ownerId: UUID) async throws {
        try await recipeService.saveRecipe(recipe, ownerId: ownerId)
    }

    func fetchUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        try await recipeService.fetchUserRecipes(ownerId: ownerId)
    }

    func syncUserRecipes(ownerId: UUID) async throws -> [Recipe] {
        try await recipeService.syncUserRecipes(ownerId: ownerId)
    }

    func deleteRecipe(_ recipe: Recipe) async throws {
        try await recipeService.deleteRecipe(recipe)
    }

    func copyRecipeToPublic(_ recipe: Recipe) async throws {
        try await recipeService.copyRecipeToPublic(recipe)
    }

    func fetchPublicRecipes(limit: Int = 50) async throws -> [Recipe] {
        try await recipeService.fetchPublicRecipes(limit: limit)
    }

    func fetchPublicRecipesForUser(ownerId: UUID) async throws -> [Recipe] {
        try await recipeService.fetchPublicRecipesForUser(ownerId: ownerId)
    }

    func fetchPublicRecipe(id: UUID) async throws -> Recipe? {
        try await recipeService.fetchPublicRecipe(id: id)
    }

    func fetchPublicRecipe(recipeId: UUID, ownerId: UUID) async throws -> Recipe {
        guard let recipe = try await recipeService.fetchPublicRecipe(id: recipeId) else {
            throw CloudKitError.invalidRecord
        }
        return recipe
    }

    func querySharedRecipes(ownerIds: [UUID]?, visibility: RecipeVisibility) async throws -> [Recipe] {
        try await recipeService.querySharedRecipes(ownerIds: ownerIds, visibility: visibility)
    }

    func deletePublicRecipe(recipeId: UUID, ownerId: UUID) async throws {
        try await recipeService.deletePublicRecipe(recipeId: recipeId)
    }

    func batchFetchPublicRecipeCounts(forOwnerIds ownerIds: [UUID]) async throws -> [UUID: Int] {
        try await recipeService.batchFetchPublicRecipeCounts(forOwnerIds: ownerIds)
    }

    func fetchPopularPublicRecipes(limit: Int = 20) async throws -> [Recipe] {
        try await recipeService.fetchPopularPublicRecipes(limit: limit)
    }

    // Legacy method that takes a CKDatabase parameter
    func uploadImageAsset(recipeId: UUID, imageData: Data, to database: CKDatabase) async throws -> String {
        let publicDB = try await core.getPublicDatabase()
        let toPublic = database == publicDB
        return try await recipeService.uploadImageAsset(recipeId: recipeId, imageData: imageData, toPublic: toPublic)
    }

    func downloadImageAsset(recipeId: UUID, from database: CKDatabase) async throws -> Data? {
        let publicDB = try await core.getPublicDatabase()
        let fromPublic = database == publicDB
        return try await recipeService.downloadImageAsset(recipeId: recipeId, fromPublic: fromPublic)
    }

    func deleteImageAsset(recipeId: UUID, from database: CKDatabase) async throws {
        let publicDB = try await core.getPublicDatabase()
        let fromPublic = database == publicDB
        try await recipeService.deleteImageAsset(recipeId: recipeId, fromPublic: fromPublic)
    }

    func saveRecipeToPublicDatabase(_ recipe: Recipe) async throws -> String {
        try await recipeService.copyRecipeToPublic(recipe)
        return recipe.id.uuidString
    }

    func recipeFromRecord(_ record: CKRecord) async throws -> Recipe {
        try await recipeService.recipeFromRecord(record)
    }

    // MARK: - Users (delegated to UserCloudService)

    func fetchCurrentUserProfile() async throws -> User? {
        try await userService.fetchCurrentUserProfile()
    }

    func fetchOrCreateCurrentUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil
    ) async throws -> User {
        try await userService.fetchOrCreateCurrentUser(
            username: username,
            displayName: displayName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
    }

    func saveUser(_ user: User) async throws {
        try await userService.saveUser(user)
    }

    func searchUsers(query: String) async throws -> [User] {
        try await userService.searchUsers(query: query)
    }

    func fetchAllUsers() async throws -> [User] {
        try await userService.fetchAllUsers()
    }

    func fetchUser(cloudRecordName: String) async throws -> User? {
        try await userService.fetchUser(cloudRecordName: cloudRecordName)
    }

    func fetchUser(byUserId userId: UUID) async throws -> User? {
        try await userService.fetchUser(byUserId: userId)
    }

    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        try await userService.fetchUsers(byUserIds: userIds)
    }

    func getCurrentUserRecordID() async throws -> CKRecord.ID {
        try await core.getCurrentUserRecordID()
    }

    func deleteUserProfile(userId: UUID) async throws {
        try await userService.deleteUserProfile(userId: userId)
    }

    func uploadUserProfileImage(userId: UUID, imageData: Data) async throws -> String {
        try await userService.uploadUserProfileImage(userId: userId, imageData: imageData)
    }

    func downloadUserProfileImage(userId: UUID) async throws -> Data? {
        try await userService.downloadUserProfileImage(userId: userId)
    }

    func deleteUserProfileImage(userId: UUID) async throws {
        try await userService.deleteUserProfileImage(userId: userId)
    }

    func lookupUserByReferralCode(_ code: String) async throws -> User? {
        try await userService.lookupUserByReferralCode(code)
    }

    func recordReferralSignup(referrerId: UUID, newUserId: UUID) async throws {
        try await userService.recordReferralSignup(referrerId: referrerId, newUserId: newUserId)
    }

    func fetchReferralCount(for userId: UUID) async throws -> Int {
        try await userService.fetchReferralCount(for: userId)
    }

    func userFromRecord(_ record: CKRecord) async throws -> User {
        try await userService.userFromRecord(record)
    }

    // MARK: - Collections (delegated to CollectionCloudService)

    func saveCollection(_ collection: Collection) async throws {
        try await collectionService.saveCollection(collection)
    }

    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        try await collectionService.fetchCollections(forUserId: userId)
    }

    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        try await collectionService.fetchSharedCollections(friendIds: friendIds)
    }

    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        try await collectionService.queryCollections(ownerIds: ownerIds, visibility: visibility)
    }

    func deleteCollection(_ collectionId: UUID) async throws {
        try await collectionService.deleteCollection(collectionId)
    }

    func uploadCollectionCoverImage(collectionId: UUID, imageData: Data) async throws -> String {
        try await collectionService.uploadCollectionCoverImage(collectionId: collectionId, imageData: imageData)
    }

    func downloadCollectionCoverImage(collectionId: UUID) async throws -> Data? {
        try await collectionService.downloadCollectionCoverImage(collectionId: collectionId)
    }

    func collectionFromRecord(_ record: CKRecord) async throws -> Collection {
        try await collectionService.collectionFromRecord(record)
    }

    // MARK: - Connections (delegated to ConnectionCloudService)

    func acceptConnectionRequest(_ connection: Connection) async throws {
        try await connectionService.acceptConnectionRequest(connection)
    }

    func rejectConnectionRequest(_ connection: Connection) async throws {
        try await connectionService.rejectConnectionRequest(connection)
    }

    func saveConnection(_ connection: Connection) async throws {
        try await connectionService.saveConnection(connection)
    }

    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        try await connectionService.fetchConnections(forUserId: userId)
    }

    func connectionExists(between userA: UUID, and userB: UUID) async throws -> Bool {
        try await connectionService.connectionExists(between: userA, and: userB)
    }

    func fetchConnections(forUserIds userIds: [UUID]) async throws -> [Connection] {
        try await connectionService.fetchConnections(forUserIds: userIds)
    }

    func deleteConnection(_ connection: Connection) async throws {
        try await connectionService.deleteConnection(connection)
    }

    func deleteAllConnectionsForUser(userId: UUID) async throws {
        try await connectionService.deleteAllConnectionsForUser(userId: userId)
    }

    func createAutoFriendConnection(referrerId: UUID, newUserId: UUID, referrerDisplayName: String?, newUserDisplayName: String?) async throws {
        try await connectionService.createAutoFriendConnection(
            referrerId: referrerId,
            newUserId: newUserId,
            referrerDisplayName: referrerDisplayName,
            newUserDisplayName: newUserDisplayName
        )
    }

    func connectionFromRecord(_ record: CKRecord) async throws -> Connection {
        try await connectionService.connectionFromRecord(record)
    }

    // MARK: - Notifications (delegated to ConnectionCloudService)

    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {
        try await connectionService.subscribeToConnectionRequests(forUserId: userId)
    }

    func unsubscribeFromConnectionRequests(forUserId userId: UUID) async throws {
        try await connectionService.unsubscribeFromConnectionRequests(forUserId: userId)
    }

    func subscribeToConnectionAcceptances(forUserId userId: UUID) async throws {
        try await connectionService.subscribeToConnectionAcceptances(forUserId: userId)
    }

    func unsubscribeFromConnectionAcceptances(forUserId userId: UUID) async throws {
        try await connectionService.unsubscribeFromConnectionAcceptances(forUserId: userId)
    }

    func subscribeToReferralSignups(forUserId userId: UUID) async throws {
        try await connectionService.subscribeToReferralSignups(forUserId: userId)
    }

    func unsubscribeFromReferralSignups(forUserId userId: UUID) async throws {
        try await connectionService.unsubscribeFromReferralSignups(forUserId: userId)
    }

    // MARK: - Search (delegated to SearchCloudService)

    func searchPublicRecipes(query: String, categories: [String]?, limit: Int = 50) async throws -> [Recipe] {
        try await searchService.searchPublicRecipes(query: query, categories: categories, limit: limit)
    }

    // MARK: - Core Infrastructure (for consumers that need low-level access)

    func optimizeImageForCloudKit(_ imageData: Data) async throws -> Data {
        try await core.optimizeImageForCloudKit(imageData)
    }

    internal func ensureCustomZone() async throws -> CKRecordZone {
        try await core.ensureCustomZone()
    }
}
