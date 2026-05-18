//
//  RecipeDeduplicationTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeDeduplicationTests: XCTestCase {
    func testByIdPreferringBestDoesNotTrapOnDuplicateRecipeIds() {
        let recipeId = UUID()
        let ownerId = UUID()
        let olderPreview = Recipe(
            id: recipeId,
            title: "Preview",
            ingredients: [],
            steps: [],
            visibility: .publicRecipe,
            ownerId: ownerId,
            updatedAt: Date(timeIntervalSince1970: 100),
            isPreview: true
        )
        let ownedRecipe = Recipe(
            id: recipeId,
            title: "Owned",
            ingredients: [],
            steps: [],
            visibility: .publicRecipe,
            ownerId: ownerId,
            cloudRecordName: "recipe-\(recipeId.uuidString)",
            updatedAt: Date(timeIntervalSince1970: 90),
            isPreview: false
        )

        let recipesById = RecipeDeduplication.byIdPreferringBest([olderPreview, ownedRecipe])

        XCTAssertEqual(recipesById[recipeId]?.title, "Owned")
        XCTAssertEqual(recipesById.count, 1)
    }
}
