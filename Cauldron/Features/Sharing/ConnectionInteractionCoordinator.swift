//
//  ConnectionInteractionCoordinator.swift
//  Cauldron
//

import Foundation

@MainActor
protocol ConnectionManaging: AnyObject {
    var currentUserId: UUID { get }
    func connectionStatus(with userId: UUID) -> ManagedConnection?
    func sendConnectionRequest(to userId: UUID, user: User) async throws
    func acceptConnection(_ connection: Connection) async throws
    func rejectConnection(_ connection: Connection) async throws
    func deleteConnection(_ connection: Connection) async throws
    func retryFailedOperation(connectionId: UUID) async
}

@MainActor
final class ConnectionInteractionCoordinator {
    private let connectionManager: any ConnectionManaging
    private let currentUserProvider: () -> UUID

    init(
        connectionManager: any ConnectionManaging,
        currentUserProvider: @escaping () -> UUID
    ) {
        self.connectionManager = connectionManager
        self.currentUserProvider = currentUserProvider
    }

    func relationshipState(with userId: UUID) -> ConnectionRelationshipState {
        ConnectionRelationshipState.from(
            managedConnection: connectionManager.connectionStatus(with: userId),
            currentUserId: currentUserProvider(),
            otherUserId: userId
        )
    }

    func sendRequest(to user: User) async throws {
        try await connectionManager.sendConnectionRequest(to: user.id, user: user)
    }

    func acceptRequest(from userId: UUID) async throws {
        guard let managedConnection = connectionManager.connectionStatus(with: userId) else {
            throw ConnectionError.notFound
        }

        let connection = managedConnection.connection
        guard connection.fromUserId == userId,
              connection.toUserId == currentUserProvider(),
              connection.status == .pending else {
            throw ConnectionError.permissionDenied
        }

        try await connectionManager.acceptConnection(connection)
    }

    func rejectRequest(from userId: UUID) async throws {
        guard let managedConnection = connectionManager.connectionStatus(with: userId) else {
            throw ConnectionError.notFound
        }

        let connection = managedConnection.connection
        guard connection.fromUserId == userId,
              connection.toUserId == currentUserProvider(),
              connection.status == .pending else {
            throw ConnectionError.permissionDenied
        }

        try await connectionManager.rejectConnection(connection)
    }

    func removeConnection(with userId: UUID) async throws {
        guard let managedConnection = connectionManager.connectionStatus(with: userId) else {
            throw ConnectionError.notFound
        }
        try await connectionManager.deleteConnection(managedConnection.connection)
    }

    func retryFailedOperation(with userId: UUID) async {
        guard let managedConnection = connectionManager.connectionStatus(with: userId) else {
            return
        }
        await connectionManager.retryFailedOperation(connectionId: managedConnection.id)
    }
}

@MainActor
extension ConnectionManager: ConnectionManaging {}
