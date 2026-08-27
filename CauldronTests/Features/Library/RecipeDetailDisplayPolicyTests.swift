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

    func testShouldRefreshHeroImage_SkipsMetadataOnlyRecipeRefresh() {
        let id = UUID()
        let imageURL = URL(fileURLWithPath: "/tmp/recipe.jpg")
        let current = Recipe(
            id: id,
            title: "Pasta",
            ingredients: [],
            steps: [],
            imageURL: imageURL,
            cloudRecordName: "recipe-record",
            cloudImageRecordName: "image-record"
        )
        let updated = Recipe(
            id: id,
            title: "Better Pasta",
            ingredients: [],
            steps: [],
            imageURL: imageURL,
            cloudRecordName: "recipe-record",
            cloudImageRecordName: "image-record"
        )

        XCTAssertFalse(
            RecipeDetailDisplayPolicy.shouldRefreshHeroImage(from: current, to: updated)
        )
    }

    func testShouldRefreshHeroImage_DetectsChangedImageIdentity() {
        let current = Recipe(
            title: "Pasta",
            ingredients: [],
            steps: [],
            imageURL: URL(fileURLWithPath: "/tmp/old.jpg"),
            cloudImageRecordName: "old-image"
        )
        let updated = Recipe(
            id: current.id,
            title: current.title,
            ingredients: [],
            steps: [],
            imageURL: URL(fileURLWithPath: "/tmp/new.jpg"),
            cloudImageRecordName: "new-image"
        )

        XCTAssertTrue(
            RecipeDetailDisplayPolicy.shouldRefreshHeroImage(from: current, to: updated)
        )
    }

    func testShouldRefreshHeroImage_DetectsInPlaceCloudAssetUpdate() {
        let originalModifiedAt = Date(timeIntervalSince1970: 1_000)
        let current = Recipe(
            title: "Pasta",
            ingredients: [],
            steps: [],
            cloudRecordName: "recipe-record",
            cloudImageRecordName: "image-record",
            imageModifiedAt: originalModifiedAt
        )
        let updated = Recipe(
            id: current.id,
            title: current.title,
            ingredients: [],
            steps: [],
            cloudRecordName: "recipe-record",
            cloudImageRecordName: "image-record",
            imageModifiedAt: originalModifiedAt.addingTimeInterval(60)
        )

        XCTAssertTrue(
            RecipeDetailDisplayPolicy.shouldRefreshHeroImage(from: current, to: updated)
        )
    }
}
