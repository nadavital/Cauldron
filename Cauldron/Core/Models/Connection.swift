//
//  Connection.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Status of a connection between users
enum ConnectionStatus: String, Codable, Sendable {
    case pending = "pending"
    case accepted = "accepted"

    // MARK: - Migration Support

    /// Custom decoder to handle legacy "rejected" and "blocked" statuses
    /// These connections should have been deleted, but we handle them gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "pending":
            self = .pending
        case "accepted":
            self = .accepted
        case "rejected", "blocked":
            // Migration: These should be deleted, but if we encounter them,
            // treat as pending so they can be properly handled by the user
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Legacy connection status '\(rawValue)' should be deleted"
                )
            )
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown connection status: \(rawValue)"
                )
            )
        }
    }
}

/// Represents a connection/friendship between two users
struct Connection: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let fromUserId: UUID  // User who sent the request
    let toUserId: UUID    // User who received the request
    let status: ConnectionStatus
    let createdAt: Date
    let updatedAt: Date

    // Cached sender info for notifications (denormalized for performance)
    let fromUsername: String?
    let fromDisplayName: String?

    // Cached receiver/acceptor info for acceptance notifications (denormalized for performance)
    let toUsername: String?
    let toDisplayName: String?

    init(
        id: UUID = UUID(),
        fromUserId: UUID,
        toUserId: UUID,
        status: ConnectionStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        fromUsername: String? = nil,
        fromDisplayName: String? = nil,
        toUsername: String? = nil,
        toDisplayName: String? = nil
    ) {
        self.id = id
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fromUsername = fromUsername
        self.fromDisplayName = fromDisplayName
        self.toUsername = toUsername
        self.toDisplayName = toDisplayName
    }
    
    /// Check if this is an accepted connection
    var isAccepted: Bool {
        status == .accepted
    }
    
    /// Get the other user's ID given the current user's ID
    func otherUserId(currentUserId: UUID) -> UUID? {
        if fromUserId == currentUserId {
            return toUserId
        } else if toUserId == currentUserId {
            return fromUserId
        }
        return nil
    }
    
    /// Check if the current user is the one who sent the request
    func isRequestFromUser(_ userId: UUID) -> Bool {
        fromUserId == userId
    }
}
