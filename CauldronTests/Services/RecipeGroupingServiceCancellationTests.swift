//
//  RecipeGroupingServiceCancellationTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeGroupingServiceCancellationTests: XCTestCase {
    func testGroupAndRankRecipesReturnsEarlyWhenTaskIsCancelled() async {
        let recipes = (0..<5_000).map { index in
            Recipe(
                id: UUID(),
                title: "Recipe \(index)",
                ingredients: [Ingredient(name: "Ingredient \(index)", quantity: nil)],
                steps: [CookStep(index: 0, text: "Cook", timers: [])],
                yields: "2 servings",
                tags: [Tag(name: "Dinner")],
                ownerId: UUID(),
                updatedAt: Date()
            )
        }

        let task = Task.detached(priority: .userInitiated) { () -> [SearchRecipeGroup] in
            try? await Task.sleep(nanoseconds: 50_000_000)
            return RecipeGroupingService.groupAndRankRecipes(
                localRecipes: recipes,
                publicRecipes: [],
                friends: [],
                currentUserId: UUID(),
                filterText: "Recipe"
            )
        }

        task.cancel()
        let groups = await task.value

        XCTAssertTrue(groups.isEmpty)
    }
}
