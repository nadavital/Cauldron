//
//  ConnectionRelationshipState.swift
//  Cauldron
//

import Foundation

/// Unified connection relationship state used across Search/People/Profile surfaces.
enum ConnectionRelationshipState: Equatable {
    case currentUser
    case none
    case pendingOutgoing
    case pendingIncoming
    case connected
    case syncing
    case failed(ConnectionError)

    static func == (lhs: ConnectionRelationshipState, rhs: ConnectionRelationshipState) -> Bool {
        switch (lhs, rhs) {
        case (.currentUser, .currentUser),
             (.none, .none),
             (.pendingOutgoing, .pendingOutgoing),
             (.pendingIncoming, .pendingIncoming),
             (.connected, .connected),
             (.syncing, .syncing):
            return true
        case (.failed(let left), .failed(let right)):
            return left.kind == right.kind
        default:
            return false
        }
    }

    static func from(
        managedConnection: ManagedConnection?,
        currentUserId: UUID,
        otherUserId: UUID
    ) -> ConnectionRelationshipState {
        if otherUserId == currentUserId {
            return .currentUser
        }

        guard let managedConnection = managedConnection else {
            return .none
        }

        switch managedConnection.syncState {
        case .syncing, .pendingSync:
            return .syncing
        case .syncFailed(let error):
            return .failed(error as? ConnectionError ?? .networkFailure(error))
        case .synced:
            break
        }

        let connection = managedConnection.connection
        if connection.isAccepted {
            return .connected
        }

        return connection.fromUserId == currentUserId ? .pendingOutgoing : .pendingIncoming
    }
}

private extension ConnectionError {
    enum Kind: Equatable {
        case notFound
        case networkFailure
        case permissionDenied
        case maxRetriesExceeded
        case alreadySentRequest
        case alreadyConnected
    }

    var kind: Kind {
        switch self {
        case .notFound:
            return .notFound
        case .networkFailure:
            return .networkFailure
        case .permissionDenied:
            return .permissionDenied
        case .maxRetriesExceeded:
            return .maxRetriesExceeded
        case .alreadySentRequest:
            return .alreadySentRequest
        case .alreadyConnected:
            return .alreadyConnected
        }
    }
}
