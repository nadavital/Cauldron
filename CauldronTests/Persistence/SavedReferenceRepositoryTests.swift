//
//  SavedReferenceRepositoryTests.swift
//  CauldronTests
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class SavedReferenceRepositoryTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var operationQueueService: OperationQueueService!
    private var repository: SavedReferenceRepository!
    private var userId: UUID!
    private var sourceOwnerId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainer.create(with: [
            SavedRecipeReferenceModel.self,
            SavedCollectionReferenceModel.self
        ])
        operationQueueService = OperationQueueService()
        repository = SavedReferenceRepository(
            modelContainer: modelContainer,
            operationQueueService: operationQueueService
        )
        userId = UUID()
        sourceOwnerId = UUID()
    }

    override func tearDown() async throws {
        repository = nil
        operationQueueService = nil
        modelContainer = nil
        userId = nil
        sourceOwnerId = nil
        try await super.tearDown()
    }

    func testReconcileLocalReferencesRemovesLocalsAbsentFromRemoteSnapshot() async throws {
        let keptRecipe = try await repository.saveRecipeReference(
            sourceRecipe: makeRecipe(id: UUID()),
            userId: userId,
            originalCreatorName: "Source Chef"
        ).reference
        _ = try await repository.saveRecipeReference(
            sourceRecipe: makeRecipe(id: UUID()),
            userId: userId,
            originalCreatorName: "Source Chef"
        )

        let keptCollection = try await repository.saveCollectionReference(
            sourceCollection: makeCollection(id: UUID()),
            userId: userId
        ).reference
        _ = try await repository.saveCollectionReference(
            sourceCollection: makeCollection(id: UUID()),
            userId: userId
        )

        try await repository.reconcileLocalReferences(
            userId: userId,
            remoteRecipeReferences: [keptRecipe],
            remoteCollectionReferences: [keptCollection]
        )

        let recipeReferences = try await repository.recipeReferences(for: userId)
        XCTAssertEqual(recipeReferences.map(\.sourceRecipeId), [keptRecipe.sourceRecipeId])

        let collectionReferences = try await repository.collectionReferences(for: userId)
        XCTAssertEqual(collectionReferences.map(\.sourceCollectionId), [keptCollection.sourceCollectionId])
    }

    func testReconcileLocalReferencesKeepsLocalsWithPendingUploads() async throws {
        let pendingReference = try await repository.saveRecipeReference(
            sourceRecipe: makeRecipe(id: UUID()),
            userId: userId,
            originalCreatorName: "Source Chef"
        ).reference
        await operationQueueService.addOperation(
            type: .create,
            entityType: .savedRecipeReference,
            entityId: pendingReference.id
        )

        try await repository.reconcileLocalReferences(
            userId: userId,
            remoteRecipeReferences: [],
            remoteCollectionReferences: []
        )

        let recipeReferences = try await repository.recipeReferences(for: userId)
        XCTAssertEqual(recipeReferences.map(\.id), [pendingReference.id])
    }

    private func makeRecipe(id: UUID) -> Recipe {
        Recipe(
            id: id,
            title: "Shared Recipe",
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: .publicRecipe,
            ownerId: sourceOwnerId
        )
    }

    private func makeCollection(id: UUID) -> Collection {
        Collection(
            id: id,
            name: "Shared Collection",
            userId: sourceOwnerId,
            recipeIds: [],
            visibility: .publicRecipe
        )
    }
}
