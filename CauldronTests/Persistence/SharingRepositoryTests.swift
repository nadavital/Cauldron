//
//  SharingRepositoryTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class SharingRepositoryTests: XCTestCase {

    var repository: SharingRepository!
    var modelContainer: ModelContainer!
    var testUser1: User!
    var testUser2: User!
    var testRecipe: Recipe!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        modelContainer = try TestModelContainer.create(with: [
            UserModel.self,
            SharedRecipeModel.self
        ])

        // Initialize repository
        repository = SharingRepository(modelContainer: modelContainer)

        // Create test users
        testUser1 = User(
            username: "user1",
            displayName: "Test User One",
            email: "user1@test.com",
            profileEmoji: "👨‍🍳",
            profileColor: "#FF5733"
        )

        testUser2 = User(
            username: "user2",
            displayName: "Test User Two",
            email: "user2@test.com",
            profileEmoji: "👩‍🍳",
            profileColor: "#33FF57"
        )

        // Create test recipe
        testRecipe = Recipe(
            id: UUID(),
            title: "Test Recipe",
            ingredients: [Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup))],
            steps: [CookStep(index: 0, text: "Mix ingredients")],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [Tag(name: "test")],
            sourceURL: nil,
            sourceTitle: nil,
            notes: "A test recipe",
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: testUser1.id,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    override func tearDown() async throws {
        repository = nil
        modelContainer = nil
        testUser1 = nil
        testUser2 = nil
        testRecipe = nil
        try await super.tearDown()
    }

    // MARK: - User Tests

    func testSaveUser_CreatesNewUser() async throws {
        // When
        try await repository.save(testUser1)

        // Then
        let fetched = try await repository.fetchUser(id: testUser1.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, testUser1.id)
        XCTAssertEqual(fetched?.username, "user1")
        XCTAssertEqual(fetched?.displayName, "Test User One")
        XCTAssertEqual(fetched?.profileEmoji, "👨‍🍳")
    }

    func testSaveUser_UpdatesExistingUser() async throws {
        // Given
        try await repository.save(testUser1)

        // When - Update user
        let updatedUser = User(
            id: testUser1.id,
            username: "user1",
            displayName: "Updated Name",
            email: testUser1.email,
            profileEmoji: "🍳",
            profileColor: "#FFFFFF"
        )
        try await repository.save(updatedUser)

        // Then
        let fetched = try await repository.fetchUser(id: testUser1.id)
        XCTAssertEqual(fetched?.displayName, "Updated Name")
        XCTAssertEqual(fetched?.profileEmoji, "🍳")
        XCTAssertEqual(fetched?.profileColor, "#FFFFFF")
    }

    func testFetchUser_NotFound() async throws {
        // When
        let fetched = try await repository.fetchUser(id: UUID())

        // Then
        XCTAssertNil(fetched)
    }

    func testFetchAllUsers_EmptyList() async throws {
        // When
        let users = try await repository.fetchAllUsers()

        // Then
        XCTAssertEqual(users.count, 0)
    }

    func testFetchAllUsers_ReturnsAllUsers() async throws {
        // Given
        try await repository.save(testUser1)
        try await repository.save(testUser2)

        // When
        let users = try await repository.fetchAllUsers()

        // Then
        XCTAssertEqual(users.count, 2)
        XCTAssertTrue(users.contains { $0.id == testUser1.id })
        XCTAssertTrue(users.contains { $0.id == testUser2.id })
    }

    func testFetchAllUsers_SortedByUsername() async throws {
        // Given - Add users in reverse alphabetical order
        try await repository.save(testUser2) // user2
        try await repository.save(testUser1) // user1

        // When
        let users = try await repository.fetchAllUsers()

        // Then - Should be sorted by username
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users[0].username, "user1")
        XCTAssertEqual(users[1].username, "user2")
    }

    // MARK: - Search Users Tests

    func testSearchUsers_ByUsername() async throws {
        // Given
        try await repository.save(testUser1)
        try await repository.save(testUser2)

        // When
        let results = try await repository.searchUsers("user1")

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.username, "user1")
    }

    func testSearchUsers_ByDisplayName() async throws {
        // Given
        try await repository.save(testUser1)
        try await repository.save(testUser2)

        // When
        let results = try await repository.searchUsers("Test User One")

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.displayName, "Test User One")
    }

    func testSearchUsers_CaseInsensitive() async throws {
        // Given
        try await repository.save(testUser1)

        // When
        let results = try await repository.searchUsers("USER1")

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.username, "user1")
    }

    func testSearchUsers_PartialMatch() async throws {
        // Given
        try await repository.save(testUser1)
        try await repository.save(testUser2)

        // When
        let results = try await repository.searchUsers("user")

        // Then - Should match both users
        XCTAssertEqual(results.count, 2)
    }

    func testSearchUsers_NoMatches() async throws {
        // Given
        try await repository.save(testUser1)

        // When
        let results = try await repository.searchUsers("nonexistent")

        // Then
        XCTAssertEqual(results.count, 0)
    }

    func testSearchUsers_EmptyQuery_ReturnsEmpty() async throws {
        // Given
        try await repository.save(testUser1)

        // When
        let results = try await repository.searchUsers("")

        // Then - Empty query should return empty results (not all users)
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Shared Recipe Tests

    func testSaveSharedRecipe_CreatesNew() async throws {
        // Given
        let sharedRecipe = SharedRecipe(
            recipe: testRecipe,
            sharedBy: testUser1
        )

        // When
        try await repository.saveSharedRecipe(sharedRecipe)

        // Then
        let fetched = try await repository.fetchSharedRecipe(id: sharedRecipe.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, sharedRecipe.id)
        XCTAssertEqual(fetched?.recipe.id, testRecipe.id)
        XCTAssertEqual(fetched?.sharedBy.id, testUser1.id)
    }

    func testSaveSharedRecipe_DoesNotDuplicate() async throws {
        // Given
        let sharedRecipe = SharedRecipe(
            recipe: testRecipe,
            sharedBy: testUser1
        )

        // When - Save twice
        try await repository.saveSharedRecipe(sharedRecipe)
        try await repository.saveSharedRecipe(sharedRecipe)

        // Then - Should only have one
        let allShared = try await repository.fetchAllSharedRecipes()
        XCTAssertEqual(allShared.count, 1)
    }

    func testFetchSharedRecipe_NotFound() async throws {
        // When
        let fetched = try await repository.fetchSharedRecipe(id: UUID())

        // Then
        XCTAssertNil(fetched)
    }

    func testFetchAllSharedRecipes_EmptyList() async throws {
        // When
        let shared = try await repository.fetchAllSharedRecipes()

        // Then
        XCTAssertEqual(shared.count, 0)
    }

    func testFetchAllSharedRecipes_ReturnsAll() async throws {
        // Given
        let sharedRecipe1 = SharedRecipe(recipe: testRecipe, sharedBy: testUser1)

        let testRecipe2 = Recipe(
            id: UUID(),
            title: "Another Recipe",
            ingredients: [Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup))],
            steps: [CookStep(index: 0, text: "Stir")],
            yields: "2 servings",
            totalMinutes: 15,
            notes: "Another test",
            ownerId: testUser2.id
        )
        let sharedRecipe2 = SharedRecipe(recipe: testRecipe2, sharedBy: testUser2)

        try await repository.saveSharedRecipe(sharedRecipe1)
        try await repository.saveSharedRecipe(sharedRecipe2)

        // When
        let shared = try await repository.fetchAllSharedRecipes()

        // Then
        XCTAssertEqual(shared.count, 2)
        XCTAssertTrue(shared.contains { $0.id == sharedRecipe1.id })
        XCTAssertTrue(shared.contains { $0.id == sharedRecipe2.id })
    }

    func testDeleteSharedRecipe_RemovesRecipe() async throws {
        // Given
        let sharedRecipe = SharedRecipe(recipe: testRecipe, sharedBy: testUser1)
        try await repository.saveSharedRecipe(sharedRecipe)

        // When
        try await repository.deleteSharedRecipe(id: sharedRecipe.id)

        // Then
        let fetched = try await repository.fetchSharedRecipe(id: sharedRecipe.id)
        XCTAssertNil(fetched)
    }

    func testDeleteSharedRecipe_NonExistent_DoesNotThrow() async throws {
        // When/Then - Should not throw
        try await repository.deleteSharedRecipe(id: UUID())
    }

    func testDeleteSharedRecipe_OnlyRemovesSpecific() async throws {
        // Given
        let sharedRecipe1 = SharedRecipe(recipe: testRecipe, sharedBy: testUser1)
        let testRecipe2 = Recipe(
            id: UUID(),
            title: "Another Recipe",
            ingredients: [Ingredient(name: "water", quantity: Quantity(value: 1, unit: .cup))],
            steps: [CookStep(index: 0, text: "Boil")],
            yields: "2 servings",
            totalMinutes: 10,
            notes: "Test",
            ownerId: testUser2.id
        )
        let sharedRecipe2 = SharedRecipe(recipe: testRecipe2, sharedBy: testUser2)

        try await repository.saveSharedRecipe(sharedRecipe1)
        try await repository.saveSharedRecipe(sharedRecipe2)

        // When
        try await repository.deleteSharedRecipe(id: sharedRecipe1.id)

        // Then
        let fetched1 = try await repository.fetchSharedRecipe(id: sharedRecipe1.id)
        let fetched2 = try await repository.fetchSharedRecipe(id: sharedRecipe2.id)
        XCTAssertNil(fetched1)
        XCTAssertNotNil(fetched2)
    }

    func testDeleteAllSharedRecipes_RemovesAll() async throws {
        // Given
        let sharedRecipe1 = SharedRecipe(recipe: testRecipe, sharedBy: testUser1)
        let testRecipe2 = Recipe(
            id: UUID(),
            title: "Another Recipe",
            ingredients: [Ingredient(name: "water", quantity: Quantity(value: 1, unit: .cup))],
            steps: [CookStep(index: 0, text: "Boil")],
            yields: "2 servings",
            totalMinutes: 10,
            notes: "Test",
            ownerId: testUser2.id
        )
        let sharedRecipe2 = SharedRecipe(recipe: testRecipe2, sharedBy: testUser2)

        try await repository.saveSharedRecipe(sharedRecipe1)
        try await repository.saveSharedRecipe(sharedRecipe2)

        // When
        try await repository.deleteAllSharedRecipes()

        // Then
        let all = try await repository.fetchAllSharedRecipes()
        XCTAssertEqual(all.count, 0)
    }

    func testDeleteAllSharedRecipes_EmptyRepository_DoesNotThrow() async throws {
        // When/Then - Should not throw
        try await repository.deleteAllSharedRecipes()

        let all = try await repository.fetchAllSharedRecipes()
        XCTAssertEqual(all.count, 0)
    }
}
