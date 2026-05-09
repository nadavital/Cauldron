//
//  RecipeDetailDisplayPolicyTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeDetailDisplayPolicyTests: XCTestCase {
    func testShouldRefreshPublicRecipeOnOpen_AllowsPreviewRecipes() {
        let currentUserId = UUID()
        let previewRecipe = Recipe(
            title: "Related Sauce",
            ingredients: [],
            steps: [],
            ownerId: UUID(),
            isPreview: true
        )

        XCTAssertTrue(
            RecipeDetailDisplayPolicy.shouldRefreshPublicRecipeOnOpen(
                previewRecipe,
                currentUserId: currentUserId
            )
        )
    }

    func testShouldRefreshPublicRecipeOnOpen_SkipsCurrentUserOwnedRecipes() {
        let currentUserId = UUID()
        let ownedRecipe = Recipe(
            title: "My Pasta",
            ingredients: [],
            steps: [],
            ownerId: currentUserId
        )

        XCTAssertFalse(
            RecipeDetailDisplayPolicy.shouldRefreshPublicRecipeOnOpen(
                ownedRecipe,
                currentUserId: currentUserId
            )
        )
    }

    func testShouldSaveAsPreviewOnOpen_SkipsExistingPreviewRecipes() {
        let previewRecipe = Recipe(
            title: "Related Sauce",
            ingredients: [],
            steps: [],
            ownerId: UUID(),
            isPreview: true
        )

        XCTAssertFalse(
            RecipeDetailDisplayPolicy.shouldSaveAsPreviewOnOpen(
                previewRecipe,
                currentUserId: UUID()
            )
        )
    }

    func testShouldSaveAsPreviewOnOpen_AllowsNonOwnedPublicRecipes() {
        let publicRecipe = Recipe(
            title: "Shared Pasta",
            ingredients: [],
            steps: [],
            ownerId: UUID()
        )

        XCTAssertTrue(
            RecipeDetailDisplayPolicy.shouldSaveAsPreviewOnOpen(
                publicRecipe,
                currentUserId: UUID()
            )
        )
    }

    func testHasHeroImage_UsesLocalOrCloudImageMetadata() {
        let noImageRecipe = Recipe(title: "No Image", ingredients: [], steps: [])
        let localImageRecipe = Recipe(
            title: "Local Image",
            ingredients: [],
            steps: [],
            imageURL: URL(fileURLWithPath: "/tmp/local-image.jpg")
        )
        let cloudImageRecipe = Recipe(
            title: "Cloud Image",
            ingredients: [],
            steps: [],
            cloudImageRecordName: "cloud-record"
        )

        XCTAssertFalse(RecipeDetailDisplayPolicy.hasHeroImage(noImageRecipe))
        XCTAssertTrue(RecipeDetailDisplayPolicy.hasHeroImage(localImageRecipe))
        XCTAssertTrue(RecipeDetailDisplayPolicy.hasHeroImage(cloudImageRecipe))
    }
}
