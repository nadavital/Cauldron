//
//  OperationQueueServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class OperationQueueServiceTests: XCTestCase {
    func testMarkFailedByRecipeEntityIdKeepsRetryableOperation() async throws {
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
        XCTAssertEqual(queued?.status, .failed)
        XCTAssertEqual(queued?.attempts, 1)
        XCTAssertEqual(queued?.errorMessage, "CloudKit unavailable")
        XCTAssertNotNil(queued?.nextRetryDate)
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
}
