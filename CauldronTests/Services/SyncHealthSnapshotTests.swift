import XCTest
@testable import Cauldron

final class SyncHealthSnapshotTests: XCTestCase {
    func testStatusMatrix() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(SyncHealthSnapshot.make(operations: [], now: now).status, .upToDate)
        XCTAssertEqual(snapshot(status: .pending, now: now).status, .waiting)
        XCTAssertEqual(snapshot(status: .inProgress, now: now).status, .syncing)
        XCTAssertEqual(snapshot(status: .failed, now: now).status, .waiting)
        XCTAssertEqual(
            SyncHealthSnapshot.make(operations: [], deadLetterCount: 1, now: now).status,
            .actionRequired
        )
    }

    func testFailedTakesPriorityAndOldestAgeIsReported() {
        let now = Date(timeIntervalSince1970: 100)
        let operations = [
            makeOperation(status: .inProgress, createdAt: Date(timeIntervalSince1970: 90)),
            makeOperation(status: .failed, createdAt: Date(timeIntervalSince1970: 70))
        ]
        let snapshot = SyncHealthSnapshot.make(operations: operations, now: now)
        XCTAssertEqual(snapshot.status, .syncing)
        XCTAssertEqual(snapshot.failedCount, 1)
        XCTAssertEqual(snapshot.oldestPendingAge, 30)
    }

    func testScheduledRetryIsWaitingRatherThanActionRequired() {
        let operation = SyncOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID(),
            status: .failed,
            attempts: 2,
            nextRetryDate: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(
            SyncHealthSnapshot.make(operations: [operation]).status,
            .waiting
        )
    }

    func testDeadLetterTakesPriorityOverActiveSync() {
        let operation = SyncOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID(),
            status: .inProgress
        )

        let snapshot = SyncHealthSnapshot.make(
            operations: [operation],
            deadLetterCount: 2
        )

        XCTAssertEqual(snapshot.status, .actionRequired)
        XCTAssertEqual(snapshot.deadLetterCount, 2)
        XCTAssertEqual(snapshot.pendingCount, 1)
    }

    private func snapshot(status: OperationStatus, now: Date) -> SyncHealthSnapshot {
        SyncHealthSnapshot.make(
            operations: [makeOperation(status: status, createdAt: now)],
            now: now
        )
    }

    private func makeOperation(status: OperationStatus, createdAt: Date) -> SyncOperation {
        SyncOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID(),
            status: status,
            createdAt: createdAt
        )
    }
}
