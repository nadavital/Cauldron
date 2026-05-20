//
//  CollectionSaveServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class CollectionSaveServiceTests: XCTestCase {
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

    func testSaveCollectionToLibraryCreatesOwnedCopyWithSavedRecipeMembership() async throws {
        let firstSourceRecipe = makeRecipe(title: "Pancakes")
        let secondSourceRecipe = makeRecipe(title: "Coffee Cake")
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let sourceCollection = Collection(
            id: UUID(),
            name: "Shared Brunch",
            description: "For weekends",
            userId: sourceOwnerId,
            recipeIds: [secondSourceRecipe.id, firstSourceRecipe.id],
            visibility: .publicRecipe,
            symbolName: "sun.max.fill",
            color: "#F7B731",
            updatedAt: sourceUpdatedAt
        )

        let result = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [firstSourceRecipe, secondSourceRecipe],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertFalse(result.reusedExistingCopy)
        XCTAssertEqual(result.savedRecipeCount, 2)
        XCTAssertNotEqual(result.collection.id, sourceCollection.id)
        XCTAssertEqual(result.collection.userId, currentUserId)
        XCTAssertEqual(result.collection.name, sourceCollection.name)
        XCTAssertEqual(result.collection.description, sourceCollection.description)
        XCTAssertEqual(result.collection.originalCollectionId, sourceCollection.id)
        XCTAssertEqual(result.collection.originalCollectionOwnerId, sourceOwnerId)
        XCTAssertEqual(result.collection.originalCollectionName, sourceCollection.name)
        XCTAssertEqual(result.collection.sourceCollectionUpdatedAt, sourceUpdatedAt)
        XCTAssertTrue(result.collection.followsSourceUpdates)
        XCTAssertNotNil(result.collection.savedAt)

        let fetchedCollection = try await dependencies.collectionRepository.fetch(id: result.collection.id)
        let savedCollection = try XCTUnwrap(fetchedCollection)
        XCTAssertEqual(savedCollection.recipeIds.count, 2)
        XCTAssertNotEqual(savedCollection.recipeIds, sourceCollection.recipeIds)

        let firstCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [firstSourceRecipe.id]
        )
        let secondCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [secondSourceRecipe.id]
        )
        XCTAssertEqual(firstCopies.count, 1)
        XCTAssertEqual(secondCopies.count, 1)
        XCTAssertEqual(savedCollection.recipeIds, [secondCopies[0].id, firstCopies[0].id])
    }

    func testSaveCollectionToLibraryReusesExistingCopyOnRepeatSave() async throws {
        let sourceRecipe = makeRecipe(title: "Soup")
        let sourceCollection = Collection(
            id: UUID(),
            name: "Shared Soup",
            userId: sourceOwnerId,
            recipeIds: [sourceRecipe.id],
            visibility: .publicRecipe
        )

        let firstSave = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [sourceRecipe],
            sourceOwnerName: "Source Chef"
        )
        let secondSave = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [sourceRecipe],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertFalse(firstSave.reusedExistingCopy)
        XCTAssertTrue(secondSave.reusedExistingCopy)
        XCTAssertEqual(secondSave.collection.id, firstSave.collection.id)
        XCTAssertEqual(secondSave.savedRecipeCount, 0)

        let allCollections = try await dependencies.collectionRepository.fetchAll()
        let savedCollections = allCollections.filter {
            $0.userId == currentUserId &&
            $0.originalCollectionId == sourceCollection.id
        }
        XCTAssertEqual(savedCollections.count, 1)

        let ownedRecipeCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipe.id]
        )
        XCTAssertEqual(ownedRecipeCopies.count, 1)
    }

    func testSaveCollectionToLibraryReconcilesExistingFollowingCopyWhenSourceChanges() async throws {
        let originalRecipe = makeRecipe(title: "Soup")
        let addedRecipe = makeRecipe(title: "Salad")
        let sourceCollectionId = UUID()
        let firstSourceCollection = Collection(
            id: sourceCollectionId,
            name: "Shared Dinner",
            userId: sourceOwnerId,
            recipeIds: [originalRecipe.id],
            visibility: .publicRecipe,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let firstSave = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            firstSourceCollection,
            visibleRecipes: [originalRecipe],
            sourceOwnerName: "Source Chef"
        )

        let updatedSourceCollection = Collection(
            id: sourceCollectionId,
            name: "Shared Dinner Updated",
            userId: sourceOwnerId,
            recipeIds: [addedRecipe.id, originalRecipe.id],
            visibility: .publicRecipe,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let secondSave = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            updatedSourceCollection,
            visibleRecipes: [originalRecipe, addedRecipe],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertTrue(secondSave.reusedExistingCopy)
        XCTAssertEqual(secondSave.collection.id, firstSave.collection.id)
        XCTAssertEqual(secondSave.collection.name, updatedSourceCollection.name)
        XCTAssertEqual(secondSave.collection.sourceCollectionUpdatedAt, updatedSourceCollection.updatedAt)
        XCTAssertEqual(secondSave.savedRecipeCount, 1)

        let persistedCollection = try await dependencies.collectionRepository.fetch(id: firstSave.collection.id)
        let fetchedCollection = try XCTUnwrap(persistedCollection)
        XCTAssertEqual(fetchedCollection.recipeIds, secondSave.collection.recipeIds)
        XCTAssertEqual(fetchedCollection.recipeIds.count, 2)

        let originalCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [originalRecipe.id],
            ownerId: currentUserId
        )
        let addedCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [addedRecipe.id],
            ownerId: currentUserId
        )
        XCTAssertEqual(originalCopies.count, 1)
        XCTAssertEqual(addedCopies.count, 1)
        XCTAssertEqual(fetchedCollection.recipeIds, [addedCopies[0].id, originalCopies[0].id])
    }

    func testSaveCollectionToLibraryThrowsWhenUpdatingExistingCopyFromPartialVisibleRecipes() async throws {
        let visibleRecipe = makeRecipe(title: "Visible Soup")
        let unrelatedExtraRecipe = makeRecipe(title: "Unrelated Cake")
        let missingRecipeId = UUID()
        let sourceCollectionId = UUID()
        let originalSourceCollection = Collection(
            id: sourceCollectionId,
            name: "Shared Dinner",
            userId: sourceOwnerId,
            recipeIds: [visibleRecipe.id],
            visibility: .publicRecipe,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let firstSave = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            originalSourceCollection,
            visibleRecipes: [visibleRecipe],
            sourceOwnerName: "Source Chef"
        )

        let partiallyLoadedUpdatedSource = Collection(
            id: sourceCollectionId,
            name: "Shared Dinner Updated",
            userId: sourceOwnerId,
            recipeIds: [missingRecipeId, visibleRecipe.id],
            visibility: .publicRecipe,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        do {
            _ = try await dependencies.collectionSaveService.saveCollectionToLibrary(
                partiallyLoadedUpdatedSource,
                visibleRecipes: [visibleRecipe, unrelatedExtraRecipe],
                sourceOwnerName: "Source Chef"
            )
            XCTFail("Expected partial source recipes to throw instead of silently no-oping")
        } catch CollectionSaveServiceError.sourceRecipesUnavailable(let visibleCount, let totalCount) {
            XCTAssertEqual(visibleCount, 1)
            XCTAssertEqual(totalCount, 2)
        }

        let persistedCollection = try await dependencies.collectionRepository.fetch(id: firstSave.collection.id)
        let savedCollection = try XCTUnwrap(persistedCollection)
        XCTAssertEqual(savedCollection.name, firstSave.collection.name)
        XCTAssertEqual(savedCollection.recipeIds, firstSave.collection.recipeIds)
        XCTAssertEqual(savedCollection.sourceCollectionUpdatedAt, firstSave.collection.sourceCollectionUpdatedAt)
    }

    func testSaveCollectionToLibraryCreatesOwnedCopyForEmptyCollection() async throws {
        let sourceCollection = Collection(
            id: UUID(),
            name: "Empty Ideas",
            description: "A collection before recipes are added",
            userId: sourceOwnerId,
            recipeIds: [],
            visibility: .publicRecipe,
            emoji: "✨",
            color: "#6C5CE7"
        )

        let result = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertFalse(result.reusedExistingCopy)
        XCTAssertEqual(result.savedRecipeCount, 0)
        XCTAssertNotEqual(result.collection.id, sourceCollection.id)
        XCTAssertEqual(result.collection.userId, currentUserId)
        XCTAssertEqual(result.collection.recipeIds, [])
        XCTAssertEqual(result.collection.originalCollectionId, sourceCollection.id)
        XCTAssertEqual(result.collection.originalCollectionOwnerId, sourceOwnerId)
        XCTAssertEqual(result.collection.originalCollectionName, sourceCollection.name)
        XCTAssertTrue(result.collection.followsSourceUpdates)
        XCTAssertNotNil(result.collection.savedAt)

        let fetchedCollection = try await dependencies.collectionRepository.fetch(id: result.collection.id)
        let savedCollection = try XCTUnwrap(fetchedCollection)
        XCTAssertEqual(savedCollection.recipeIds, [])
        XCTAssertEqual(savedCollection.originalCollectionId, sourceCollection.id)
    }

    private func makeRecipe(title: String) -> Recipe {
        Recipe(
            title: title,
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: .publicRecipe,
            ownerId: sourceOwnerId
        )
    }
}
