//
//  RecipeRepositoryVisibilityTests.swift
//  CauldronTests
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class RecipeRepositoryVisibilityTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var recipeRepository: RecipeRepository!
    private var collectionRepository: CollectionRepository!
    private var userId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        CurrentUserSession.shared.signOut()
        userId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: userId,
                username: "owner",
                displayName: "Owner",
                createdAt: Date()
            )
        )
        modelContainer = try TestModelContainer.create(with: [
            RecipeModel.self,
            DeletedRecipeModel.self,
            CollectionModel.self,
            CollectionMembershipModel.self
        ])

        let cloudKitCore = CloudKitCore()
        let recipeCloudService = RecipeCloudService(core: cloudKitCore)
        let collectionCloudService = CollectionCloudService(core: cloudKitCore)
        let imageManager = RecipeImageManager(
            directoryName: "RecipeRepositoryVisibilityTests-\(UUID().uuidString)",
            uploadToCloudWithDatabase: nil,
            downloadFromCloudWithDatabase: nil
        )
        let operationQueueService = OperationQueueService()
        collectionRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: operationQueueService
        )
        recipeRepository = RecipeRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            deletedRecipeRepository: DeletedRecipeRepository(modelContainer: modelContainer),
            collectionRepository: collectionRepository,
            imageManager: imageManager,
            imageSyncManager: ImageSyncManager(),
            operationQueueService: operationQueueService,
            externalShareService: ExternalShareService(imageManager: imageManager)
        )
    }

    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        recipeRepository = nil
        collectionRepository = nil
        modelContainer = nil
        userId = nil
        try await super.tearDown()
    }

    func testVisibilityImpactReportsOwnedPublicCollectionsOnly() async throws {
        let recipe = makeRecipe(visibility: .publicRecipe)
        try await recipeRepository.create(recipe)
        let publicCollection = Collection(
            name: "Public",
            userId: userId,
            recipeIds: [recipe.id],
            visibility: .publicRecipe
        )
        let privateCollection = Collection(
            name: "Private",
            userId: userId,
            recipeIds: [recipe.id],
            visibility: .privateRecipe
        )
        let otherUsersCollection = Collection(
            name: "Other",
            userId: UUID(),
            recipeIds: [recipe.id],
            visibility: .publicRecipe
        )
        try await collectionRepository.create(publicCollection)
        try await collectionRepository.create(privateCollection)
        try insertCollectionFixture(otherUsersCollection)

        let impact = try await recipeRepository.visibilityImpactForChangingRecipe(
            id: recipe.id,
            to: .privateRecipe
        )

        XCTAssertTrue(impact.requiresConfirmation)
        XCTAssertEqual(impact.publicCollectionCount, 1)
        XCTAssertEqual(impact.publicCollectionsAffected.first?.id, publicCollection.id)
    }

    func testMakingRecipePrivateRemovesItFromOwnedPublicCollections() async throws {
        let recipe = makeRecipe(visibility: .publicRecipe)
        try await recipeRepository.create(recipe)
        let publicCollection = Collection(
            name: "Public",
            userId: userId,
            recipeIds: [recipe.id],
            visibility: .publicRecipe
        )
        let privateCollection = Collection(
            name: "Private",
            userId: userId,
            recipeIds: [recipe.id],
            visibility: .privateRecipe
        )
        try await collectionRepository.create(publicCollection)
        try await collectionRepository.create(privateCollection)

        try await recipeRepository.updateVisibility(id: recipe.id, visibility: .privateRecipe)

        let fetchedRecipe = try await recipeRepository.fetch(id: recipe.id)
        let fetchedPublicCollection = try await collectionRepository.fetch(id: publicCollection.id)
        let fetchedPrivateCollection = try await collectionRepository.fetch(id: privateCollection.id)
        let updatedRecipe = try XCTUnwrap(fetchedRecipe)
        let updatedPublicCollection = try XCTUnwrap(fetchedPublicCollection)
        let updatedPrivateCollection = try XCTUnwrap(fetchedPrivateCollection)
        XCTAssertEqual(updatedRecipe.visibility, .privateRecipe)
        XCTAssertFalse(updatedPublicCollection.recipeIds.contains(recipe.id))
        XCTAssertTrue(updatedPrivateCollection.recipeIds.contains(recipe.id))
    }

    func testRepairInvalidPublicCollectionMembershipsRemovesPrivateRecipes() async throws {
        let publicRecipe = makeRecipe(visibility: .publicRecipe)
        let privateRecipe = makeRecipe(visibility: .privateRecipe)
        try await recipeRepository.create(publicRecipe)
        try await recipeRepository.create(privateRecipe)
        let collection = Collection(
            name: "Public",
            userId: userId,
            recipeIds: [publicRecipe.id, privateRecipe.id],
            visibility: .publicRecipe
        )
        try await collectionRepository.create(collection)

        let repairedCount = try await collectionRepository.repairInvalidPublicCollectionMemberships(
            recipeRepository: recipeRepository,
            ownerId: userId
        )

        let fetchedCollection = try await collectionRepository.fetch(id: collection.id)
        let updatedCollection = try XCTUnwrap(fetchedCollection)
        XCTAssertEqual(repairedCount, 1)
        XCTAssertEqual(updatedCollection.recipeIds, [publicRecipe.id])
    }

    func testDeleteRejectsNonOwnedNonPreviewRecipe() async throws {
        let externalRecipe = Recipe(
            id: UUID(),
            title: "External Recipe",
            ingredients: [],
            steps: [],
            yields: "1 serving",
            tags: [],
            visibility: .publicRecipe,
            ownerId: UUID(),
            createdAt: Date(),
            updatedAt: Date()
        )
        try await recipeRepository.create(externalRecipe, skipCloudSync: true)

        do {
            try await recipeRepository.delete(id: externalRecipe.id)
            XCTFail("Expected non-owned recipe deletion to be rejected")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .notAuthorized)
        }

        let fetchedRecipe = try await recipeRepository.fetch(id: externalRecipe.id)
        XCTAssertNotNil(fetchedRecipe)
    }

    private func makeRecipe(visibility: RecipeVisibility) -> Recipe {
        Recipe(
            id: UUID(),
            title: "Test Recipe",
            ingredients: [Ingredient(name: "Salt", quantity: Quantity(value: 1, unit: .teaspoon))],
            steps: [CookStep(index: 0, text: "Mix.")],
            yields: "2 servings",
            tags: [],
            isFavorite: false,
            visibility: visibility,
            ownerId: userId,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func insertCollectionFixture(_ collection: Collection) throws {
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(collection))
        try context.save()
    }
}
