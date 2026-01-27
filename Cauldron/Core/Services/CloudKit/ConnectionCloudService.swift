//
//  ConnectionCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for connection/friend operations.
//

import Foundation
import CloudKit
import os

/// CloudKit service for connection/friend-related operations.
///
/// Handles:
/// - Friend connection CRUD
/// - Connection requests and acceptances
/// - Push notification subscriptions
/// - Auto-friend connections from referrals
actor ConnectionCloudService {
    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "ConnectionCloudService")

    init(core: CloudKitCore) {
        self.core = core
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Connection CRUD

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
    func rejectConnectionRequest(_ connection: Connection) async throws {
        logger.info("🔄 Rejecting connection request: \(connection.id) from \(connection.fromUserId) to \(connection.toUserId)")

        try await deleteConnection(connection)
        logger.info("✅ Connection request rejected and deleted: \(connection.id)")
    }

    /// Save connection to CloudKit PUBLIC database
    func saveConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try await core.getPublicDatabase()

        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing connection: \(connection.id)")
        } catch {
            record = CKRecord(recordType: CloudKitCore.RecordType.connection, recordID: recordID)
            logger.info("Creating new connection: \(connection.id)")
        }

        record["connectionId"] = connection.id.uuidString as CKRecordValue
        record["fromUserId"] = connection.fromUserId.uuidString as CKRecordValue
        record["toUserId"] = connection.toUserId.uuidString as CKRecordValue
        record["status"] = connection.status.rawValue as CKRecordValue
        record["createdAt"] = connection.createdAt as CKRecordValue
        record["updatedAt"] = connection.updatedAt as CKRecordValue

        if let fromUsername = connection.fromUsername {
            record["fromUsername"] = fromUsername as CKRecordValue
        }
        if let fromDisplayName = connection.fromDisplayName {
            record["fromDisplayName"] = fromDisplayName as CKRecordValue
        }
        if let toUsername = connection.toUsername {
            record["toUsername"] = toUsername as CKRecordValue
        }
        if let toDisplayName = connection.toDisplayName {
            record["toDisplayName"] = toDisplayName as CKRecordValue
        }

        // Use modifyRecords with .changedKeys to allow any authenticated user to update
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
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
        let db = try await core.getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>()

        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: fromPredicate)

        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: toPredicate)

        async let fromResultsTask = db.records(matching: fromQuery)
        async let toResultsTask = db.records(matching: toQuery)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

        for (_, result) in fromResults.matchResults {
            if let record = try? result.get() {
                do {
                    let connection = try connectionFromRecord(record)
                    if !connectionIds.contains(connection.id) {
                        connections.append(connection)
                        connectionIds.insert(connection.id)
                    }
                } catch {
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
                    logger.info("⏭️ Skipping legacy connection record (likely rejected/blocked): \(record.recordID.recordName)")
                }
            }
        }

        let cleanedConnections = try await removeDuplicateConnections(connections)
        return cleanedConnections
    }

    /// Check if a connection already exists between two users
    func connectionExists(between userA: UUID, and userB: UUID) async throws -> Bool {
        let db = try await core.getPublicDatabase()

        let predicate1 = NSPredicate(format: "fromUserId == %@ AND toUserId == %@", userA.uuidString, userB.uuidString)
        let query1 = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: predicate1)
        let results1 = try await db.records(matching: query1, resultsLimit: 1)

        if results1.matchResults.contains(where: { (try? $0.1.get()) != nil }) {
            return true
        }

        let predicate2 = NSPredicate(format: "fromUserId == %@ AND toUserId == %@", userB.uuidString, userA.uuidString)
        let query2 = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: predicate2)
        let results2 = try await db.records(matching: query2, resultsLimit: 1)

        return results2.matchResults.contains(where: { (try? $0.1.get()) != nil })
    }

    /// Fetch connections for multiple users (batch fetch)
    func fetchConnections(forUserIds userIds: [UUID]) async throws -> [Connection] {
        guard !userIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()
        var connections: [Connection] = []
        var connectionIds = Set<UUID>()

        let userIdStrings = userIds.map { $0.uuidString }

        let fromPredicate = NSPredicate(format: "fromUserId IN %@", userIdStrings)
        let fromQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: fromPredicate)

        let toPredicate = NSPredicate(format: "toUserId IN %@", userIdStrings)
        let toQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: toPredicate)

        async let fromResultsTask = db.records(matching: fromQuery, resultsLimit: 200)
        async let toResultsTask = db.records(matching: toQuery, resultsLimit: 200)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

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

        return connections
    }

    /// Remove duplicate connections between the same two users
    private func removeDuplicateConnections(_ connections: [Connection]) async throws -> [Connection] {
        var connectionsByPair: [Set<UUID>: [Connection]] = [:]

        for connection in connections {
            let userPair = Set([connection.fromUserId, connection.toUserId])
            connectionsByPair[userPair, default: []].append(connection)
        }

        var connectionsToKeep: [Connection] = []
        let db = try await core.getPublicDatabase()

        for (userPair, pairConnections) in connectionsByPair {
            if pairConnections.count > 1 {
                let sorted = pairConnections.sorted { $0.updatedAt > $1.updatedAt }
                let toKeep = sorted.first!
                let toDelete = Array(sorted.dropFirst())

                logger.warning("🧹 Found \(pairConnections.count) duplicate connections for users \(Array(userPair))")
                logger.info("  Keeping: \(toKeep.id) (status: \(toKeep.status.rawValue), updated: \(toKeep.updatedAt))")

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
                connectionsToKeep.append(pairConnections[0])
            }
        }

        return connectionsToKeep
    }

    /// Delete a connection from CloudKit PUBLIC database
    func deleteConnection(_ connection: Connection) async throws {
        let recordID = CKRecord.ID(recordName: connection.id.uuidString)
        let db = try await core.getPublicDatabase()

        try await db.deleteRecord(withID: recordID)
        logger.info("Deleted connection from PUBLIC database: \(connection.id)")
    }

    /// Delete all connections involving a user from CloudKit PUBLIC database
    func deleteAllConnectionsForUser(userId: UUID) async throws {
        logger.info("🗑️ Deleting all connections for user: \(userId)")
        let db = try await core.getPublicDatabase()

        let fromPredicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)
        let fromQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: fromPredicate)

        let toPredicate = NSPredicate(format: "toUserId == %@", userId.uuidString)
        let toQuery = CKQuery(recordType: CloudKitCore.RecordType.connection, predicate: toPredicate)

        async let fromResultsTask = db.records(matching: fromQuery)
        async let toResultsTask = db.records(matching: toQuery)

        let (fromResults, toResults) = try await (fromResultsTask, toResultsTask)

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

    /// Create an auto-accepted friend connection between two users (from referral)
    func createAutoFriendConnection(referrerId: UUID, newUserId: UUID, referrerDisplayName: String?, newUserDisplayName: String?) async throws {
        guard referrerId != newUserId else {
            logger.warning("Skipping auto-friend connection for self referral: \(referrerId)")
            return
        }

        if try await connectionExists(between: referrerId, and: newUserId) {
            logger.info("Connection already exists between \(referrerId) and \(newUserId); skipping auto-friend connection")
            return
        }

        let db = try await core.getPublicDatabase()

        let connectionId = UUID()
        let recordID = CKRecord.ID(recordName: connectionId.uuidString)
        let record = CKRecord(recordType: CloudKitCore.RecordType.connection, recordID: recordID)

        record["connectionId"] = connectionId.uuidString as CKRecordValue
        record["fromUserId"] = referrerId.uuidString as CKRecordValue
        record["toUserId"] = newUserId.uuidString as CKRecordValue
        record["status"] = ConnectionStatus.accepted.rawValue as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue

        if let referrerName = referrerDisplayName {
            record["fromDisplayName"] = referrerName as CKRecordValue
        }
        if let newUserName = newUserDisplayName {
            record["toDisplayName"] = newUserName as CKRecordValue
        }

        record["isReferral"] = 1 as CKRecordValue

        _ = try await db.save(record)
        logger.info("✅ Created auto-friend connection between referrer \(referrerId) and new user \(newUserId)")
    }

    // MARK: - Push Notifications

    /// Subscribe to connection requests for push notifications
    func subscribeToConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"

        let db = try await core.getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet
        }

        let predicate = NSPredicate(format: "toUserId == %@ AND status == %@", userId.uuidString, "pending")

        let subscription = CKQuerySubscription(
            recordType: CloudKitCore.RecordType.connection,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let notification = CKSubscription.NotificationInfo()
        notification.alertLocalizationKey = "CONNECTION_REQUEST_ALERT"
        notification.alertLocalizationArgs = ["fromDisplayName"]
        notification.alertBody = "You have a new friend request!"
        notification.soundName = "default"
        notification.shouldBadge = true
        notification.shouldSendContentAvailable = true
        notification.desiredKeys = ["connectionId", "fromUserId", "fromUsername", "fromDisplayName"]

        subscription.notificationInfo = notification

        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save connection request subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection request notifications
    func unsubscribeFromConnectionRequests(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-requests-\(userId.uuidString)"
        let db = try await core.getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection requests")
        } catch {
            logger.warning("Failed to unsubscribe: \(error.localizedDescription)")
        }
    }

    /// Subscribe to connection acceptances for push notifications
    func subscribeToConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"

        let db = try await core.getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet
        }

        let predicate = NSPredicate(format: "fromUserId == %@ AND status == %@", userId.uuidString, "accepted")

        let subscription = CKQuerySubscription(
            recordType: CloudKitCore.RecordType.connection,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordUpdate]
        )

        let notification = CKSubscription.NotificationInfo()
        notification.alertBody = "Your friend request was accepted!"
        notification.soundName = "default"
        notification.shouldBadge = false
        notification.shouldSendContentAvailable = true
        notification.desiredKeys = ["connectionId", "fromUserId", "toUserId", "status"]

        subscription.notificationInfo = notification

        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save connection acceptance subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from connection acceptance notifications
    func unsubscribeFromConnectionAcceptances(forUserId userId: UUID) async throws {
        let subscriptionID = "connection-acceptances-\(userId.uuidString)"
        let db = try await core.getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from connection acceptances")
        } catch {
            logger.warning("Failed to unsubscribe from acceptances: \(error.localizedDescription)")
        }
    }

    /// Subscribe to referral signup notifications
    func subscribeToReferralSignups(forUserId userId: UUID) async throws {
        let subscriptionID = "referral-signups-\(userId.uuidString)"

        let db = try await core.getPublicDatabase()
        do {
            try await db.deleteSubscription(withID: subscriptionID)
        } catch {
            // Subscription doesn't exist yet
        }

        let predicate = NSPredicate(format: "fromUserId == %@", userId.uuidString)

        let subscription = CKQuerySubscription(
            recordType: CloudKitCore.RecordType.connection,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation]
        )

        let notification = CKSubscription.NotificationInfo()
        notification.alertBody = "Someone joined Cauldron using your referral code! You're now friends. 🎉"
        notification.soundName = "default"
        notification.shouldBadge = false
        notification.shouldSendContentAvailable = true
        notification.desiredKeys = ["connectionId", "toUserId"]

        subscription.notificationInfo = notification

        do {
            _ = try await db.save(subscription)
        } catch {
            logger.error("Failed to save referral signup subscription: \(error.localizedDescription)")
            throw error
        }
    }

    /// Unsubscribe from referral signup notifications
    func unsubscribeFromReferralSignups(forUserId userId: UUID) async throws {
        let subscriptionID = "referral-signups-\(userId.uuidString)"
        let db = try await core.getPublicDatabase()

        do {
            try await db.deleteSubscription(withID: subscriptionID)
            logger.info("Unsubscribed from referral signups")
        } catch {
            logger.warning("Failed to unsubscribe from referral signups: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

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

        let fromUsername = record["fromUsername"] as? String
        let fromDisplayName = record["fromDisplayName"] as? String
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
