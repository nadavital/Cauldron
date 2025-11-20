//
//  ConnectionRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftData
import os

/// Repository for managing connections between users
actor ConnectionRepository {
    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "ConnectionRepository")
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    // MARK: - Fetch
    
    /// Fetch all connections for a user
    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ConnectionModel>()
        let models = try context.fetch(descriptor)
        
        return models
            .compactMap { $0.toDomain() }
            .filter { $0.fromUserId == userId || $0.toUserId == userId }
    }
    
    /// Fetch accepted connections (friends) for a user
    func fetchAcceptedConnections(forUserId userId: UUID) async throws -> [Connection] {
        let connections = try await fetchConnections(forUserId: userId)
        return connections.filter { $0.isAccepted }
    }
    
    /// Fetch pending connection requests sent by user
    func fetchSentRequests(fromUserId userId: UUID) async throws -> [Connection] {
        let connections = try await fetchConnections(forUserId: userId)
        return connections.filter { $0.fromUserId == userId && $0.status == .pending }
    }
    
    /// Fetch pending connection requests received by user
    func fetchReceivedRequests(forUserId userId: UUID) async throws -> [Connection] {
        let connections = try await fetchConnections(forUserId: userId)
        return connections.filter { $0.toUserId == userId && $0.status == .pending }
    }
    
    /// Find connection between two users
    func fetchConnection(fromUserId: UUID, toUserId: UUID) async throws -> Connection? {
        let connections = try await fetchConnections(forUserId: fromUserId)
        return connections.first { connection in
            (connection.fromUserId == fromUserId && connection.toUserId == toUserId) ||
            (connection.fromUserId == toUserId && connection.toUserId == fromUserId)
        }
    }
    
    /// Check if two users are connected
    func areConnected(user1: UUID, user2: UUID) async throws -> Bool {
        if let connection = try await fetchConnection(fromUserId: user1, toUserId: user2) {
            return connection.isAccepted
        }
        return false
    }
    
    // MARK: - Save
    
    /// Save or update a connection
    func save(_ connection: Connection) async throws {
        let context = ModelContext(modelContainer)
        
        // Check if connection already exists
        let descriptor = FetchDescriptor<ConnectionModel>(
            predicate: #Predicate { $0.id == connection.id }
        )
        let existing = try context.fetch(descriptor)
        
        if let existingModel = existing.first {
            // Update existing
            existingModel.status = connection.status.rawValue
            existingModel.updatedAt = connection.updatedAt
        } else {
            // Insert new
            let model = ConnectionModel.from(connection)
            context.insert(model)
        }
        
        try context.save()
        // Saved connection to cache (don't log routine operations)
    }
    
    // MARK: - Delete
    
    /// Delete a connection
    func delete(_ connection: Connection) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ConnectionModel>(
            predicate: #Predicate { $0.id == connection.id }
        )
        let models = try context.fetch(descriptor)
        
        if let model = models.first {
            context.delete(model)
            try context.save()
            logger.info("Deleted connection: \(connection.id)")
        }
    }
}
