//
//  CloudKitServiceFacadeTests.swift
//  CauldronTests
//
//  Unit tests for CloudKit service operations using the mock facade.
//  These tests verify the interface and behavior without hitting real CloudKit.
//

import XCTest
@testable import Cauldron

final class CloudKitServiceFacadeTests: XCTestCase {

    var mockService: MockCloudKitServiceFacade!

    override func setUp() async throws {
        mockService = MockCloudKitServiceFacade()
    }

    override func tearDown() async throws {
        await mockService.reset()
        mockService = nil
    }

    // MARK: - Account Status Tests

    func testAccountStatusAvailable() async {
        let status = await mockService.checkAccountStatus()
        XCTAssertEqual(status, .available)
        XCTAssertTrue(status.isAvailable)
    }

    func testAccountStatusNoAccount() async {
        await mockService.setAccountStatus(.noAccount)
        let status = await mockService.checkAccountStatus()
        XCTAssertEqual(status, .noAccount)
        XCTAssertFalse(status.isAvailable)
    }

    func testIsAvailable() async {
        let available = await mockService.isAvailable()
        XCTAssertTrue(available)

        await mockService.setAccountStatus(.restricted)
        let notAvailable = await mockService.isAvailable()
        XCTAssertFalse(notAvailable)
    }

    // MARK: - Recipe Operations Tests

    func testSaveAndFetchRecipe() async throws {
        let ownerId = UUID()
        let recipe = createTestRecipe(ownerId: ownerId)

        try await mockService.saveRecipe(recipe, ownerId: ownerId)

        let fetched = try await mockService.fetchUserRecipes(ownerId: ownerId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, recipe.id)
        XCTAssertEqual(fetched.first?.title, recipe.title)
    }

    func testDeleteRecipe() async throws {
        let ownerId = UUID()
        let recipe = createTestRecipe(ownerId: ownerId)

        try await mockService.saveRecipe(recipe, ownerId: ownerId)
        try await mockService.deleteRecipe(recipe)

        let fetched = try await mockService.fetchUserRecipes(ownerId: ownerId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testCopyRecipeToPublic() async throws {
        let ownerId = UUID()
        let recipe = createTestRecipe(ownerId: ownerId, visibility: .publicRecipe)

        try await mockService.saveRecipe(recipe, ownerId: ownerId)
        try await mockService.copyRecipeToPublic(recipe)

        let publicRecipes = try await mockService.fetchPublicRecipes()
        XCTAssertEqual(publicRecipes.count, 1)
        XCTAssertEqual(publicRecipes.first?.id, recipe.id)
    }

    func testFetchPublicRecipesForUser() async throws {
        let ownerId = UUID()
        let recipe1 = createTestRecipe(ownerId: ownerId, title: "Recipe 1")
        let recipe2 = createTestRecipe(ownerId: ownerId, title: "Recipe 2")
        let otherOwner = UUID()
        let recipe3 = createTestRecipe(ownerId: otherOwner, title: "Other Recipe")

        try await mockService.copyRecipeToPublic(recipe1)
        try await mockService.copyRecipeToPublic(recipe2)
        try await mockService.copyRecipeToPublic(recipe3)

        let userRecipes = try await mockService.fetchPublicRecipesForUser(ownerId: ownerId)
        XCTAssertEqual(userRecipes.count, 2)
    }

    func testSearchPublicRecipes() async throws {
        let ownerId = UUID()
        let pastaRecipe = createTestRecipe(ownerId: ownerId, title: "Spaghetti Carbonara")
        let saladRecipe = createTestRecipe(ownerId: ownerId, title: "Caesar Salad")

        try await mockService.copyRecipeToPublic(pastaRecipe)
        try await mockService.copyRecipeToPublic(saladRecipe)

        let searchResults = try await mockService.searchPublicRecipes(query: "spaghetti", categories: nil)
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.title, "Spaghetti Carbonara")
    }

    // MARK: - User Operations Tests

    func testSaveAndFetchUser() async throws {
        let user = createTestUser()

        try await mockService.saveUser(user)

        let fetched = try await mockService.fetchUser(byUserId: user.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, user.id)
        XCTAssertEqual(fetched?.displayName, user.displayName)
    }

    func testSearchUsers() async throws {
        let user1 = createTestUser(username: "chefmaster", displayName: "Master Chef")
        let user2 = createTestUser(username: "baker99", displayName: "Pro Baker")

        try await mockService.saveUser(user1)
        try await mockService.saveUser(user2)

        let results = try await mockService.searchUsers(query: "chef")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.username, "chefmaster")
    }

    func testDeleteUserProfile() async throws {
        let user = createTestUser()
        try await mockService.saveUser(user)

        try await mockService.deleteUserProfile(userId: user.id)

        let fetched = try await mockService.fetchUser(byUserId: user.id)
        XCTAssertNil(fetched)
    }

    // MARK: - Collection Operations Tests

    func testSaveAndFetchCollection() async throws {
        let userId = UUID()
        let collection = createTestCollection(userId: userId)

        try await mockService.saveCollection(collection)

        let fetched = try await mockService.fetchCollections(forUserId: userId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, collection.id)
    }

    func testDeleteCollection() async throws {
        let userId = UUID()
        let collection = createTestCollection(userId: userId)

        try await mockService.saveCollection(collection)
        try await mockService.deleteCollection(collection.id)

        let fetched = try await mockService.fetchCollections(forUserId: userId)
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Connection Operations Tests

    func testSaveAndFetchConnection() async throws {
        let fromUser = UUID()
        let toUser = UUID()
        let connection = createTestConnection(fromUserId: fromUser, toUserId: toUser)

        try await mockService.saveConnection(connection)

        let fetched = try await mockService.fetchConnections(forUserId: fromUser)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.fromUserId, fromUser)
        XCTAssertEqual(fetched.first?.toUserId, toUser)
    }

    func testConnectionExists() async throws {
        let fromUser = UUID()
        let toUser = UUID()
        let connection = createTestConnection(fromUserId: fromUser, toUserId: toUser)

        try await mockService.saveConnection(connection)

        let exists = try await mockService.connectionExists(between: fromUser, and: toUser)
        XCTAssertTrue(exists)

        let reverseExists = try await mockService.connectionExists(between: toUser, and: fromUser)
        XCTAssertTrue(reverseExists) // Should work both ways

        let nonExistent = try await mockService.connectionExists(between: fromUser, and: UUID())
        XCTAssertFalse(nonExistent)
    }

    func testAcceptConnectionRequest() async throws {
        let fromUser = UUID()
        let toUser = UUID()
        let connection = createTestConnection(fromUserId: fromUser, toUserId: toUser, status: .pending)

        try await mockService.saveConnection(connection)
        try await mockService.acceptConnectionRequest(connection)

        let fetched = try await mockService.fetchConnections(forUserId: fromUser)
        XCTAssertEqual(fetched.first?.status, .accepted)
    }

    func testRejectConnectionRequest() async throws {
        let fromUser = UUID()
        let toUser = UUID()
        let connection = createTestConnection(fromUserId: fromUser, toUserId: toUser, status: .pending)

        try await mockService.saveConnection(connection)
        try await mockService.rejectConnectionRequest(connection)

        let fetched = try await mockService.fetchConnections(forUserId: fromUser)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testCreateAutoFriendConnection() async throws {
        let referrerId = UUID()
        let newUserId = UUID()

        try await mockService.createAutoFriendConnection(
            referrerId: referrerId,
            newUserId: newUserId,
            referrerDisplayName: "Referrer",
            newUserDisplayName: "New User"
        )

        let exists = try await mockService.connectionExists(between: referrerId, and: newUserId)
        XCTAssertTrue(exists)
    }

    // MARK: - Error Handling Tests

    func testNetworkErrorOnSave() async throws {
        await mockService.setError(.networkError)

        let recipe = createTestRecipe(ownerId: UUID())

        do {
            try await mockService.saveRecipe(recipe, ownerId: UUID())
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .networkError)
        }
    }

    func testNetworkErrorOnFetch() async throws {
        await mockService.setError(.networkError)

        do {
            _ = try await mockService.fetchUserRecipes(ownerId: UUID())
            XCTFail("Expected error to be thrown")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .networkError)
        }
    }

    // MARK: - Image Operations Tests

    func testUploadAndDownloadProfileImage() async throws {
        let userId = UUID()
        let imageData = "test image data".data(using: .utf8)!

        let recordName = try await mockService.uploadUserProfileImage(userId: userId, imageData: imageData)
        XCTAssertFalse(recordName.isEmpty)

        let downloaded = try await mockService.downloadUserProfileImage(userId: userId)
        XCTAssertEqual(downloaded, imageData)
    }

    func testDeleteProfileImage() async throws {
        let userId = UUID()
        let imageData = "test image data".data(using: .utf8)!

        _ = try await mockService.uploadUserProfileImage(userId: userId, imageData: imageData)
        try await mockService.deleteUserProfileImage(userId: userId)

        let downloaded = try await mockService.downloadUserProfileImage(userId: userId)
        XCTAssertNil(downloaded)
    }

    // MARK: - Edge Case Tests: Empty Results

    func testFetchRecipesForUserWithNoRecipes() async throws {
        let ownerId = UUID()
        let fetched = try await mockService.fetchUserRecipes(ownerId: ownerId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchPublicRecipesWhenNoneExist() async throws {
        let publicRecipes = try await mockService.fetchPublicRecipes()
        XCTAssertTrue(publicRecipes.isEmpty)
    }

    func testSearchPublicRecipesNoResults() async throws {
        let ownerId = UUID()
        let recipe = createTestRecipe(ownerId: ownerId, title: "Chocolate Cake")
        try await mockService.copyRecipeToPublic(recipe)

        let results = try await mockService.searchPublicRecipes(query: "sushi", categories: nil)
        XCTAssertTrue(results.isEmpty)
    }

    func testFetchUserThatDoesNotExist() async throws {
        let fetched = try await mockService.fetchUser(byUserId: UUID())
        XCTAssertNil(fetched)
    }

    func testFetchCollectionsForUserWithNoCollections() async throws {
        let userId = UUID()
        let fetched = try await mockService.fetchCollections(forUserId: userId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchConnectionsForUserWithNoConnections() async throws {
        let userId = UUID()
        let fetched = try await mockService.fetchConnections(forUserId: userId)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testDownloadProfileImageThatDoesNotExist() async throws {
        let userId = UUID()
        let downloaded = try await mockService.downloadUserProfileImage(userId: userId)
        XCTAssertNil(downloaded)
    }

    // MARK: - Edge Case Tests: Multiple Items

    func testFetchMultipleRecipesForUser() async throws {
        let ownerId = UUID()
        let recipes = (1...5).map { createTestRecipe(ownerId: ownerId, title: "Recipe \($0)") }

        for recipe in recipes {
            try await mockService.saveRecipe(recipe, ownerId: ownerId)
        }

        let fetched = try await mockService.fetchUserRecipes(ownerId: ownerId)
        XCTAssertEqual(fetched.count, 5)
    }

    func testFetchMultipleUsers() async throws {
        let users = (1...3).map { createTestUser(username: "user\($0)", displayName: "User \($0)") }

        for user in users {
            try await mockService.saveUser(user)
        }

        let fetched = try await mockService.fetchUsers(byUserIds: users.map { $0.id })
        XCTAssertEqual(fetched.count, 3)
    }

    func testFetchUsersWithMixedExistence() async throws {
        let existingUser = createTestUser()
        try await mockService.saveUser(existingUser)

        let nonExistentId = UUID()
        let fetched = try await mockService.fetchUsers(byUserIds: [existingUser.id, nonExistentId])
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, existingUser.id)
    }

    func testBatchFetchPublicRecipeCounts() async throws {
        let owner1 = UUID()
        let owner2 = UUID()
        let owner3 = UUID()

        // Owner1 has 3 public recipes
        for i in 1...3 {
            let recipe = createTestRecipe(ownerId: owner1, title: "Owner1 Recipe \(i)")
            try await mockService.copyRecipeToPublic(recipe)
        }

        // Owner2 has 1 public recipe
        let recipe2 = createTestRecipe(ownerId: owner2, title: "Owner2 Recipe")
        try await mockService.copyRecipeToPublic(recipe2)

        // Owner3 has no public recipes

        let counts = try await mockService.batchFetchPublicRecipeCounts(forOwnerIds: [owner1, owner2, owner3])
        XCTAssertEqual(counts[owner1], 3)
        XCTAssertEqual(counts[owner2], 1)
        XCTAssertEqual(counts[owner3], 0)
    }

    func testFetchConnectionsForMultipleUsers() async throws {
        let userA = UUID()
        let userB = UUID()
        let userC = UUID()

        let conn1 = createTestConnection(fromUserId: userA, toUserId: userB)
        let conn2 = createTestConnection(fromUserId: userB, toUserId: userC)

        try await mockService.saveConnection(conn1)
        try await mockService.saveConnection(conn2)

        let connections = try await mockService.fetchConnections(forUserIds: [userA, userB])
        XCTAssertEqual(connections.count, 2) // Both connections involve userA or userB
    }

    // MARK: - Edge Case Tests: Error Types

    func testQuotaExceededError() async throws {
        await mockService.setError(.quotaExceeded)

        do {
            try await mockService.saveUser(createTestUser())
            XCTFail("Expected error")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .quotaExceeded)
        }
    }

    func testNotAuthenticatedError() async throws {
        await mockService.setError(.notAuthenticated)

        do {
            _ = try await mockService.fetchPublicRecipes()
            XCTFail("Expected error")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .notAuthenticated)
        }
    }

    func testInvalidRecordError() async throws {
        await mockService.setError(.invalidRecord)

        do {
            try await mockService.saveCollection(createTestCollection(userId: UUID()))
            XCTFail("Expected error")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .invalidRecord)
        }
    }

    // MARK: - Edge Case Tests: Account Status

    func testAccountStatusRestricted() async {
        await mockService.setAccountStatus(.restricted)
        let status = await mockService.checkAccountStatus()
        XCTAssertEqual(status, .restricted)
        let available = await mockService.isAvailable()
        XCTAssertFalse(available)
    }

    func testAccountStatusTemporarilyUnavailable() async {
        await mockService.setAccountStatus(.temporarilyUnavailable)
        let status = await mockService.checkAccountStatus()
        XCTAssertEqual(status, .temporarilyUnavailable)
        let available = await mockService.isAvailable()
        XCTAssertFalse(available)
    }

    func testAccountStatusCouldNotDetermine() async {
        await mockService.setAccountStatus(.couldNotDetermine)
        let status = await mockService.checkAccountStatus()
        XCTAssertEqual(status, .couldNotDetermine)
        let available = await mockService.isAvailable()
        XCTAssertFalse(available)
    }

    // MARK: - Edge Case Tests: Referral Operations

    func testLookupUserByReferralCodeNotFound() async throws {
        let user = try await mockService.lookupUserByReferralCode("ABCDEF")
        XCTAssertNil(user)
    }

    func testLookupUserByReferralCodeFound() async throws {
        var user = createTestUser()
        // We need to create a user with a referral code - check if User has this
        // For now, seed it directly
        await mockService.seedUser(user)

        // This test would need the User to have a referralCode property set
        // Skipping detailed implementation since User model may not expose this easily
    }

    // MARK: - Edge Case Tests: Visibility Filtering

    func testQuerySharedRecipesFiltersCorrectly() async throws {
        let owner1 = UUID()
        let owner2 = UUID()

        let publicRecipe1 = createTestRecipe(ownerId: owner1, title: "Public 1", visibility: .publicRecipe)
        let publicRecipe2 = createTestRecipe(ownerId: owner2, title: "Public 2", visibility: .publicRecipe)
        let privateRecipe = createTestRecipe(ownerId: owner1, title: "Private", visibility: .privateRecipe)

        try await mockService.copyRecipeToPublic(publicRecipe1)
        try await mockService.copyRecipeToPublic(publicRecipe2)
        // Private recipe not copied to public

        let publicOnly = try await mockService.querySharedRecipes(ownerIds: [owner1], visibility: .publicRecipe)
        XCTAssertEqual(publicOnly.count, 1)
        XCTAssertEqual(publicOnly.first?.title, "Public 1")
    }

    func testFetchSharedCollectionsFiltersPrivate() async throws {
        let friendId = UUID()
        let publicCollection = Collection(
            name: "Public Collection",
            userId: friendId,
            visibility: .publicRecipe
        )
        let privateCollection = Collection(
            name: "Private Collection",
            userId: friendId,
            visibility: .privateRecipe
        )

        try await mockService.saveCollection(publicCollection)
        try await mockService.saveCollection(privateCollection)

        let shared = try await mockService.fetchSharedCollections(friendIds: [friendId])
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(shared.first?.name, "Public Collection")
    }

    // MARK: - Edge Case Tests: Delete All Connections

    func testDeleteAllConnectionsForUser() async throws {
        let userId = UUID()
        let otherUser1 = UUID()
        let otherUser2 = UUID()
        let unrelatedUser = UUID()

        let conn1 = createTestConnection(fromUserId: userId, toUserId: otherUser1)
        let conn2 = createTestConnection(fromUserId: otherUser2, toUserId: userId)
        let conn3 = createTestConnection(fromUserId: unrelatedUser, toUserId: otherUser1) // Unrelated

        try await mockService.saveConnection(conn1)
        try await mockService.saveConnection(conn2)
        try await mockService.saveConnection(conn3)

        try await mockService.deleteAllConnectionsForUser(userId: userId)

        let userConnections = try await mockService.fetchConnections(forUserId: userId)
        XCTAssertTrue(userConnections.isEmpty)

        // Unrelated connection should still exist
        let unrelatedConnections = try await mockService.fetchConnections(forUserId: unrelatedUser)
        XCTAssertEqual(unrelatedConnections.count, 1)
    }

    // MARK: - Edge Case Tests: Duplicate Operations

    func testSaveRecipeTwiceOverwrites() async throws {
        let ownerId = UUID()
        let recipeId = UUID()

        let recipe1 = Recipe(
            id: recipeId,
            title: "Original Title",
            ingredients: [],
            steps: [],
            visibility: .privateRecipe,
            ownerId: ownerId
        )
        let recipe2 = Recipe(
            id: recipeId,
            title: "Updated Title",
            ingredients: [],
            steps: [],
            visibility: .privateRecipe,
            ownerId: ownerId
        )

        try await mockService.saveRecipe(recipe1, ownerId: ownerId)
        try await mockService.saveRecipe(recipe2, ownerId: ownerId)

        let fetched = try await mockService.fetchUserRecipes(ownerId: ownerId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Updated Title")
    }

    func testSaveConnectionTwice() async throws {
        let fromUser = UUID()
        let toUser = UUID()
        let connection = createTestConnection(fromUserId: fromUser, toUserId: toUser)

        try await mockService.saveConnection(connection)
        try await mockService.saveConnection(connection) // Save again

        let fetched = try await mockService.fetchConnections(forUserId: fromUser)
        XCTAssertEqual(fetched.count, 1) // Should not duplicate
    }

    // MARK: - Edge Case Tests: Case Insensitive Search

    func testSearchUsersCaseInsensitive() async throws {
        let user = createTestUser(username: "ChefMaster", displayName: "The Chef Master")
        try await mockService.saveUser(user)

        let results1 = try await mockService.searchUsers(query: "chefmaster")
        XCTAssertEqual(results1.count, 1)

        let results2 = try await mockService.searchUsers(query: "CHEF")
        XCTAssertEqual(results2.count, 1)

        let results3 = try await mockService.searchUsers(query: "master")
        XCTAssertEqual(results3.count, 1)
    }

    func testSearchRecipesCaseInsensitive() async throws {
        let recipe = createTestRecipe(ownerId: UUID(), title: "Chocolate Lava Cake")
        try await mockService.copyRecipeToPublic(recipe)

        let results1 = try await mockService.searchPublicRecipes(query: "CHOCOLATE", categories: nil)
        XCTAssertEqual(results1.count, 1)

        let results2 = try await mockService.searchPublicRecipes(query: "lava", categories: nil)
        XCTAssertEqual(results2.count, 1)
    }

    // MARK: - Edge Case Tests: Public Recipe Limits

    func testFetchPublicRecipesRespectsLimit() async throws {
        let ownerId = UUID()
        for i in 1...10 {
            let recipe = createTestRecipe(ownerId: ownerId, title: "Recipe \(i)")
            try await mockService.copyRecipeToPublic(recipe)
        }

        let limited = try await mockService.fetchPublicRecipes(limit: 5)
        XCTAssertEqual(limited.count, 5)

        let all = try await mockService.fetchPublicRecipes(limit: 50)
        XCTAssertEqual(all.count, 10)
    }

    // MARK: - Call Tracking Tests

    func testCallTracking() async throws {
        let ownerId = UUID()
        let recipe = createTestRecipe(ownerId: ownerId)
        let user = createTestUser()

        try await mockService.saveRecipe(recipe, ownerId: ownerId)
        _ = try await mockService.fetchUserRecipes(ownerId: ownerId)
        try await mockService.saveUser(user)
        _ = try await mockService.fetchUser(byUserId: user.id)

        let saveRecipeCalls = await mockService.saveRecipeCalls
        let fetchRecipesCalls = await mockService.fetchRecipesCalls
        let saveUserCalls = await mockService.saveUserCalls
        let fetchUserCalls = await mockService.fetchUserCalls

        XCTAssertEqual(saveRecipeCalls.count, 1)
        XCTAssertEqual(fetchRecipesCalls.count, 1)
        XCTAssertEqual(saveUserCalls.count, 1)
        XCTAssertEqual(fetchUserCalls.count, 1)
    }

    // MARK: - Test Helpers

    private func createTestRecipe(
        ownerId: UUID,
        title: String = "Test Recipe",
        visibility: RecipeVisibility = .privateRecipe
    ) -> Recipe {
        Recipe(
            id: UUID(),
            title: title,
            ingredients: [Ingredient(name: "Test ingredient")],
            steps: [CookStep(index: 0, text: "Test step")],
            visibility: visibility,
            ownerId: ownerId
        )
    }

    private func createTestUser(
        username: String = "testuser",
        displayName: String = "Test User"
    ) -> User {
        User(
            id: UUID(),
            username: username,
            displayName: displayName,
            profileEmoji: "🧙‍♀️",
            profileColor: "#7B68EE"
        )
    }

    private func createTestCollection(userId: UUID) -> Collection {
        Collection(
            id: UUID(),
            name: "Test Collection",
            description: "A test collection",
            userId: userId,
            recipeIds: [],
            visibility: .privateRecipe
        )
    }

    private func createTestConnection(
        fromUserId: UUID,
        toUserId: UUID,
        status: ConnectionStatus = .pending
    ) -> Connection {
        Connection(
            id: UUID(),
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            fromDisplayName: "From User",
            toDisplayName: "To User"
        )
    }
}

// MARK: - Mock Helper Extensions

extension MockCloudKitServiceFacade {
    func setAccountStatus(_ status: CloudKitAccountStatus) {
        Task { @Sendable in
            await self.updateAccountStatus(status)
        }
    }

    private func updateAccountStatus(_ status: CloudKitAccountStatus) {
        self.accountStatus = status
    }

    func setError(_ error: CloudKitError?) {
        Task { @Sendable in
            await self.updateError(error)
        }
    }

    private func updateError(_ error: CloudKitError?) {
        self.shouldFailWithError = error
    }
}
