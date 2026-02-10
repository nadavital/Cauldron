//
//  RecipeGroupingServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeGroupingServiceTests: XCTestCase {
    func testGroupAndRankRecipes_PrioritizesExactTitleMatch() {
        let currentUserId = UUID()
        let owner1 = UUID()
        let owner2 = UUID()

        let exact = makeRecipe(
            title: "Spicy Chili",
            ownerId: owner1,
            tags: ["Dinner"],
            ingredients: ["ground beef"]
        )
        let partial = makeRecipe(
            title: "Chili Oil Noodles",
            ownerId: owner2,
            tags: ["Noodles"],
            ingredients: ["noodles"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [partial, exact],
            friends: [],
            currentUserId: currentUserId,
            filterText: "Spicy Chili"
        )

        XCTAssertEqual(groups.first?.primaryRecipe.id, exact.id)
    }

    func testGroupAndRankRecipes_BoostsFriendSaves() {
        let currentUserId = UUID()
        let friendId = UUID()
        let owner2 = UUID()

        let friend = User(id: friendId, username: "friend", displayName: "Friend Chef")

        let baseId = UUID()
        let friendSavedCopy = makeRecipe(
            id: UUID(),
            title: "Tomato Soup",
            ownerId: friendId,
            tags: ["Soup"],
            ingredients: ["tomato"],
            originalRecipeId: baseId
        )
        let other = makeRecipe(
            title: "Tomato Soup",
            ownerId: owner2,
            tags: ["Soup"],
            ingredients: ["tomato"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [other, friendSavedCopy],
            friends: [friend],
            currentUserId: currentUserId,
            filterText: "tomato soup"
        )

        XCTAssertFalse(groups.isEmpty)
        XCTAssertFalse(groups[0].friendSavers.isEmpty)
    }

    func testGroupAndRankRecipes_MatchesIngredientTokens() {
        let currentUserId = UUID()
        let owner1 = UUID()
        let owner2 = UUID()

        let ingredientMatch = makeRecipe(
            title: "Simple Pasta",
            ownerId: owner1,
            tags: ["Dinner"],
            ingredients: ["garlic", "olive oil", "pasta"]
        )
        let noMatch = makeRecipe(
            title: "Banana Bread",
            ownerId: owner2,
            tags: ["Dessert"],
            ingredients: ["banana", "flour", "sugar"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [noMatch, ingredientMatch],
            friends: [],
            currentUserId: currentUserId,
            filterText: "garlic pasta"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.primaryRecipe.id, ingredientMatch.id)
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        ownerId: UUID,
        tags: [String],
        ingredients: [String],
        originalRecipeId: UUID? = nil
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: ingredients.map { Ingredient(name: $0, quantity: nil) },
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "2 servings",
            tags: tags.compactMap { Tag(name: $0) },
            ownerId: ownerId,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId
        )
    }
}
