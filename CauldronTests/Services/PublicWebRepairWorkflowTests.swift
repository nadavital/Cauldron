import XCTest
@testable import Cauldron

final class PublicWebRepairWorkflowTests: XCTestCase {
    actor Events {
        private(set) var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }
    }

    func testPublicationRunsOnlyAfterAuthoritativeSync() async throws {
        let events = Events()

        try await PublicWebRepairWorkflow.run(
            maxAttempts: 1,
            sync: { await events.append("sync") },
            publish: { await events.append("publish") },
            waitBeforeRetry: { _ in }
        )

        let recordedEvents = await events.values
        XCTAssertEqual(recordedEvents, ["sync", "publish"])
    }

    func testFailedSyncPreventsStalePublication() async {
        struct SyncFailure: Error {}
        let events = Events()

        do {
            try await PublicWebRepairWorkflow.run(
                maxAttempts: 1,
                sync: {
                    await events.append("sync")
                    throw SyncFailure()
                },
                publish: { await events.append("publish") },
                waitBeforeRetry: { _ in }
            )
            XCTFail("Expected the authoritative sync to fail")
        } catch {
            let recordedEvents = await events.values
            XCTAssertEqual(recordedEvents, ["sync"])
        }
    }

    func testTransientFailureRetriesFullSyncBeforePublishing() async throws {
        actor Attempts {
            var syncCount = 0
            var publishCount = 0

            func sync() throws {
                syncCount += 1
                if syncCount == 1 { throw URLError(.timedOut) }
            }

            func publish() {
                publishCount += 1
            }
        }
        let attempts = Attempts()

        try await PublicWebRepairWorkflow.run(
            maxAttempts: 3,
            sync: { try await attempts.sync() },
            publish: { await attempts.publish() },
            waitBeforeRetry: { _ in }
        )

        let syncCount = await attempts.syncCount
        let publishCount = await attempts.publishCount
        XCTAssertEqual(syncCount, 2)
        XCTAssertEqual(publishCount, 1)
    }

    func testLegacyCheckpointDoesNotSuppressConsecutiveLaunchReconciliation() async throws {
        actor Attempts {
            var syncCount = 0
            var publishCount = 0

            func sync() {
                syncCount += 1
            }

            func publish() {
                publishCount += 1
            }
        }
        let attempts = Attempts()
        let ownerID = UUID()
        let suiteName = "PublicWebRepairLaunchPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let legacyKey = "hasRepairedPublicWebSnapshots_v1_\(ownerID.uuidString)"
        defaults.set(true, forKey: legacyKey)

        for _ in 0..<2 {
            try await PublicWebRepairWorkflow.reconcileOnLaunch(
                ownerID: ownerID,
                defaults: defaults,
                maxAttempts: 1,
                sync: { await attempts.sync() },
                publish: { await attempts.publish() },
                waitBeforeRetry: { _ in }
            )
        }

        let syncCount = await attempts.syncCount
        let publishCount = await attempts.publishCount
        XCTAssertEqual(syncCount, 2)
        XCTAssertEqual(publishCount, 2)
        XCTAssertNil(defaults.object(forKey: legacyKey))
    }

    func testCanonicalRecordMustBelongToFirebasePointerOwner() {
        let expectedOwner = UUID()
        XCTAssertTrue(SharedContentAuthority.matches(
            pointerOwnerID: expectedOwner,
            recordOwnerID: expectedOwner
        ))
        XCTAssertFalse(SharedContentAuthority.matches(
            pointerOwnerID: expectedOwner,
            recordOwnerID: UUID()
        ))
        XCTAssertFalse(SharedContentAuthority.matches(
            pointerOwnerID: nil,
            recordOwnerID: expectedOwner
        ))
    }
}
