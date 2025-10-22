//
//  ConnectionModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftData

/// SwiftData model for persisting connections
@Model
final class ConnectionModel {
    var id: UUID = UUID()
    var fromUserId: UUID = UUID()
    var toUserId: UUID = UUID()
    var status: String = ""  // ConnectionStatus rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Cached sender info for notifications
    var fromUsername: String?
    var fromDisplayName: String?

    init(
        id: UUID,
        fromUserId: UUID,
        toUserId: UUID,
        status: String,
        createdAt: Date,
        updatedAt: Date,
        fromUsername: String? = nil,
        fromDisplayName: String? = nil
    ) {
        self.id = id
        self.fromUserId = fromUserId
        self.toUserId = toUserId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fromUsername = fromUsername
        self.fromDisplayName = fromDisplayName
    }
    
    /// Convert to domain model
    func toDomain() -> Connection? {
        guard let connectionStatus = ConnectionStatus(rawValue: status) else {
            return nil
        }

        return Connection(
            id: id,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: connectionStatus,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fromUsername: fromUsername,
            fromDisplayName: fromDisplayName
        )
    }
    
    /// Create from domain model
    static func from(_ connection: Connection) -> ConnectionModel {
        ConnectionModel(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: connection.status.rawValue,
            createdAt: connection.createdAt,
            updatedAt: connection.updatedAt,
            fromUsername: connection.fromUsername,
            fromDisplayName: connection.fromDisplayName
        )
    }
}
