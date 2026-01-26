//
//  CloudKitService+Connections.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

extension CloudKitService {
    // MARK: - Connections

    /// Accept a connection request
    func acceptConnectionRequest(_ connection: Connection) async throws {
        logger.info("🔄 Accepting connection request: \(connection.id) from \(connection.fromUserId) to \(connection.toUserId)")

        let accepted = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date()
        )

        try await saveConnection(accepted)
        logger.info("✅ Connection accepted and saved: \(connection.id) - new status: \(accepted.status.rawValue)")
    }

    /// Reject a connection request by deleting it
    /// This makes it invisible to both users and allows the sender to try again
    func rejectConnectionRequest(_ connection: Connection) async throws {
        logger.info("🔄 Rejecting connection request: \(connection.id) from \(connection.fromUserId) to \(connection.toUserId)")

        // Delete the connection entirely - cleaner than marking as rejected
        try await deleteConnection(connection)
        logger.info("✅ Connection request rejected and deleted: \(connection.id)")
    }

    /// Save connection to CloudKit PUBLIC database
    /// Uses CKModifyRecordsOperation with .changedKeys save policy to allow updates by any user
    func saveConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try getPublicDatabase()

        // Try to fetch existing record first
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing connection: \(connection.id)")
        } catch {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: connectionRecordType, recordID: recordID)
            logger.info("Creating new connection: \(connection.id)")
        }

        // Update record fields
        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["fromUserId"] = connection.fromUserId.uuidString as CKRecordValue
        record["toUserId"] = connection.toUserId.uuidString as CKRecordValue
        record["status"] = connection.status.rawValue as CKRecordValue
        record["createdAt"] = connection.createdAt as CKRecordValue
        record["updatedAt"] = connection.updatedAt as CKRecordValue

        // Sender info for personalized notifications
        if let fromUsername = connection.fromUsername {
            record["fromUsername"] = fromUsername as CKRecordValue
        }
        if let fromDisplayName = connection.fromDisplayName {
            record["fromDisplayName"] = fromDisplayName as CKRecordValue
        }

        // Acceptor info for acceptance notifications
        if let toUsername = connection.toUsername {
            record["toUsername"] = toUsername as CKRecordValue
        }
        if let toDisplayName = connection.toDisplayName {
            record["toDisplayName"] = toDisplayName as CKRecordValue
        }

        // Use modifyRecords with .changedKeys to allow any authenticated user to update
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys // Allow updates even if not the creator
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.logger.info("Successfully saved connection to PUBLIC database: \(connection.id)")
                    continuation.resume()
                case .failure(let error):
                    self.logger.error("Failed to save connection: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            operation.database = db
            operation.start()
        }
    }
    
    /// Fetch connections for a user from CloudKit PUBLIC database
    func fetchConnections(forUserId userId: UUID) async throws -> [Connection] {
        // Fetching connections (don't log routine operations)
        let db = try getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>() // Track IDs to avoid duplicates

        // Run both queries in parallel for better performance
        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: connectionRecordType, predicate: fromPredicate)

        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: connectionRecordType, predicate: toPredicate)

        // Execute both queries concurrently
        async let fromResultsTask = db.records(matching: fromQuery)
        async let toResultsTask = db.records(matching: toQuery)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

        // Process results from both queries
        for (_, result) in fromResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy connections (rejected/blocked) - they should be deleted
                    logger.info("⏭️ Skipping legacy connection record (likely rejected/blocked): \(record.recordID.recordName)")
                }
            }
        }

        for (_, result) in toResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy connections (rejected/blocked) - they should be deleted
                    logger.info("⏭️ Skipping legacy connection record (likely rejected/blocked): \(record.recordID.recordName)")
                }
            }
        }

        // Fetched connections from CloudKit (don't log routine operations)

        // Clean up duplicates - remove duplicate connections between same two users
        let cleanedConnections = try await removeDuplicateConnections(connections)

        // Return cleaned connections (don't log count - routine operation)
        return cleanedConnections
    }

    /// Check if a connection already exists between two users (any direction)
    func connectionExists(between userA: UUID, and userB: UUID) async throws -> Bool {
        let db = try getPublicDatabase()

        // CloudKit doesn't support OR predicates, so check both directions separately
        // Direction 1: userA -> userB
        let predicate1 = NSPredicate(format: "fromUserId == %@ AND toUserId == %@", userA.uuidString, userB.uuidString)
        let query1 = CKQuery(recordType: connectionRecordType, predicate: predicate1)
        let results1 = try await db.records(matching: query1, resultsLimit: 1)

        if results1.matchResults.contains(where: { (try? $0.1.get()) != nil }) {
            return true
        }

        // Direction 2: userB -> userA
        let predicate2 = NSPredicate(format: "fromUserId == %@ AND toUserId == %@", userB.uuidString, userA.uuidString)
        let query2 = CKQuery(recordType: connectionRecordType, predicate: predicate2)
        let results2 = try await db.records(matching: query2, resultsLimit: 1)

        return results2.matchResults.contains(where: { (try? $0.1.get()) != nil })
    }

    /// Fetch connections for multiple users (batch fetch)
    /// Used for finding friends-of-friends
    func fetchConnections(forUserIds userIds: [UUID]) async throws -> [Connection] {
        guard !userIds.isEmpty else { return [] }

        let db = try getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>() // Track IDs to avoid duplicates

        // Convert UUIDs to Strings
        let userIdStrings = userIds.map { $0.uuidString }

        // Run both queries in parallel for better performance
        let fromPredicate = NSPredicate(format: "fromUserId IN %@", userIdStrings)
        let fromQuery = CKQuery(recordType: connectionRecordType, predicate: fromPredicate)

        let toPredicate = NSPredicate(format: "toUserId IN %@", userIdStrings)
        let toQuery = CKQuery(recordType: connectionRecordType, predicate: toPredicate)

        // Execute both queries concurrently
        async let fromResultsTask = db.records(matching: fromQuery, resultsLimit: 200)
        async let toResultsTask = db.records(matching: toQuery, resultsLimit: 200)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

        // Process results from both queries
        for (_, result) in fromResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy/invalid
                }
            }
        }

        for (_, result) in toResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
                    // Skip legacy/invalid
                }
            }
        }

        // Return raw connections (duplicate Logic is handled by caller if needed for specific pairs, here we just want the graph)
        return connections
    }

    /// Remove duplicate connections between the same two users
    /// Keeps the most recent one (by updatedAt), deletes older duplicates
    func removeDuplicateConnections(_ connections: [Connection]) async throws -> [Connection] {
        // Group connections by user pair (regardless of direction)
        var connectionsByPair: [Set<UUID>: [Connection]] = [:]

        for connection in connections {
            let userPair = Set([connection.fromUserId, connection.toUserId])
            connectionsByPair[userPair, default: []].append(connection)
        }

        var connectionsToKeep: [Connection] = []
        let db = try getPublicDatabase()

        // For each user pair, keep only the most recent connection
        for (userPair, pairConnections) in connectionsByPair {
            if pairConnections.count > 1 {
                // Sort by updatedAt descending (newest first)
                let sorted = pairConnections.sorted { $0.updatedAt > $1.updatedAt }
                let toKeep = sorted.first!
                let toDelete = Array(sorted.dropFirst())

                logger.warning("🧹 Found \(pairConnections.count) duplicate connections for users \(Array(userPair))")
                logger.info("  Keeping: \(toKeep.id) (status: \(toKeep.status.rawValue), updated: \(toKeep.updatedAt))")

                // Delete the older duplicates from CloudKit
                for duplicate in toDelete {
                    logger.info("  Deleting duplicate: \(duplicate.id) (status: \(duplicate.status.rawValue), updated: \(duplicate.updatedAt))")
                    do {
                        let recordID = CKRecord.ID(recordName: duplicate.id.uuidString)
                        try await db.deleteRecord(withID: recordID)
                        logger.info("  ✅ Deleted duplicate connection: \(duplicate.id)")
                    } catch {
                        logger.error("  ❌ Failed to delete duplicate: \(error.localizedDescription)")
                    }
                }

                connectionsToKeep.append(toKeep)
            } else {
                // No duplicates for this pair
                connectionsToKeep.append(pairConnections[0])
            }
        }

        return connectionsToKeep
    }
    
    /// Delete a connection from CloudKit PUBLIC database
    func deleteConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try getPublicDatabase()

        try await db.deleteRecord(withID: recordID)
        logger.info("Deleted connection from PUBLIC database: \(connection.id)")
    }

    /// Delete all connections involving a user from CloudKit PUBLIC database
    /// Used during account deletion to clean up friend relationships
    func deleteAllConnectionsForUser(userId: UUID) async throws {
        logger.info("🗑️ Deleting all connections for user: \(userId)")
        let db = try getPublicDatabase()

        // Query connections where user is the sender (fromUserId)
        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: connectionRecordType, predicate: fromPredicate)

        // Query connections where user is the receiver (toUserId)
        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: connectionRecordType, predicate: toPredicate)

        // Execute both queries concurrently
        async let fromResultsTask = db.records(matching: fromQuery)
        async let toResultsTask = db.records(matching: toQuery)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

        // Collect all record IDs to delete
        var recordIDs: [CKRecord.ID] = []

        for (recordID, result) in fromResults.matchResults {
            if (try? result.get()) != nil {
                recordIDs.append(recordID)
            }
        }

        for (recordID, result) in toResults.matchResults {
            if (try? result.get()) != nil {
                recordIDs.append(recordID)
            }
        }

        guard !recordIDs.isEmpty else {
            logger.info("No connections found to delete for user: \(userId)")
            return
        }

        logger.info("Found \(recordIDs.count) connections to delete for user: \(userId)")

        // Batch delete using modifyRecords
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    self.logger.info("✅ Successfully deleted \(recordIDs.count) connections for user: \(userId)")
                    continuation.resume()
                case .failure(let error):
                    self.logger.error("❌ Failed to delete connections: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
            operation.database = db
            operation.start()
        }
    }

    func connectionFromRecord(_ record: CKRecord) throws -> Connection {
        guard let connectionIdString = record["connectionId"] as? String,
              let connectionId = UUID(uuidString: connectionIdString),
              let fromUserIdString = record["fromUserId"] as? String,
              let fromUserId = UUID(uuidString: fromUserIdString),
              let toUserIdString = record["toUserId"] as? String,
              let toUserId = UUID(uuidString: toUserIdString),
              let statusString = record["status"] as? String,
              let status = ConnectionStatus(rawValue: statusString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        // Optional sender info for notifications
        let fromUsername = record["fromUsername"] as? String
        let fromDisplayName = record["fromDisplayName"] as? String

        // Optional acceptor/receiver info for acceptance notifications
        let toUsername = record["toUsername"] as? String
        let toDisplayName = record["toDisplayName"] as? String

        return Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            fromUsername: fromUsername,
            fromDisplayName: fromDisplayName,
            toUsername: toUsername,
            toDisplayName: toDisplayName
        )
    }
}
