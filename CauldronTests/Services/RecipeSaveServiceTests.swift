//
//  RecipeSaveServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class RecipeSaveServiceTests: XCTestCase {
    private var dependencies: DependencyContainer!
    private var currentUserId: UUID!
    private var sourceOwnerId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        CurrentUserSession.shared.signOut()
        dependencies = DependencyContainer.preview()
        currentUserId = UUID()
        sourceOwnerId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "saver",
                displayName: "Saver",
                createdAt: Date()
            )
        )
    }

    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        dependencies = nil
        currentUserId = nil
        sourceOwnerId = nil
        try await super.tearDown()
    }

    func testSaveRecipeToLibrary_createsOwnedCopyWithAttributionAndReusesOnRepeatSave() async throws {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Pasta",
            ownerId: sourceOwnerId
        )

        let firstSave = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertFalse(firstSave.reusedExistingCopy)
        XCTAssertEqual(firstSave.savedRelatedRecipeCount, 0)
        XCTAssertNotEqual(firstSave.recipe.id, sourceRecipeId)
        XCTAssertEqual(firstSave.recipe.ownerId, currentUserId)
        XCTAssertEqual(firstSave.recipe.originalRecipeId, sourceRecipeId)
        XCTAssertEqual(firstSave.recipe.originalCreatorId, sourceOwnerId)
        XCTAssertEqual(firstSave.recipe.originalCreatorName, "Source Chef")
        XCTAssertTrue(firstSave.recipe.followsSourceUpdates)
        XCTAssertFalse(firstSave.recipe.isPreview)

        let secondSave = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertTrue(secondSave.reusedExistingCopy)
        XCTAssertEqual(secondSave.recipe.id, firstSave.recipe.id)

        let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId]
        )
        XCTAssertEqual(ownedCopies.count, 1)
    }

    func testSaveRecipeToLibrary_convertsExistingPreviewToOwnedCopy() async throws {
        let sourceRecipeId = UUID()
        let preview = makeRecipe(
            id: sourceRecipeId,
            title: "Preview Curry",
            ownerId: sourceOwnerId,
            isPreview: true
        )
        try await dependencies.recipeRepository.create(preview, skipCloudSync: true)

        let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            preview,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertFalse(result.reusedExistingCopy)
        XCTAssertNotEqual(result.recipe.id, sourceRecipeId)
        XCTAssertEqual(result.recipe.ownerId, currentUserId)
        XCTAssertEqual(result.recipe.originalRecipeId, sourceRecipeId)
        XCTAssertEqual(result.recipe.originalCreatorId, sourceOwnerId)
        XCTAssertEqual(result.recipe.originalCreatorName, "Source Chef")
        XCTAssertTrue(result.recipe.followsSourceUpdates)
        XCTAssertFalse(result.recipe.isPreview)

        let oldPreview = try await dependencies.recipeRepository.fetch(id: sourceRecipeId)
        XCTAssertNil(oldPreview)
        let previewWasTombstoned = try await dependencies.deletedRecipeRepository.isDeleted(recipeId: sourceRecipeId)
        XCTAssertFalse(previewWasTombstoned)
    }

    func testSaveRecipeToLibraryDoesNotReuseNonOwnedDirectLocalRecipe() async throws {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Noodles",
            ownerId: sourceOwnerId
        )
        try await dependencies.recipeRepository.create(sourceRecipe, skipCloudSync: true)

        let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertFalse(result.reusedExistingCopy)
        XCTAssertNotEqual(result.recipe.id, sourceRecipeId)
        XCTAssertEqual(result.recipe.ownerId, currentUserId)
        XCTAssertEqual(result.recipe.originalRecipeId, sourceRecipeId)
    }

    func testSaveRecipeToLibrary_savesAndRemapsRequestedRelatedRecipes() async throws {
        let relatedSourceId = UUID()
        let relatedRecipe = makeRecipe(
            id: relatedSourceId,
            title: "Shared Sauce",
            ownerId: sourceOwnerId
        )
        let sourceRecipe = makeRecipe(
            id: UUID(),
            title: "Shared Dinner",
            ownerId: sourceOwnerId,
            relatedRecipeIds: [relatedSourceId]
        )

        let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef",
            relatedRecipesToSave: [relatedRecipe]
        )

        XCTAssertEqual(result.savedRelatedRecipeCount, 1)
        XCTAssertEqual(result.recipe.relatedRecipeIds.count, 1)
        XCTAssertNotEqual(result.recipe.relatedRecipeIds.first, relatedSourceId)

        let relatedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [relatedSourceId]
        )
        XCTAssertEqual(relatedCopies.count, 1)
        XCTAssertEqual(result.recipe.relatedRecipeIds.first, relatedCopies.first?.id)
    }

    func testSaveRecipeToLibraryDoesNotReuseNonOwnedDirectLocalRelatedRecipe() async throws {
        let relatedSourceId = UUID()
        let relatedRecipe = makeRecipe(
            id: relatedSourceId,
            title: "Shared Salsa",
            ownerId: sourceOwnerId
        )
        try await dependencies.recipeRepository.create(relatedRecipe, skipCloudSync: true)

        let sourceRecipe = makeRecipe(
            id: UUID(),
            title: "Shared Tacos",
            ownerId: sourceOwnerId,
            relatedRecipeIds: [relatedSourceId]
        )

        let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef",
            relatedRecipesToSave: [relatedRecipe]
        )

        let relatedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [relatedSourceId],
            ownerId: currentUserId
        )

        XCTAssertEqual(relatedCopies.count, 1)
        XCTAssertEqual(result.recipe.relatedRecipeIds.first, relatedCopies.first?.id)
        XCTAssertNotEqual(result.recipe.relatedRecipeIds.first, relatedSourceId)
    }

    private func makeRecipe(
        id: UUID,
        title: String,
        ownerId: UUID,
        relatedRecipeIds: [UUID] = [],
        isPreview: Bool = false
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: .publicRecipe,
            ownerId: ownerId,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
}
