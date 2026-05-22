//
//  LibraryRelationResolverTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class LibraryRelationResolverTests: XCTestCase {
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

    func testRecipeRelationReturnsOwnedForCurrentUserRecipe() async throws {
        let recipe = makeRecipe(title: "Owned", ownerId: currentUserId)

        let relation = try await dependencies.libraryRelationResolver.recipeRelation(
            for: recipe,
            currentUserId: currentUserId
        )

        XCTAssertEqual(relation, .owned)
    }

    func testRecipeRelationReturnsSavedForSavedReference() async throws {
        let recipe = makeRecipe(title: "Shared", ownerId: sourceOwnerId)
        _ = try await dependencies.savedReferenceRepository.saveRecipeReference(
            sourceRecipe: recipe,
            userId: currentUserId,
            originalCreatorName: "Source Chef"
        )

        let relation = try await dependencies.libraryRelationResolver.recipeRelation(
            for: recipe,
            currentUserId: currentUserId
        )

        XCTAssertEqual(relation, .saved(materializedRecipeId: nil))
    }

    func testCollectionRelationReturnsSavedForSavedReference() async throws {
        let collection = Collection(
            id: UUID(),
            name: "Shared Dinner",
            userId: sourceOwnerId,
            recipeIds: [],
            visibility: .publicRecipe
        )
        _ = try await dependencies.savedReferenceRepository.saveCollectionReference(
            sourceCollection: collection,
            userId: currentUserId
        )

        let relation = try await dependencies.libraryRelationResolver.collectionRelation(
            for: collection,
            currentUserId: currentUserId
        )

        guard case .saved = relation else {
            return XCTFail("Expected saved collection relation, got \(relation)")
        }
        XCTAssertTrue(relation.isSavedOrOwned)
    }

    func testPresentationStoreAliasesRecipeRelationsWithoutSubstitutingSnapshots() {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(id: sourceRecipeId, title: "Original", ownerId: sourceOwnerId)
        let savedCopy = makeRecipe(
            title: "Saved Copy",
            ownerId: currentUserId,
            originalRecipeId: sourceRecipeId,
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedRecipe(
            sourceRecipe,
            relation: .saved(materializedRecipeId: savedCopy.id)
        )

        let snapshot = dependencies.libraryPresentationStore.recipeSnapshot(for: savedCopy)
        let relation = dependencies.libraryPresentationStore.recipeRelation(for: savedCopy)

        XCTAssertNil(snapshot)
        XCTAssertEqual(relation, .saved(materializedRecipeId: savedCopy.id))
    }

    func testPresentationStoreAliasesCollectionRelationsWithoutSubstitutingSnapshots() {
        let sourceCollectionId = UUID()
        let sourceCollection = Collection(
            id: sourceCollectionId,
            name: "Original",
            userId: sourceOwnerId
        )
        let legacyLocalCopy = Collection(
            id: UUID(),
            name: "Local Copy",
            userId: currentUserId,
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: "Original",
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedCollection(
            sourceCollection,
            relation: .saved(referenceId: nil),
            savedCollection: sourceCollection
        )

        let snapshot = dependencies.libraryPresentationStore.collectionSnapshot(for: legacyLocalCopy)
        let relation = dependencies.libraryPresentationStore.collectionRelation(for: legacyLocalCopy)

        XCTAssertNil(snapshot)
        XCTAssertEqual(relation, .saved(referenceId: nil))
    }

    func testPresentationStoreKeepsSourceAndSavedCopySnapshotsSeparate() {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(id: sourceRecipeId, title: "Original", ownerId: sourceOwnerId)
        let savedCopy = makeRecipe(
            title: "Edited Copy",
            ownerId: currentUserId,
            originalRecipeId: sourceRecipeId,
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedRecipe(
            savedCopy,
            relation: .saved(materializedRecipeId: savedCopy.id)
        )
        dependencies.libraryPresentationStore.seedRecipe(sourceRecipe, relation: .saved(materializedRecipeId: savedCopy.id))

        XCTAssertEqual(dependencies.libraryPresentationStore.recipeSnapshot(for: sourceRecipe)?.recipe.id, sourceRecipe.id)
        XCTAssertEqual(dependencies.libraryPresentationStore.recipeSnapshot(for: savedCopy)?.recipe.id, savedCopy.id)
    }

    func testPresentationStorePrefersExactRecipeRelationOverSourceAlias() {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(id: sourceRecipeId, title: "Original", ownerId: sourceOwnerId)
        let savedCopy = makeRecipe(
            title: "Edited Copy",
            ownerId: currentUserId,
            originalRecipeId: sourceRecipeId,
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedRecipe(
            sourceRecipe,
            relation: .saved(materializedRecipeId: savedCopy.id)
        )
        dependencies.libraryPresentationStore.seedRecipe(savedCopy, relation: .owned)

        XCTAssertEqual(dependencies.libraryPresentationStore.recipeRelation(for: savedCopy), .owned)
    }

    func testPresentationStoreDoesNotAliasSourceRecipeNotSavedStateToCopy() {
        let sourceRecipeId = UUID()
        let sourceRecipe = makeRecipe(id: sourceRecipeId, title: "Original", ownerId: sourceOwnerId)
        let savedCopy = makeRecipe(
            title: "Edited Copy",
            ownerId: currentUserId,
            originalRecipeId: sourceRecipeId,
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedRecipe(sourceRecipe, relation: .notSaved)

        XCTAssertNil(dependencies.libraryPresentationStore.recipeRelation(for: savedCopy))
    }

    func testPresentationStoreKeepsSourceAndLegacyCollectionSnapshotsSeparate() {
        let sourceCollectionId = UUID()
        let sourceCollection = Collection(id: sourceCollectionId, name: "Original", userId: sourceOwnerId)
        let legacyLocalCopy = Collection(
            id: UUID(),
            name: "Edited Local Copy",
            userId: currentUserId,
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: "Original",
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedCollection(
            sourceCollection,
            relation: .saved(referenceId: nil),
            savedCollection: sourceCollection
        )
        dependencies.libraryPresentationStore.seedCollection(legacyLocalCopy, relation: .owned)

        XCTAssertEqual(dependencies.libraryPresentationStore.collectionSnapshot(for: sourceCollection)?.collection.id, sourceCollection.id)
        XCTAssertEqual(dependencies.libraryPresentationStore.collectionSnapshot(for: legacyLocalCopy)?.collection.id, legacyLocalCopy.id)
        XCTAssertEqual(dependencies.libraryPresentationStore.collectionRelation(for: sourceCollection), .saved(referenceId: nil))
        XCTAssertEqual(dependencies.libraryPresentationStore.collectionRelation(for: legacyLocalCopy), .owned)
    }

    func testPresentationStorePrefersExactCollectionRelationOverSourceAlias() {
        let sourceCollectionId = UUID()
        let sourceCollection = Collection(id: sourceCollectionId, name: "Original", userId: sourceOwnerId)
        let legacyLocalCopy = Collection(
            id: UUID(),
            name: "Edited Local Copy",
            userId: currentUserId,
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: "Original",
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedCollection(sourceCollection, relation: .saved(referenceId: nil))
        dependencies.libraryPresentationStore.seedCollection(legacyLocalCopy, relation: .owned)

        XCTAssertEqual(dependencies.libraryPresentationStore.collectionRelation(for: legacyLocalCopy), .owned)
    }

    func testPresentationStoreDoesNotAliasSourceCollectionNotSavedStateToCopy() {
        let sourceCollectionId = UUID()
        let sourceCollection = Collection(id: sourceCollectionId, name: "Original", userId: sourceOwnerId)
        let legacyLocalCopy = Collection(
            id: UUID(),
            name: "Edited Local Copy",
            userId: currentUserId,
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: "Original",
            savedAt: Date(),
            followsSourceUpdates: true
        )

        dependencies.libraryPresentationStore.seedCollection(sourceCollection, relation: .notSaved)

        XCTAssertNil(dependencies.libraryPresentationStore.collectionRelation(for: legacyLocalCopy))
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        ownerId: UUID,
        originalRecipeId: UUID? = nil,
        savedAt: Date? = nil,
        followsSourceUpdates: Bool = false
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "4 servings",
            visibility: .publicRecipe,
            ownerId: ownerId,
            originalRecipeId: originalRecipeId,
            savedAt: savedAt,
            followsSourceUpdates: followsSourceUpdates
        )
    }
}
