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

    func testSaveCollectionToLibraryCreatesReferenceWithoutCopyingCollectionOrRecipes() async throws {
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
        XCTAssertEqual(result.savedRecipeCount, 0)
        XCTAssertEqual(result.collection.id, sourceCollection.id)
        XCTAssertEqual(result.collection.userId, sourceOwnerId)
        XCTAssertEqual(result.collection.recipeIds, sourceCollection.recipeIds)
        XCTAssertEqual(result.savedReference?.sourceCollectionId, sourceCollection.id)
        XCTAssertEqual(result.savedReference?.sourceOwnerId, sourceOwnerId)
        XCTAssertEqual(result.savedReference?.sourceCollectionUpdatedAt, sourceUpdatedAt)

        let allCollections = try await dependencies.collectionRepository.fetchAll()
        XCTAssertFalse(allCollections.contains { collection in
            collection.userId == currentUserId &&
            collection.originalCollectionId == sourceCollection.id
        })

        let firstCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [firstSourceRecipe.id]
        )
        let secondCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [secondSourceRecipe.id]
        )
        XCTAssertEqual(firstCopies.count, 0)
        XCTAssertEqual(secondCopies.count, 0)
    }

    func testSaveCollectionToLibraryReusesExistingReferenceOnRepeatSave() async throws {
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
        XCTAssertEqual(secondSave.collection.id, sourceCollection.id)
        XCTAssertEqual(secondSave.savedReference?.id, firstSave.savedReference?.id)

        let references = try await dependencies.savedReferenceRepository.collectionReferences(for: currentUserId)
        XCTAssertEqual(references.count, 1)
        XCTAssertEqual(references.first?.sourceCollectionId, sourceCollection.id)

        let ownedRecipeCopies = try await dependencies.recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipe.id]
        )
        XCTAssertEqual(ownedRecipeCopies.count, 0)
    }

    func testDeleteCollectionReferenceRemovesSavedReferenceWithoutDeletingSource() async throws {
        let recipeId = UUID()
        let sourceCollection = Collection(
            id: UUID(),
            name: "Shared Dinner",
            userId: sourceOwnerId,
            recipeIds: [recipeId],
            visibility: .publicRecipe
        )

        _ = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: []
        )

        let deleted = try await dependencies.savedReferenceRepository.deleteCollectionReference(
            userId: currentUserId,
            sourceCollectionId: sourceCollection.id
        )

        XCTAssertTrue(deleted)
        let references = try await dependencies.savedReferenceRepository.collectionReferences(for: currentUserId)
        XCTAssertTrue(references.isEmpty)
    }

    func testLegacyOwnedCollectionCopyMarksSourceAsSavedAndBridgesReference() async throws {
        let sourceCollection = Collection(
            id: UUID(),
            name: "Shared Brunch",
            userId: sourceOwnerId,
            recipeIds: [],
            visibility: .publicRecipe
        )
        let legacyCopy = Collection(
            name: sourceCollection.name,
            userId: currentUserId,
            recipeIds: [],
            visibility: .publicRecipe,
            originalCollectionId: sourceCollection.id,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: sourceCollection.name,
            savedAt: Date(),
            sourceCollectionUpdatedAt: sourceCollection.updatedAt,
            followsSourceUpdates: true
        )
        try await dependencies.collectionRepository.create(legacyCopy)

        let existing = try await dependencies.collectionSaveService.existingSavedCollection(for: sourceCollection)
        XCTAssertEqual(existing?.id, legacyCopy.id)

        let result = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertTrue(result.reusedExistingCopy)
        XCTAssertEqual(result.collection.id, legacyCopy.id)
        XCTAssertEqual(result.savedReference?.sourceCollectionId, sourceCollection.id)

        let references = try await dependencies.savedReferenceRepository.collectionReferences(for: currentUserId)
        XCTAssertEqual(references.count, 1)
    }

    func testSaveCollectionToLibraryCreatesReferenceForEmptyCollection() async throws {
        let sourceCollection = Collection(
            id: UUID(),
            name: "Empty Ideas",
            description: "A collection before recipes are added",
            userId: sourceOwnerId,
            recipeIds: [],
            visibility: .publicRecipe,
            emoji: "*",
            color: "#6C5CE7"
        )

        let result = try await dependencies.collectionSaveService.saveCollectionToLibrary(
            sourceCollection,
            visibleRecipes: [],
            sourceOwnerName: "Source Chef"
        )

        XCTAssertFalse(result.reusedExistingCopy)
        XCTAssertEqual(result.savedRecipeCount, 0)
        XCTAssertEqual(result.collection.id, sourceCollection.id)
        XCTAssertEqual(result.collection.recipeIds, [])
        XCTAssertEqual(result.savedReference?.sourceCollectionId, sourceCollection.id)
        XCTAssertEqual(result.savedReference?.sourceOwnerId, sourceOwnerId)

        let allCollections = try await dependencies.collectionRepository.fetchAll()
        XCTAssertFalse(allCollections.contains { $0.originalCollectionId == sourceCollection.id })
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
