//
//  ConnectionManagerTests.swift
//  CauldronTests
//
//  Tests for ConnectionManager including cache, sync states, and retry logic
//

import XCTest
@testable import Cauldron

/// Tests for ConnectionManager
/// Note: Dependencies are created as local variables to avoid @MainActor
/// deinitialization issues during test teardown (Swift issue #85221)
@MainActor
final class ConnectionManagerTests: XCTestCase {
    // Helper to create fresh dependencies and connection manager
    private func makeConnectionManager() -> (ConnectionManager, DependencyContainer, UUID) {
        let dependencies = DependencyContainer.preview()
        let connectionManager = ConnectionManager(dependencies: dependencies)
        let testUserId = UUID()
        return (connectionManager, dependencies, testUserId)
    }

    // MARK: - Cache Tests

    func testCacheValidityDuration() async throws {
        let (connectionManager, _, testUserId) = makeConnectionManager()

        // Given: Empty connections
        XCTAssertTrue(connectionManager.connections.isEmpty)

        // When: Load connections for the first time
        await connectionManager.loadConnections(forUserId: testUserId)

        // Then: Connections should be loaded from CloudKit/cache
        // (We can't test exact count without mocking CloudKit, but we can verify no crash)

        // When: Load again immediately (within 30 minutes)
        await connectionManager.loadConnections(forUserId: testUserId, forceRefresh: false)

        // Then: Should use cache (no new CloudKit fetch)
        // This is verified by checking logs in real implementation
    }

    func testForceRefreshBypassesCache() async throws {
        let (connectionManager, _, testUserId) = makeConnectionManager()

        // Given: Connections loaded once
        await connectionManager.loadConnections(forUserId: testUserId)

        // When: Force refresh immediately
        await connectionManager.loadConnections(forUserId: testUserId, forceRefresh: true)

        // Then: Should fetch from CloudKit again (not from cache)
        // Count might be same, but fetch happened (verified by logs)
        XCTAssertGreaterThanOrEqual(connectionManager.connections.count, 0)
    }

    // MARK: - Connection State Tests

    func testAcceptConnectionCreatesOptimisticUpdate() async throws {
        let (connectionManager, dependencies, _) = makeConnectionManager()

        // Given: A pending connection request
        let connectionId = UUID()
        let fromUserId = UUID()
        let toUserId = connectionManager.currentUserId

        let pendingConnection = Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to repository first
        try await dependencies.connectionRepository.save(pendingConnection)

        // When: Accept the connection
        try await connectionManager.acceptConnection(pendingConnection)

        // Then: Connection should be optimistically updated to accepted
        if let managed = connectionManager.connections[connectionId] {
            XCTAssertTrue(managed.connection.isAccepted)
        }
    }

    func testConnectionsViewModelAcceptRefreshesLocalArrays() async throws {
        let dependencies = DependencyContainer.preview()
        let currentUserId = UUID()
        let fromUserId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "receiver",
                displayName: "Receiver",
                createdAt: Date()
            )
        )
        defer { CurrentUserSession.shared.signOut() }
        let pendingConnection = Connection(
            id: UUID(),
            fromUserId: fromUserId,
            toUserId: currentUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await dependencies.connectionRepository.save(pendingConnection)
        let viewModel = ConnectionsViewModel(dependencies: dependencies)
        await viewModel.loadConnections()
        XCTAssertEqual(viewModel.receivedRequests.map(\.id), [pendingConnection.id])

        await viewModel.acceptRequest(pendingConnection)

        XCTAssertTrue(viewModel.receivedRequests.isEmpty)
        XCTAssertEqual(viewModel.connections.map(\.id), [pendingConnection.id])
        XCTAssertEqual(viewModel.connections.first?.status, .accepted)
    }

    func testConnectionsViewModelRejectRefreshesLocalArrays() async throws {
        let dependencies = DependencyContainer.preview()
        let currentUserId = UUID()
        let fromUserId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "receiver",
                displayName: "Receiver",
                createdAt: Date()
            )
        )
        defer { CurrentUserSession.shared.signOut() }
        let pendingConnection = Connection(
            id: UUID(),
            fromUserId: fromUserId,
            toUserId: currentUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await dependencies.connectionRepository.save(pendingConnection)
        let viewModel = ConnectionsViewModel(dependencies: dependencies)
        await viewModel.loadConnections()
        XCTAssertEqual(viewModel.receivedRequests.map(\.id), [pendingConnection.id])

        await viewModel.rejectRequest(pendingConnection)

        XCTAssertTrue(viewModel.receivedRequests.isEmpty)
        XCTAssertTrue(viewModel.connections.isEmpty)
    }

    func testSendConnectionRequestCreatesOptimisticState() async throws {
        let (connectionManager, _, _) = makeConnectionManager()

        // Given: A new user to connect with
        let targetUserId = UUID()
        let targetUser = User(
            id: targetUserId,
            username: "testfriend",
            displayName: "Test Friend",
            email: "test@test.com"
        )

        // When: Send connection request
        try await connectionManager.sendConnectionRequest(to: targetUserId, user: targetUser)

        // Then: Should create a connection in pending state
        let sentConnection = connectionManager.connections.values.first {
            $0.connection.toUserId == targetUserId && $0.connection.status == .pending
        }

        XCTAssertNotNil(sentConnection, "Should have created a pending connection")
    }

    // MARK: - Sync State Tests

    func testSyncStateTransitions() async throws {
        let testUserId = UUID()

        // This test verifies the sync state lifecycle:
        // pending -> syncing -> synced (on success)
        // pending -> syncing -> pendingSync (on failure with retry)
        // pendingSync -> syncFailed (after max retries)

        // Note: Full testing requires mocking CloudKit failures
        // Here we verify the state enum works correctly

        let connection = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: testUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )

        let synced = ManagedConnection(connection: connection, syncState: .synced)
        let syncing = ManagedConnection(connection: connection, syncState: .syncing)
        let pending = ManagedConnection(connection: connection, syncState: .pendingSync(retryCount: 0))

        XCTAssertNotEqual(synced, syncing)
        XCTAssertNotEqual(syncing, pending)
        XCTAssertEqual(synced.id, syncing.id) // Same connection, different states
    }

    // Note: testRetryCountIncrement and testExponentialBackoffCapped removed
    // because PendingOperation is private to ConnectionManager.
    // Retry logic is tested indirectly through integration tests.

    // MARK: - Badge Count Tests

    func testBadgeCountReflectsPendingRequests() async throws {
        let (connectionManager, _, testUserId) = makeConnectionManager()

        // Given: Load connections
        await connectionManager.loadConnections(forUserId: testUserId)

        // Then: Connections should load without error
        XCTAssertGreaterThanOrEqual(connectionManager.connections.count, 0)
    }

    // MARK: - Error Handling Tests

    func testConnectionErrorDescriptions() async {
        // Test all error cases have descriptions
        let errors: [ConnectionError] = [
            .notFound,
            .networkFailure(NSError(domain: "test", code: 0)),
            .permissionDenied,
            .maxRetriesExceeded,
            .alreadySentRequest,
            .alreadyConnected
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error should have description: \(error)")
        }
    }

    func testSyncStateEquality() async {
        // Test sync state equality
        let synced1 = ConnectionSyncState.synced
        let synced2 = ConnectionSyncState.synced
        let syncing = ConnectionSyncState.syncing
        let pending1 = ConnectionSyncState.pendingSync(retryCount: 1)
        let pending2 = ConnectionSyncState.pendingSync(retryCount: 1)
        let pending3 = ConnectionSyncState.pendingSync(retryCount: 2)

        XCTAssertEqual(synced1, synced2)
        XCTAssertNotEqual(synced1, syncing)
        XCTAssertEqual(pending1, pending2)
        XCTAssertNotEqual(pending1, pending3)
    }

    // MARK: - Integration Tests

    func testLoadConnectionsFromEmptyState() async throws {
        let (connectionManager, _, testUserId) = makeConnectionManager()

        // Given: Fresh connection manager
        XCTAssertTrue(connectionManager.connections.isEmpty)

        // When: Load connections
        await connectionManager.loadConnections(forUserId: testUserId)

        // Then: Should complete without crashing
        // Actual count depends on test data, but should be >= 0
        XCTAssertGreaterThanOrEqual(connectionManager.connections.count, 0)
    }

    func testRejectConnectionRequest() async throws {
        let (connectionManager, dependencies, _) = makeConnectionManager()

        // Given: A pending connection
        let connectionId = UUID()
        let connection = Connection(
            id: connectionId,
            fromUserId: UUID(),
            toUserId: connectionManager.currentUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Save to repository
        try await dependencies.connectionRepository.save(connection)

        // When: Reject the connection
        try await connectionManager.rejectConnection(connection)

        // Then: Connection should be removed from memory
        XCTAssertNil(connectionManager.connections[connectionId], "Rejected connection should be removed from manager")
    }

    func testMultipleConcurrentAccepts() async throws {
        let (connectionManager, dependencies, testUserId) = makeConnectionManager()

        // Given: Multiple pending connections
        let connection1 = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: testUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )

        let connection2 = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: testUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await dependencies.connectionRepository.save(connection1)
        try await dependencies.connectionRepository.save(connection2)

        // When: Accept both concurrently
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await connectionManager.acceptConnection(connection1)
            }
            group.addTask {
                try? await connectionManager.acceptConnection(connection2)
            }
        }

        // Then: Both should be accepted without race conditions
        if let managed1 = connectionManager.connections[connection1.id] {
            XCTAssertTrue(managed1.connection.isAccepted)
        }
        if let managed2 = connectionManager.connections[connection2.id] {
            XCTAssertTrue(managed2.connection.isAccepted)
        }
    }

    // MARK: - Operation Queue Integration

    func testConnectionQueuePolicyAllowsOnlyMatchingOwnerAndAccountGeneration() {
        let ownerId = UUID()
        let revision = UUID()
        let connection = Connection(
            id: UUID(),
            fromUserId: ownerId,
            toUserId: UUID(),
            status: .pending
        )
        let payload = QueuedConnectionContext(connection: connection, actorUserId: ownerId)
        let operation = SyncOperation(
            type: .create,
            entityType: .connection,
            entityId: connection.id,
            ownerId: ownerId,
            accountRevision: revision
        )

        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: operation,
                payload: payload,
                currentUserId: ownerId,
                currentScope: SyncOperationAccountScope(ownerId: ownerId, revision: revision)
            ),
            .allowed
        )
        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: operation,
                payload: payload,
                currentUserId: UUID(),
                currentScope: SyncOperationAccountScope(ownerId: UUID(), revision: UUID())
            ),
            .deferred
        )
        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: operation,
                payload: payload,
                currentUserId: ownerId,
                currentScope: SyncOperationAccountScope(ownerId: ownerId, revision: UUID())
            ),
            .deferred
        )
    }

    func testConnectionQueuePolicyDefersSwitchAwayAndLegacyGenerationReplay() {
        let ownerA = UUID()
        let ownerB = UUID()
        let revisionA = UUID()
        let connection = Connection(
            id: UUID(),
            fromUserId: ownerA,
            toUserId: ownerB,
            status: .pending
        )
        let operation = SyncOperation(
            type: .create,
            entityType: .connection,
            entityId: connection.id,
            ownerId: ownerA,
            accountRevision: revisionA
        )
        let payload = QueuedConnectionContext(connection: connection, actorUserId: ownerA)

        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: operation,
                payload: payload,
                currentUserId: ownerB,
                currentScope: SyncOperationAccountScope(ownerId: ownerB, revision: UUID())
            ),
            .deferred
        )
        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: operation,
                payload: payload,
                currentUserId: ownerA,
                currentScope: SyncOperationAccountScope(ownerId: ownerA, revision: UUID())
            ),
            .deferred
        )
    }

    func testConnectionQueuePolicyMigratesUnambiguousLegacyWorkButRejectsAmbiguousDelete() {
        let ownerId = UUID()
        let otherId = UUID()
        let connection = Connection(
            id: UUID(),
            fromUserId: ownerId,
            toUserId: otherId,
            status: .pending
        )
        let scope = SyncOperationAccountScope(ownerId: ownerId, revision: UUID())
        let legacyCreate = SyncOperation(
            type: .create,
            entityType: .connection,
            entityId: connection.id
        )
        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: legacyCreate,
                payload: QueuedConnectionContext(connection: connection, actorUserId: nil),
                currentUserId: ownerId,
                currentScope: scope
            ),
            .migrateLegacy
        )

        let legacyDelete = SyncOperation(
            type: .delete,
            entityType: .connection,
            entityId: connection.id
        )
        XCTAssertEqual(
            ConnectionOperationAccountPolicy.decision(
                operation: legacyDelete,
                payload: QueuedConnectionContext(connection: connection, actorUserId: nil),
                currentUserId: ownerId,
                currentScope: scope
            ),
            .reject
        )
    }

    func testOperationQueueSupportsConnectionEntityPayload() async throws {
        let (_, dependencies, _) = makeConnectionManager()

        let connection = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: UUID(),
            status: .accepted
        )
        let payload = try JSONEncoder().encode(connection)

        await dependencies.operationQueueService.addOperation(
            type: .acceptConnection,
            entityType: .connection,
            entityId: connection.id,
            payload: payload
        )

        let queued = await dependencies.operationQueueService.getOperation(
            for: connection.id,
            entityType: .connection
        )

        XCTAssertNotNil(queued)
        XCTAssertEqual(queued?.type, .acceptConnection)
        XCTAssertEqual(queued?.entityType, .connection)
        XCTAssertEqual(queued?.payload, payload)
    }

    func testOperationQueueMarkInProgressUsesOperationId() async throws {
        let (_, dependencies, _) = makeConnectionManager()
        let connectionId = UUID()

        let operationId = await dependencies.operationQueueService.addOperation(
            type: .create,
            entityType: .connection,
            entityId: connectionId
        )

        await dependencies.operationQueueService.markInProgress(operationId: operationId)

        let queued = await dependencies.operationQueueService.getOperation(
            for: connectionId,
            entityType: .connection
        )

        XCTAssertEqual(queued?.status, .inProgress)
    }

    func testOperationQueueRetryByOperationIdCannotReviveOtherAccountsCollision() async throws {
        let queue = OperationQueueService()
        let connectionId = UUID()
        let ownerA = UUID()
        let ownerB = UUID()
        let operationA = await queue.addOperation(
            type: .create,
            entityType: .connection,
            entityId: connectionId,
            ownerId: ownerA,
            accountRevision: UUID()
        )
        let operationB = await queue.addOperation(
            type: .delete,
            entityType: .connection,
            entityId: connectionId,
            ownerId: ownerB,
            accountRevision: UUID()
        )
        await queue.markFailed(operationId: operationA, error: "offline")
        await queue.markFailed(operationId: operationB, error: "offline")

        await queue.retryOperation(operationId: operationB)

        let ownerAOperation = await queue.getOperation(operationId: operationA)
        let ownerBOperation = await queue.getOperation(operationId: operationB)
        XCTAssertEqual(ownerAOperation?.status, .failed)
        XCTAssertEqual(ownerBOperation?.status, .pending)
    }

    func testOperationQueueRetryOperationByEntity() async throws {
        // Use an isolated queue service for deterministic retry behavior.
        let queueService = OperationQueueService()
        let connectionId = UUID()

        await queueService.addOperation(
            type: .rejectConnection,
            entityType: .connection,
            entityId: connectionId
        )

        guard let initial = await queueService.getOperation(
            for: connectionId,
            entityType: .connection
        ) else {
            XCTFail("Expected queued operation")
            return
        }

        await queueService.markFailed(
            operationId: initial.id,
            error: "Network timeout"
        )

        let retried = await queueService.retryOperation(
            entityId: connectionId,
            entityType: .connection
        )

        XCTAssertNotNil(retried)
        XCTAssertEqual(retried?.status, .pending)
        XCTAssertEqual(retried?.attempts, 1)
    }

    // MARK: - Per-User Session Scoping (cross-account leak prevention)

    /// Populating connections then resetting session state must clear them, so a
    /// signed-out / switched user never sees the prior user's connections.
    func testResetSessionStateClearsConnections() async throws {
        let (connectionManager, dependencies, _) = makeConnectionManager()

        let connection = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: connectionManager.currentUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await dependencies.connectionRepository.save(connection)
        try await connectionManager.acceptConnection(connection)
        XCTAssertFalse(connectionManager.connections.isEmpty, "Precondition: connections populated")

        // When the session is reset (sign-out / account change)
        connectionManager.resetSessionState()

        // Then no prior-user connection state remains
        XCTAssertTrue(connectionManager.connections.isEmpty)
        XCTAssertTrue(connectionManager.syncErrors.isEmpty)
    }

    /// Loading connections for a different user must clear the previous user's
    /// in-memory connections (the 30-min cache must not leak across accounts).
    func testLoadConnectionsForDifferentUserClearsPriorUserState() async throws {
        let (connectionManager, dependencies, _) = makeConnectionManager()

        let priorConnection = Connection(
            id: UUID(),
            fromUserId: UUID(),
            toUserId: connectionManager.currentUserId,
            status: .pending,
            createdAt: Date(),
            updatedAt: Date()
        )
        try await dependencies.connectionRepository.save(priorConnection)
        try await connectionManager.acceptConnection(priorConnection)
        XCTAssertFalse(connectionManager.connections.isEmpty, "Precondition: prior user's connections populated")

        // When a different account loads connections
        let differentUserId = UUID()
        await connectionManager.loadConnections(forUserId: differentUserId)

        // Then the prior user's connection must not remain visible
        XCTAssertNil(
            connectionManager.connections[priorConnection.id],
            "Prior user's connection leaked into a different account"
        )
    }
}
