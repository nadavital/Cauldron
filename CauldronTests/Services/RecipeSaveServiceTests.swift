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

    func testSaveRecipeToLibraryCreatesReferenceWithoutOwnedCopyAndReusesOnRepeatSave() async throws {
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
        XCTAssertEqual(firstSave.recipe.id, sourceRecipeId)
        XCTAssertEqual(firstSave.recipe.ownerId, sourceOwnerId)
        XCTAssertEqual(firstSave.savedReference?.sourceRecipeId, sourceRecipeId)
        XCTAssertEqual(firstSave.savedReference?.userId, currentUserId)
        XCTAssertNil(firstSave.savedReference?.materializedRecipeId)

        let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId]
        )
        XCTAssertEqual(ownedCopies.count, 0)

        let secondSave = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertTrue(secondSave.reusedExistingCopy)
        XCTAssertEqual(secondSave.recipe.id, sourceRecipeId)
        XCTAssertEqual(secondSave.savedReference?.id, firstSave.savedReference?.id)

        let references = try await dependencies.savedReferenceRepository.recipeReferences(for: currentUserId)
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.sourceRecipeId, sourceRecipeId)
    }

    func testDeleteRecipeReferenceRemovesSavedReferenceWithoutDeletingSource() async throws {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Salad",
            ownerId: sourceOwnerId
        )

        _ = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        let deleted = try await dependencies.savedReferenceRepository.deleteRecipeReference(
            userId: currentUserId,
            sourceRecipeId: sourceRecipeId
        )

        XCTAssertTrue(deleted)
        let references = try await dependencies.savedReferenceRepository.recipeReferences(for: currentUserId)
        XCTAssertTrue(references.isEmpty)
    }

    func testSaveRecipeToLibraryReusesLegacyOwnedCopyAndLinksSavedReference() async throws {
        let sourceRecipeId = UUID()
        let legacyCopy = Recipe(
            title: "My Pasta",
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: .privateRecipe,
            ownerId: currentUserId,
            originalRecipeId: sourceRecipeId,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef",
            savedAt: Date(),
            sourceRecipeUpdatedAt: Date(),
            followsSourceUpdates: true
        )
        try await dependencies.recipeRepository.create(legacyCopy, skipCloudSync: true)

        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Pasta",
            ownerId: sourceOwnerId
        )

        let result = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertTrue(result.reusedExistingCopy)
        XCTAssertEqual(result.recipe.id, legacyCopy.id)
        XCTAssertEqual(result.savedReference?.sourceRecipeId, sourceRecipeId)
        XCTAssertEqual(result.savedReference?.materializedRecipeId, legacyCopy.id)

        let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId]
        )
        XCTAssertEqual(ownedCopies.count, 1)
    }

    func testMaterializeSavedRecipeForEditingCreatesOneOwnedCopyAndReusesIt() async throws {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Curry",
            ownerId: sourceOwnerId
        )

        _ = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        let firstEditable = try await dependencies.recipeSaveService.materializeSavedRecipeForEditing(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertNotEqual(firstEditable.id, sourceRecipeId)
        XCTAssertEqual(firstEditable.ownerId, currentUserId)
        XCTAssertEqual(firstEditable.originalRecipeId, sourceRecipeId)
        XCTAssertEqual(firstEditable.originalCreatorId, sourceOwnerId)
        XCTAssertEqual(firstEditable.originalCreatorName, "Source Chef")
        XCTAssertTrue(firstEditable.followsSourceUpdates)

        let secondEditable = try await dependencies.recipeSaveService.materializeSavedRecipeForEditing(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )
        XCTAssertEqual(secondEditable.id, firstEditable.id)

        let ownedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId]
        )
        XCTAssertEqual(ownedCopies.count, 1)

        let fetchedReference = try await dependencies.savedReferenceRepository.recipeReference(
            userId: currentUserId,
            sourceRecipeId: sourceRecipeId
        )
        let reference = try XCTUnwrap(fetchedReference)
        XCTAssertEqual(reference.materializedRecipeId, firstEditable.id)
    }

    func testMaterializeRecipeForOwnedCollectionMembershipLinksReferenceAndReturnsOwnedRecipe() async throws {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(
            id: sourceRecipeId,
            title: "Shared Soup",
            ownerId: sourceOwnerId
        )

        _ = try await dependencies.recipeSaveService.saveRecipeToLibrary(
            sourceRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        let materializedRecipe = try await dependencies.recipeSaveService.materializeRecipeForOwnedCollectionMembership(
            sourceRecipe,
            minimumVisibility: .publicRecipe,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef"
        )

        XCTAssertNotEqual(materializedRecipe.id, sourceRecipeId)
        XCTAssertEqual(materializedRecipe.ownerId, currentUserId)
        XCTAssertEqual(materializedRecipe.originalRecipeId, sourceRecipeId)
        XCTAssertEqual(materializedRecipe.visibility, .publicRecipe)

        let fetchedReference = try await dependencies.savedReferenceRepository.recipeReference(
            userId: currentUserId,
            sourceRecipeId: sourceRecipeId
        )
        let reference = try XCTUnwrap(fetchedReference)
        XCTAssertEqual(reference.materializedRecipeId, materializedRecipe.id)
    }

    func testSaveRecipeToLibraryCreatesReferencesForRequestedRelatedRecipesWithoutCopyingThem() async throws {
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

        let references = try await dependencies.savedReferenceRepository.recipeReferences(for: currentUserId)
        XCTAssertEqual(Set(references.map(\.sourceRecipeId)), Set([sourceRecipe.id, relatedSourceId]))

        let relatedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [relatedSourceId]
        )
        XCTAssertEqual(relatedCopies.count, 0)
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
