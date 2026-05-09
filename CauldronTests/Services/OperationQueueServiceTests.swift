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
}
