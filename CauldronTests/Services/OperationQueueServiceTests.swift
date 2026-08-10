//
//  OperationQueueServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

private actor AsyncFlag {
    private var isSet = false

    func set() { isSet = true }
    func value() -> Bool { isSet }
}

final class OperationQueueServiceTests: XCTestCase {
    func testUnknownOperationIDCannotMutateQueuedRecipe() async throws {
        let queueService = OperationQueueService()
        let recipeId = UUID()

        await queueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipeId
        )

        await queueService.markInProgress(operationId: recipeId)
        await queueService.markFailed(operationId: recipeId, error: "CloudKit unavailable")

        let queued = await queueService.getOperation(for: recipeId, entityType: .recipe)
        XCTAssertNotNil(queued)
        XCTAssertEqual(queued?.status, .pending)
        XCTAssertEqual(queued?.attempts, 0)
        XCTAssertNil(queued?.errorMessage)
    }

    func testMarkCompletedByRecipeEntityIdRemovesOperation() async throws {
        let queueService = OperationQueueService()
        let recipeId = UUID()

        await queueService.addOperation(
            type: .delete,
            entityType: .recipe,
            entityId: recipeId
        )

        await queueService.markCompleted(entityId: recipeId, entityType: .recipe)

        let queued = await queueService.getOperation(for: recipeId, entityType: .recipe)
        XCTAssertNil(queued)
    }

    func testStaleOperationCompletionCannotRemoveReplacement() async throws {
        let queueService = OperationQueueService()
        let recipeId = UUID()
        let staleOperationID = await queueService.addOperation(
            type: .create,
            entityType: .recipe,
            entityId: recipeId
        )
        let replacementID = await queueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipeId
        )

        await queueService.markCompleted(operationId: staleOperationID)

        let queued = await queueService.getOperation(for: recipeId, entityType: .recipe)
        XCTAssertEqual(queued?.id, replacementID)
        XCTAssertEqual(queued?.type, .update)
    }

    func testAccountDeletionGateRejectsOnlyDeletingOwner() async {
        let deletingOwner = UUID()
        let otherOwner = UUID()

        let deletionLease = await AccountDeletionGate.shared.begin(ownerID: deletingOwner)
        let permitsDeletingOwner = await AccountDeletionGate.shared.permitsWrite(ownerID: deletingOwner)
        let permitsOtherOwner = await AccountDeletionGate.shared.permitsWrite(ownerID: otherOwner)
        XCTAssertFalse(permitsDeletingOwner)
        XCTAssertTrue(permitsOtherOwner)
        await AccountDeletionGate.shared.end(deletionLease)
        let permitsAfterDeletion = await AccountDeletionGate.shared.permitsWrite(ownerID: deletingOwner)
        XCTAssertTrue(permitsAfterDeletion)
    }

    func testAccountDeletionGateClosesAdmissionAndDrainsPublicationLeases() async throws {
        let owner = UUID()
        let gate = AccountDeletionGate.shared
        let acquiredLease = await gate.acquirePublicationLease(ownerID: owner)
        let lease = try XCTUnwrap(acquiredLease)
        let deletionFinished = AsyncFlag()

        let deletion = Task {
            let deletionLease = await gate.begin(ownerID: owner)
            await deletionFinished.set()
            return deletionLease
        }

        for _ in 0..<20 {
            if !(await gate.permitsWrite(ownerID: owner)) { break }
            await Task.yield()
        }

        let permitsWhileDraining = await gate.permitsWrite(ownerID: owner)
        let finishedBeforeRelease = await deletionFinished.value()
        let rejectedLease = await gate.acquirePublicationLease(ownerID: owner)
        XCTAssertFalse(permitsWhileDraining)
        XCTAssertFalse(finishedBeforeRelease)
        XCTAssertNil(rejectedLease)

        await gate.releasePublicationLease(lease)
        let deletionLease = await deletion.value
        let finishedAfterRelease = await deletionFinished.value()
        XCTAssertTrue(finishedAfterRelease)

        await gate.end(deletionLease)
        let permitsAfterDeletion = await gate.permitsWrite(ownerID: owner)
        XCTAssertTrue(permitsAfterDeletion)
    }

    @MainActor
    func testDecodePersistedOperationsRecoversValidOperationsWhenOneEntryIsCorrupt() throws {
        let validOperation = SyncOperation(
            type: .delete,
            entityType: .recipe,
            entityId: UUID()
        )
        let invalidOperation = SyncOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID()
        )

        let validObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(validOperation))
        var invalidObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(invalidOperation)) as? [String: Any]
        )
        invalidObject["type"] = "futureUnsupportedOperation"

        let queueObject: [String: Any] = [
            validOperation.id.uuidString: validObject,
            invalidOperation.id.uuidString: invalidObject
        ]
        let queueData = try JSONSerialization.data(withJSONObject: queueObject)
        let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let decoded = OperationQueueService.decodePersistedOperations(queueData, capturedAt: capturedAt)

        XCTAssertEqual(decoded.operations.count, 1)
        XCTAssertEqual(decoded.operations[validOperation.id], validOperation)
        XCTAssertEqual(decoded.deadLetters.count, 1)
        XCTAssertEqual(decoded.deadLetters.first?.operationId, invalidOperation.id.uuidString)
        XCTAssertEqual(decoded.deadLetters.first?.capturedAt, capturedAt)
        XCTAssertNotNil(decoded.deadLetters.first?.rawJSON)
    }

    func testInProgressOperationKeepsDistinctPendingSuccessor() async {
        let queueService = OperationQueueService()
        let entityId = UUID()
        let firstId = await queueService.addOperation(
            type: .acceptConnection,
            entityType: .connection,
            entityId: entityId,
            payload: Data("accept".utf8)
        )
        await queueService.markInProgress(operationId: firstId)

        let successorId = await queueService.addOperation(
            type: .delete,
            entityType: .connection,
            entityId: entityId,
            payload: Data("delete".utf8)
        )

        let operations = await queueService.getOperations(for: entityId)
        XCTAssertNotEqual(firstId, successorId)
        XCTAssertEqual(operations.count, 2)
        XCTAssertEqual(operations.first(where: { $0.id == firstId })?.status, .inProgress)
        XCTAssertEqual(operations.first(where: { $0.id == successorId })?.status, .pending)

        await queueService.markCompleted(operationId: firstId)
        let remaining = await queueService.getOperations(for: entityId)
        XCTAssertEqual(remaining.map(\.id), [successorId])
    }

    func testDestructiveCleanupRemovesInProgressOperationAndSuccessor() async {
        let queueService = OperationQueueService()
        let entityId = UUID()
        let firstId = await queueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: entityId
        )
        await queueService.markInProgress(operationId: firstId)
        _ = await queueService.addOperation(
            type: .delete,
            entityType: .recipe,
            entityId: entityId
        )

        let queuedBeforeCleanup = await queueService.getOperations(for: entityId)
        XCTAssertEqual(queuedBeforeCleanup.count, 2)
        await queueService.removeAllOperations(entityId: entityId, entityType: .recipe)
        let queuedAfterCleanup = await queueService.getOperations(for: entityId)
        XCTAssertTrue(queuedAfterCleanup.isEmpty)
    }
}
