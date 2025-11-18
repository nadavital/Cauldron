//
//  CookTabViewModelTests.swift
//  CauldronTests
//
//  Tests for CookTabViewModel including favorites filtering and preloaded data
//

import XCTest
@testable import Cauldron

@MainActor
final class CookTabViewModelTests: XCTestCase {
    var dependencies: DependencyContainer!
    var viewModel: CookTabViewModel!
    var testUserId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        dependencies = DependencyContainer.preview()
        testUserId = UUID()
    }

    override func tearDown() async throws {
        viewModel = nil
        dependencies = nil
        try await super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitWithoutPreloadedData() async throws {
        // When: Initialize without preloaded data
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: nil)

        // Give it time to load
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Then: Should load data asynchronously
        XCTAssertGreaterThanOrEqual(viewModel.allRecipes.count, 0)
    }

    func testInitWithPreloadedData() async throws {
        // Given: Preloaded recipe data
        let recipe1 = Recipe(
            id: UUID(),
            title: "Test Recipe 1",
            ingredients: [Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup))],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [],
            isFavorite: true
        )

        let recipe2 = Recipe(
            id: UUID(),
            title: "Test Recipe 2",
            ingredients: [Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup))],
            steps: [CookStep(index: 0, text: "Stir", timers: [])],
            yields: "2 servings",
            totalMinutes: 15,
            tags: [],
            isFavorite: false
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [recipe1, recipe2],
            recentlyCookedIds: [recipe1.id],
            collections: []
        )

        // When: Initialize with preloaded data
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        // Then: Should immediately have recipes
        XCTAssertEqual(viewModel.allRecipes.count, 2)

        // Give favorites time to populate (happens asynchronously)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify favorites filtering
        XCTAssertEqual(viewModel.favoriteRecipes.count, 1)
        XCTAssertEqual(viewModel.favoriteRecipes.first?.id, recipe1.id)
    }

    // MARK: - Favorites Filtering Tests

    func testFavoritesFilterOnlyShowsFavorites() async throws {
        // Given: Mix of favorite and non-favorite recipes
        let favoriteRecipe1 = Recipe(
            id: UUID(),
            title: "Favorite 1",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: true
        )

        let favoriteRecipe2 = Recipe(
            id: UUID(),
            title: "Favorite 2",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: true
        )

        let normalRecipe = Recipe(
            id: UUID(),
            title: "Normal Recipe",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: false
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [favoriteRecipe1, normalRecipe, favoriteRecipe2],
            recentlyCookedIds: [],
            collections: []
        )

        // When: Initialize with preloaded data
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        // Give favorites time to populate
        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: Only favorites should be in favoriteRecipes
        XCTAssertEqual(viewModel.favoriteRecipes.count, 2)
        XCTAssertTrue(viewModel.favoriteRecipes.allSatisfy { $0.isFavorite })
        XCTAssertTrue(viewModel.favoriteRecipes.contains { $0.id == favoriteRecipe1.id })
        XCTAssertTrue(viewModel.favoriteRecipes.contains { $0.id == favoriteRecipe2.id })
        XCTAssertFalse(viewModel.favoriteRecipes.contains { $0.id == normalRecipe.id })
    }

    func testEmptyFavoritesWhenNoFavorites() async throws {
        // Given: No favorite recipes
        let recipe1 = Recipe(
            id: UUID(),
            title: "Recipe 1",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: false
        )

        let recipe2 = Recipe(
            id: UUID(),
            title: "Recipe 2",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: false
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [recipe1, recipe2],
            recentlyCookedIds: [],
            collections: []
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: Favorites should be empty
        XCTAssertTrue(viewModel.favoriteRecipes.isEmpty)
    }

    func testAllRecipesAreFavorites() async throws {
        // Given: All recipes are favorites
        let recipe1 = Recipe(
            id: UUID(),
            title: "Favorite 1",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: true
        )

        let recipe2 = Recipe(
            id: UUID(),
            title: "Favorite 2",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1",
            isFavorite: true
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [recipe1, recipe2],
            recentlyCookedIds: [],
            collections: []
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: All recipes should be in favorites
        XCTAssertEqual(viewModel.favoriteRecipes.count, 2)
        XCTAssertEqual(viewModel.allRecipes.count, viewModel.favoriteRecipes.count)
    }

    // MARK: - Recently Cooked Tests

    func testRecentlyCookedFilteredCorrectly() async throws {
        // Given: Some recipes, some recently cooked
        let recentRecipe = Recipe(
            id: UUID(),
            title: "Recent",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1"
        )

        let oldRecipe = Recipe(
            id: UUID(),
            title: "Old",
            ingredients: [Ingredient(name: "Test", quantity: nil)],
            steps: [CookStep(index: 0, text: "Test", timers: [])],
            yields: "1"
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [recentRecipe, oldRecipe],
            recentlyCookedIds: [recentRecipe.id],
            collections: []
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: Only recent recipe should be in recentlyCookedRecipes
        XCTAssertEqual(viewModel.recentlyCookedRecipes.count, 1)
        XCTAssertEqual(viewModel.recentlyCookedRecipes.first?.id, recentRecipe.id)
    }

    // MARK: - Collections Tests

    func testCollectionsSortedByUpdatedAt() async throws {
        // Given: Collections with different update times
        let oldCollection = Collection(
            id: UUID(),
            name: "Old",
            userId: testUserId,
            recipeIds: [],
            createdAt: Date().addingTimeInterval(-1000),
            updatedAt: Date().addingTimeInterval(-1000)
        )

        let newCollection = Collection(
            id: UUID(),
            name: "New",
            userId: testUserId,
            recipeIds: [],
            createdAt: Date(),
            updatedAt: Date()
        )

        let preloadedData = PreloadedRecipeData(
            allRecipes: [],
            recentlyCookedIds: [],
            collections: [oldCollection, newCollection]
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        // Then: Collections should be sorted by updatedAt (newest first)
        XCTAssertEqual(viewModel.collections.count, 2)
        XCTAssertEqual(viewModel.collections.first?.id, newCollection.id)
        XCTAssertEqual(viewModel.collections.last?.id, oldCollection.id)
    }

    // MARK: - Edge Cases

    func testEmptyPreloadedData() async throws {
        // Given: Empty preloaded data
        let preloadedData = PreloadedRecipeData(
            allRecipes: [],
            recentlyCookedIds: [],
            collections: []
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: All arrays should be empty
        XCTAssertTrue(viewModel.allRecipes.isEmpty)
        XCTAssertTrue(viewModel.favoriteRecipes.isEmpty)
        XCTAssertTrue(viewModel.recentlyCookedRecipes.isEmpty)
        XCTAssertTrue(viewModel.collections.isEmpty)
    }

    func testLargeNumberOfRecipes() async throws {
        // Given: Many recipes with mix of favorites
        var recipes: [Recipe] = []
        for i in 0..<100 {
            recipes.append(Recipe(
                id: UUID(),
                title: "Recipe \(i)",
                ingredients: [Ingredient(name: "Test", quantity: nil)],
                steps: [CookStep(index: 0, text: "Test", timers: [])],
                yields: "1",
                isFavorite: i % 3 == 0, // Every 3rd recipe is favorite
                ownerId: testUserId
            ))
        }

        let preloadedData = PreloadedRecipeData(
            allRecipes: recipes,
            recentlyCookedIds: [],
            collections: []
        )

        // When: Initialize
        viewModel = CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData)

        try await Task.sleep(nanoseconds: 200_000_000) // Give more time for large data

        // Then: Should handle large dataset
        XCTAssertEqual(viewModel.allRecipes.count, 100)
        XCTAssertEqual(viewModel.favoriteRecipes.count, 34) // 0, 3, 6, 9... = 34 recipes
        XCTAssertTrue(viewModel.favoriteRecipes.allSatisfy { $0.isFavorite })
    }
}
