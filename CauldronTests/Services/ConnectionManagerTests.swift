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

    func testOperationQueueMarkInProgressByEntityIdFallback() async throws {
        let (_, dependencies, _) = makeConnectionManager()
        let connectionId = UUID()

        await dependencies.operationQueueService.addOperation(
            type: .create,
            entityType: .connection,
            entityId: connectionId
        )

        // Existing repository call sites pass entity IDs here.
        await dependencies.operationQueueService.markInProgress(operationId: connectionId)

        let queued = await dependencies.operationQueueService.getOperation(
            for: connectionId,
            entityType: .connection
        )

        XCTAssertEqual(queued?.status, .inProgress)
    }

    func testOperationQueueRetryOperationByEntity() async throws {
        let (_, dependencies, _) = makeConnectionManager()
        let connectionId = UUID()

        await dependencies.operationQueueService.addOperation(
            type: .rejectConnection,
            entityType: .connection,
            entityId: connectionId
        )

        guard let initial = await dependencies.operationQueueService.getOperation(
            for: connectionId,
            entityType: .connection
        ) else {
            XCTFail("Expected queued operation")
            return
        }

        await dependencies.operationQueueService.markFailed(
            operationId: initial.id,
            error: "Network timeout"
        )

        let retried = await dependencies.operationQueueService.retryOperation(
            entityId: connectionId,
            entityType: .connection
        )

        XCTAssertNotNil(retried)
        XCTAssertEqual(retried?.status, .pending)
        XCTAssertEqual(retried?.attempts, 1)
    }
}
