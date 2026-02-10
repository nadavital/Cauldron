//
//  ConnectionInteractionCoordinatorTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class ConnectionInteractionCoordinatorTests: XCTestCase {
    private final class MockConnectionManager: ConnectionManaging {
        var currentUserId: UUID
        var managedConnectionsByUserId: [UUID: ManagedConnection] = [:]

        private(set) var sentRequests: [UUID] = []
        private(set) var acceptedConnections: [Connection] = []
        private(set) var rejectedConnections: [Connection] = []
        private(set) var deletedConnections: [Connection] = []
        private(set) var retriedConnectionIds: [UUID] = []

        init(currentUserId: UUID) {
            self.currentUserId = currentUserId
        }

        func connectionStatus(with userId: UUID) -> ManagedConnection? {
            managedConnectionsByUserId[userId]
        }

        func sendConnectionRequest(to userId: UUID, user: User) async throws {
            sentRequests.append(userId)
        }

        func acceptConnection(_ connection: Connection) async throws {
            acceptedConnections.append(connection)
        }

        func rejectConnection(_ connection: Connection) async throws {
            rejectedConnections.append(connection)
        }

        func deleteConnection(_ connection: Connection) async throws {
            deletedConnections.append(connection)
        }

        func retryFailedOperation(connectionId: UUID) async {
            retriedConnectionIds.append(connectionId)
        }
    }

    func testRelationshipState_mapsPendingOutgoingPendingIncomingAcceptedAndSyncing() async throws {
        let currentUserId = UUID()
        let outgoingUserId = UUID()
        let incomingUserId = UUID()
        let connectedUserId = UUID()
        let syncingUserId = UUID()
        let failedUserId = UUID()

        let manager = MockConnectionManager(currentUserId: currentUserId)
        manager.managedConnectionsByUserId[outgoingUserId] = ManagedConnection(
            connection: Connection(fromUserId: currentUserId, toUserId: outgoingUserId, status: .pending),
            syncState: .synced
        )
        manager.managedConnectionsByUserId[incomingUserId] = ManagedConnection(
            connection: Connection(fromUserId: incomingUserId, toUserId: currentUserId, status: .pending),
            syncState: .synced
        )
        manager.managedConnectionsByUserId[connectedUserId] = ManagedConnection(
            connection: Connection(fromUserId: currentUserId, toUserId: connectedUserId, status: .accepted),
            syncState: .synced
        )
        manager.managedConnectionsByUserId[syncingUserId] = ManagedConnection(
            connection: Connection(fromUserId: currentUserId, toUserId: syncingUserId, status: .pending),
            syncState: .pendingSync(retryCount: 1)
        )
        manager.managedConnectionsByUserId[failedUserId] = ManagedConnection(
            connection: Connection(fromUserId: currentUserId, toUserId: failedUserId, status: .pending),
            syncState: .syncFailed(ConnectionError.maxRetriesExceeded)
        )

        let coordinator = ConnectionInteractionCoordinator(
            connectionManager: manager,
            currentUserProvider: { currentUserId }
        )

        XCTAssertEqual(coordinator.relationshipState(with: currentUserId), .currentUser)
        XCTAssertEqual(coordinator.relationshipState(with: UUID()), .none)
        XCTAssertEqual(coordinator.relationshipState(with: outgoingUserId), .pendingOutgoing)
        XCTAssertEqual(coordinator.relationshipState(with: incomingUserId), .pendingIncoming)
        XCTAssertEqual(coordinator.relationshipState(with: connectedUserId), .connected)
        XCTAssertEqual(coordinator.relationshipState(with: syncingUserId), .syncing)
        XCTAssertEqual(coordinator.relationshipState(with: failedUserId), .failed(.maxRetriesExceeded))
    }

    func testCoordinator_acceptRejectSend_routeThroughConnectionManager() async throws {
        let currentUserId = UUID()
        let incomingUserId = UUID()
        let connectedUserId = UUID()
        let retryUserId = UUID()

        let incomingConnection = Connection(
            fromUserId: incomingUserId,
            toUserId: currentUserId,
            status: .pending
        )
        let connectedConnection = Connection(
            fromUserId: currentUserId,
            toUserId: connectedUserId,
            status: .accepted
        )
        let retryConnection = Connection(
            fromUserId: currentUserId,
            toUserId: retryUserId,
            status: .pending
        )

        let manager = MockConnectionManager(currentUserId: currentUserId)
        manager.managedConnectionsByUserId[incomingUserId] = ManagedConnection(
            connection: incomingConnection,
            syncState: .synced
        )
        manager.managedConnectionsByUserId[connectedUserId] = ManagedConnection(
            connection: connectedConnection,
            syncState: .synced
        )
        manager.managedConnectionsByUserId[retryUserId] = ManagedConnection(
            connection: retryConnection,
            syncState: .syncFailed(ConnectionError.maxRetriesExceeded)
        )

        let coordinator = ConnectionInteractionCoordinator(
            connectionManager: manager,
            currentUserProvider: { currentUserId }
        )

        let targetUser = User(
            id: UUID(),
            username: "target",
            displayName: "Target User",
            email: "target@example.com"
        )

        try await coordinator.sendRequest(to: targetUser)
        try await coordinator.acceptRequest(from: incomingUserId)
        try await coordinator.rejectRequest(from: incomingUserId)
        try await coordinator.removeConnection(with: connectedUserId)
        await coordinator.retryFailedOperation(with: retryUserId)

        XCTAssertEqual(manager.sentRequests, [targetUser.id])
        XCTAssertEqual(manager.acceptedConnections, [incomingConnection])
        XCTAssertEqual(manager.rejectedConnections, [incomingConnection])
        XCTAssertEqual(manager.deletedConnections, [connectedConnection])
        XCTAssertEqual(manager.retriedConnectionIds, [retryConnection.id])
    }
}
