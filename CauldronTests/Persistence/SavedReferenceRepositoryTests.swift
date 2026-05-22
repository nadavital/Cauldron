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

    func testReconcileLocalReferencesPostsRemovedReferenceNotifications() async throws {
        let removedRecipe = try await repository.saveRecipeReference(
            sourceRecipe: makeRecipe(id: UUID()),
            userId: userId,
            originalCreatorName: "Source Chef"
        ).reference
        let removedCollection = try await repository.saveCollectionReference(
            sourceCollection: makeCollection(id: UUID()),
            userId: userId
        ).reference

        let recipeExpectation = expectation(description: "removed recipe reference notification")
        let collectionExpectation = expectation(description: "removed collection reference notification")
        let recipeObserver = NotificationCenter.default.addObserver(
            forName: .savedRecipeReferencesChanged,
            object: nil,
            queue: .main
        ) { notification in
            guard notification.userInfo?["changeType"] as? String == "removed",
                  notification.userInfo?["sourceRecipeId"] as? UUID == removedRecipe.sourceRecipeId else {
                return
            }
            recipeExpectation.fulfill()
        }
        let collectionObserver = NotificationCenter.default.addObserver(
            forName: .savedCollectionReferencesChanged,
            object: nil,
            queue: .main
        ) { notification in
            guard notification.userInfo?["changeType"] as? String == "removed",
                  notification.userInfo?["sourceCollectionId"] as? UUID == removedCollection.sourceCollectionId else {
                return
            }
            collectionExpectation.fulfill()
        }
        defer {
            NotificationCenter.default.removeObserver(recipeObserver)
            NotificationCenter.default.removeObserver(collectionObserver)
        }

        try await repository.reconcileLocalReferences(
            userId: userId,
            remoteRecipeReferences: [],
            remoteCollectionReferences: []
        )

        await fulfillment(of: [recipeExpectation, collectionExpectation], timeout: 1)
    }

    func testNewestRecipeReferencesBySourceIdHandlesDuplicateRows() {
        let sourceRecipeId = UUID()
        let older = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            materializedRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let newerCopyId = UUID()
        let newer = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            materializedRecipeId: newerCopyId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let referencesBySourceId = SavedReferenceRepository.newestRecipeReferencesBySourceId([older, newer])

        XCTAssertEqual(referencesBySourceId[sourceRecipeId]?.id, newer.id)
        XCTAssertEqual(referencesBySourceId[sourceRecipeId]?.materializedRecipeId, newerCopyId)
    }

    func testAppliedRemoteRecipeReferenceChangesIgnoresStaleRemoteRows() {
        let sourceRecipeId = UUID()
        let localCopyId = UUID()
        let local = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            materializedRecipeId: localCopyId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let staleRemote = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            materializedRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let changes = SavedReferenceRepository.appliedRemoteRecipeReferenceChanges(
            [staleRemote],
            localBySourceId: [sourceRecipeId: local]
        )

        XCTAssertTrue(changes.isEmpty)
    }

    func testPendingRecipeReferenceDeleteSuppressesStaleRemoteReference() throws {
        let sourceRecipeId = UUID()
        let reference = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let operation = SyncOperation(
            type: .delete,
            entityType: .savedRecipeReference,
            entityId: reference.id,
            payload: try JSONEncoder().encode(reference)
        )

        let filtered = SavedReferenceRepository.remoteRecipeReferences(
            [reference],
            excludingPendingDeletes: [operation],
            for: userId
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testPendingRecipeReferenceDeleteDoesNotSuppressOtherUsersRemoteReference() throws {
        let sourceRecipeId = UUID()
        let otherUserId = UUID()
        let deletedReference = SavedRecipeReference(
            userId: otherUserId,
            sourceRecipeId: sourceRecipeId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let currentUsersRemoteReference = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let operation = SyncOperation(
            type: .delete,
            entityType: .savedRecipeReference,
            entityId: deletedReference.id,
            payload: try JSONEncoder().encode(deletedReference)
        )

        let filtered = SavedReferenceRepository.remoteRecipeReferences(
            [currentUsersRemoteReference],
            excludingPendingDeletes: [operation],
            for: userId
        )

        XCTAssertEqual(filtered.map(\.id), [currentUsersRemoteReference.id])
    }

    func testPendingCollectionReferenceDeleteSuppressesStaleRemoteReference() throws {
        let sourceCollectionId = UUID()
        let reference = SavedCollectionReference(
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let operation = SyncOperation(
            type: .delete,
            entityType: .savedCollectionReference,
            entityId: reference.id,
            payload: try JSONEncoder().encode(reference)
        )

        let filtered = SavedReferenceRepository.remoteCollectionReferences(
            [reference],
            excludingPendingDeletes: [operation],
            for: userId
        )

        XCTAssertTrue(filtered.isEmpty)
    }

    func testPendingCollectionReferenceDeleteDoesNotSuppressOtherUsersRemoteReference() throws {
        let sourceCollectionId = UUID()
        let otherUserId = UUID()
        let deletedReference = SavedCollectionReference(
            userId: otherUserId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let currentUsersRemoteReference = SavedCollectionReference(
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let operation = SyncOperation(
            type: .delete,
            entityType: .savedCollectionReference,
            entityId: deletedReference.id,
            payload: try JSONEncoder().encode(deletedReference)
        )

        let filtered = SavedReferenceRepository.remoteCollectionReferences(
            [currentUsersRemoteReference],
            excludingPendingDeletes: [operation],
            for: userId
        )

        XCTAssertEqual(filtered.map(\.id), [currentUsersRemoteReference.id])
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
