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
    func testMalformedDeadLetterStoreRemainsVisibleAsActionableDiagnostic() {
        let capturedAt = Date(timeIntervalSince1970: 123)
        let data = Data("not-json".utf8)

        let decoded = OperationQueueService.decodePersistedDeadLetters(
            data,
            capturedAt: capturedAt
        )

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.operationId, "diagnostics")
        XCTAssertEqual(decoded.first?.capturedAt, capturedAt)
        XCTAssertEqual(decoded.first?.rawJSON, data)
    }

    func testDeadLetterCompactionKeepsNewestNinetyNineDetailsAndOneSummary() {
        let entries = (0..<120).map { index in
            DeadLetteredSyncOperation(
                operationId: "operation-\(index)",
                errorDescription: "error-\(index)",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                rawJSON: nil
            )
        }

        let bounded = OperationQueueService.boundedDeadLetters(
            entries,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        let details = bounded.filter { $0.operationId != "compacted" }
        XCTAssertEqual(bounded.count, 100)
        XCTAssertEqual(details.count, 99)
        XCTAssertEqual(Set(details.map(\.operationId)), Set((21..<120).map { "operation-\($0)" }))
        XCTAssertEqual(bounded.filter { $0.operationId == "compacted" }.count, 1)
    }

    func testDeadLetterCompactionTruncatesRawJSON() {
        let oversized = Data(repeating: 0xAB, count: 100 * 1024)
        let entry = DeadLetteredSyncOperation(
            operationId: "operation",
            errorDescription: "error",
            capturedAt: .distantPast,
            rawJSON: oversized
        )

        let bounded = OperationQueueService.boundedDeadLetters([entry])

        XCTAssertEqual(bounded.first?.rawJSON?.count, 64 * 1024)
        XCTAssertEqual(bounded.first?.rawJSON, Data(oversized.prefix(64 * 1024)))
    }

    func testMalformedDeadLetterStoreTruncatesPreservedBytes() {
        let corrupted = Data(repeating: 0xFF, count: 100 * 1024)

        let decoded = OperationQueueService.decodePersistedDeadLetters(corrupted)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.operationId, "diagnostics")
        XCTAssertEqual(decoded.first?.rawJSON?.count, 64 * 1024)
        XCTAssertEqual(decoded.first?.rawJSON, Data(corrupted.prefix(64 * 1024)))
    }

    func testCompactionSummarySurvivesDecodeAndKeepsSyncHealthActionable() throws {
        let entries = (0..<120).map { index in
            DeadLetteredSyncOperation(
                operationId: "operation-\(index)",
                errorDescription: "error",
                capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                rawJSON: nil
            )
        }
        let compactedAt = Date(timeIntervalSince1970: 1_000)
        let compacted = OperationQueueService.boundedDeadLetters(entries, capturedAt: compactedAt)

        let decoded = OperationQueueService.decodePersistedDeadLetters(
            try JSONEncoder().encode(compacted),
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let snapshot = SyncHealthSnapshot.make(operations: [], deadLetterCount: decoded.count)

        XCTAssertEqual(decoded.count, 100)
        XCTAssertEqual(decoded.filter { $0.operationId == "compacted" }.count, 1)
        XCTAssertEqual(decoded.first { $0.operationId == "compacted" }?.capturedAt, compactedAt)
        XCTAssertEqual(snapshot.status, .actionRequired)
        XCTAssertEqual(snapshot.deadLetterCount, 100)
    }

    func testAccountScopedOperationPersistsOwnerAndRevision() throws {
        let ownerId = UUID()
        let revision = UUID()
        let operation = SyncOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: ownerId,
            accountRevision: revision
        )

        let decoded = try JSONDecoder().decode(
            SyncOperation.self,
            from: JSONEncoder().encode(operation)
        )

        XCTAssertEqual(decoded.ownerId, ownerId)
        XCTAssertEqual(decoded.accountRevision, revision)
    }

    func testLegacyOperationWithoutAccountScopeStillDecodes() throws {
        let operation = SyncOperation(
            type: .delete,
            entityType: .savedRecipeReference,
            entityId: UUID()
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(operation)) as? [String: Any]
        )
        object.removeValue(forKey: "ownerId")
        object.removeValue(forKey: "accountRevision")
        object.removeValue(forKey: "accountIdentity")

        let decoded = try JSONDecoder().decode(
            SyncOperation.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertNil(decoded.ownerId)
        XCTAssertNil(decoded.accountRevision)
        XCTAssertNil(decoded.accountIdentity)
    }

    func testAccountPolicyAllowsCurrentScopeAndDefersUntilSameCloudIdentityReturns() {
        let ownerId = UUID()
        let revision = UUID()
        let identity = "icloud-A"
        let scope = SyncOperationAccountScope(ownerId: ownerId, revision: revision, cloudKitIdentity: identity)
        let operation = SyncOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: ownerId,
            accountRevision: revision,
            accountIdentity: identity
        )

        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: ownerId,
                currentScope: scope
            ),
            .allowed
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: UUID(),
                currentScope: scope
            ),
            .deferred
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: ownerId,
                currentScope: SyncOperationAccountScope(ownerId: ownerId, revision: UUID(), cloudKitIdentity: identity)
            ),
            .migrateLegacy
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: ownerId,
                currentScope: SyncOperationAccountScope(ownerId: ownerId, revision: UUID(), cloudKitIdentity: "icloud-B")
            ),
            .deferred
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: ownerId,
                currentScope: nil
            ),
            .deferred
        )
    }

    func testLegacyAccountPolicyRequiresMatchingCurrentOwnerBeforeMigration() {
        let ownerId = UUID()
        let legacy = SyncOperation(
            type: .create,
            entityType: .savedCollectionReference,
            entityId: UUID()
        )
        let scope = SyncOperationAccountScope(ownerId: ownerId, revision: UUID())

        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: legacy,
                entityOwnerId: ownerId,
                currentScope: scope
            ),
            .migrateLegacy
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: legacy,
                entityOwnerId: UUID(),
                currentScope: scope
            ),
            .deferred
        )
    }

    func testReturningCloudIdentityRebindsPreservedOutboxToCurrentRevision() async throws {
        let ownerID = UUID()
        let oldRevision = UUID()
        let newScope = SyncOperationAccountScope(
            ownerId: ownerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let queue = OperationQueueService()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID(),
            ownerId: ownerID,
            accountRevision: oldRevision,
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: operation,
                entityOwnerId: ownerID,
                currentScope: newScope
            ),
            .migrateLegacy
        )
        let reboundOperation = await queue.bindLegacyOperation(operationId: operationID, scope: newScope)
        let rebound = try XCTUnwrap(reboundOperation)
        XCTAssertEqual(rebound.ownerId, ownerID)
        XCTAssertEqual(rebound.accountIdentity, "icloud-A")
        XCTAssertEqual(rebound.accountRevision, newScope.revision)
        XCTAssertEqual(rebound.status, .pending)
    }

    func testVerifiedCloudIdentityCanRebindOperationToCanonicalOwner() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let queue = OperationQueueService()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        await queue.markFailed(operationId: operationID, error: "temporary")
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )

        let rebound = await queue.rebindOperationOwner(
            operationId: operationID,
            previousOwnerID: previousOwnerID,
            scope: scope
        )

        XCTAssertEqual(rebound?.ownerId, canonicalOwnerID)
        XCTAssertEqual(rebound?.accountRevision, scope.revision)
        XCTAssertEqual(rebound?.accountIdentity, scope.cloudKitIdentity)
        XCTAssertEqual(rebound?.status, .pending)
        XCTAssertEqual(rebound?.attempts, 1)
        XCTAssertNil(rebound?.nextRetryDate)
    }

    func testOperationOwnerRebindRefusesDifferentCloudIdentity() async {
        let previousOwnerID = UUID()
        let queue = OperationQueueService()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )

        let rebound = await queue.rebindOperationOwner(
            operationId: operationID,
            previousOwnerID: previousOwnerID,
            scope: SyncOperationAccountScope(
                ownerId: UUID(),
                revision: UUID(),
                cloudKitIdentity: "icloud-B"
            )
        )

        XCTAssertNil(rebound)
        let unchanged = await queue.getOperation(operationId: operationID)
        XCTAssertEqual(unchanged?.ownerId, previousOwnerID)
        XCTAssertEqual(unchanged?.accountIdentity, "icloud-A")
    }

    func testPartialAccountScopesAreRejectedRatherThanMigrated() {
        let ownerId = UUID()
        let scope = SyncOperationAccountScope(ownerId: ownerId, revision: UUID())
        let ownerOnly = SyncOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: ownerId,
            accountRevision: nil
        )
        let revisionOnly = SyncOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: nil,
            accountRevision: scope.revision
        )

        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(operation: ownerOnly, entityOwnerId: ownerId, currentScope: scope),
            .reject
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(operation: revisionOnly, entityOwnerId: ownerId, currentScope: scope),
            .reject
        )
    }

    func testQueueDoesNotBindPartiallyScopedOperationsAsLegacy() async {
        let queueService = OperationQueueService()
        let scope = SyncOperationAccountScope(ownerId: UUID(), revision: UUID())
        for partialScope in [
            (ownerId: Optional(scope.ownerId), revision: Optional<UUID>.none),
            (ownerId: Optional<UUID>.none, revision: Optional(scope.revision))
        ] {
            let operationId = await queueService.addOperation(
                type: .update,
                entityType: .collection,
                entityId: UUID(),
                ownerId: partialScope.ownerId,
                accountRevision: partialScope.revision
            )
            let result = await queueService.bindLegacyOperation(operationId: operationId, scope: scope)
            XCTAssertEqual(result?.ownerId, partialScope.ownerId)
            XCTAssertEqual(result?.accountRevision, partialScope.revision)
        }
    }

    func testQueueMigratesLegacyScopeAndQuarantinesMismatchAsTerminal() async {
        let queueService = OperationQueueService()
        let entityId = UUID()
        let operationId = await queueService.addOperation(
            type: .update,
            entityType: .collection,
            entityId: entityId
        )
        let scope = SyncOperationAccountScope(ownerId: UUID(), revision: UUID())

        let migrated = await queueService.bindLegacyOperation(operationId: operationId, scope: scope)
        XCTAssertEqual(migrated?.ownerId, scope.ownerId)
        XCTAssertEqual(migrated?.accountRevision, scope.revision)

        await queueService.quarantineOperation(operationId: operationId, error: "account changed")
        let remaining = await queueService.getOperation(operationId: operationId)
        XCTAssertNil(remaining)
    }

    func testQueuedMutationFreshnessUsesPersistedTimestamp() {
        let callerTimestamp = Date(timeIntervalSince1970: 100)
        let persistedTimestamp = Date(timeIntervalSince1970: 101)

        XCTAssertFalse(
            QueuedMutationFreshnessPolicy.matchesPersistedMutation(
                persistedUpdatedAt: persistedTimestamp,
                persistedVisibility: .publicRecipe,
                expectedUpdatedAt: callerTimestamp,
                expectedVisibility: .publicRecipe
            )
        )
        XCTAssertTrue(
            QueuedMutationFreshnessPolicy.matchesPersistedMutation(
                persistedUpdatedAt: persistedTimestamp,
                persistedVisibility: .publicRecipe,
                expectedUpdatedAt: persistedTimestamp,
                expectedVisibility: .publicRecipe
            )
        )
    }

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

    func testDeletionAuthorityAllowsOnlyDeletingOwnersStructuredCleanup() async throws {
        let gate = AccountDeletionGate.shared
        let deletingOwner = UUID()
        let otherOwner = UUID()
        let deletionLease = await gate.begin(ownerID: deletingOwner)

        let permitsBeforeAuthority = await gate.permitsWrite(ownerID: deletingOwner)
        XCTAssertFalse(permitsBeforeAuthority)
        let cleanupLease = try await AccountDeletionGate.withDeletionAuthority(deletionLease) {
            let permitsDeletingOwner = await gate.permitsWrite(ownerID: deletingOwner)
            let permitsOtherOwner = await gate.permitsWrite(ownerID: otherOwner)
            XCTAssertTrue(permitsDeletingOwner)
            XCTAssertTrue(permitsOtherOwner)
            let publicationLease = await gate.acquirePublicationLease(ownerID: deletingOwner)
            return try XCTUnwrap(publicationLease)
        }
        await gate.releasePublicationLease(cleanupLease)

        let permitsAfterAuthority = await gate.permitsWrite(ownerID: deletingOwner)
        XCTAssertFalse(permitsAfterAuthority)
        await gate.end(deletionLease)
        let permitsAfterDeletion = await gate.permitsWrite(ownerID: deletingOwner)
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
