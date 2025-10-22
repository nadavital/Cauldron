//
//  ConnectionManager.swift
//  Cauldron
//
//  Enterprise-grade connection management with optimistic UI updates,
//  automatic retry logic, and graceful error handling.
//

import Foundation
import Combine
import os
import UserNotifications

/// Represents the sync state of a connection operation
enum ConnectionSyncState: Equatable {
    case synced                          // Fully synced with CloudKit
    case syncing                         // Currently syncing to CloudKit
    case pendingSync(retryCount: Int)    // Queued for sync (offline or failed)
    case syncFailed(Error)               // Permanent failure after retries

    static func == (lhs: ConnectionSyncState, rhs: ConnectionSyncState) -> Bool {
        switch (lhs, rhs) {
        case (.synced, .synced), (.syncing, .syncing):
            return true
        case (.pendingSync(let a), .pendingSync(let b)):
            return a == b
        case (.syncFailed, .syncFailed):
            return true
        default:
            return false
        }
    }
}

/// Enhanced connection model with sync state
struct ManagedConnection: Equatable {
    let connection: Connection
    let syncState: ConnectionSyncState

    var id: UUID { connection.id }
    var status: ConnectionStatus { connection.status }
    var isAccepted: Bool { connection.isAccepted }
}

/// Errors that can occur during connection operations
enum ConnectionError: LocalizedError {
    case notFound
    case networkFailure(Error)
    case permissionDenied
    case maxRetriesExceeded
    case invalidState

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Connection request not found"
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .maxRetriesExceeded:
            return "Failed to sync after multiple attempts. Please try again."
        case .invalidState:
            return "Connection is in an invalid state"
        }
    }
}

/// Operation types for the sync queue
private enum OperationType {
    case accept(Connection)
    case create(Connection)
}

/// Represents a pending sync operation
private struct PendingOperation {
    let id: UUID
    let type: OperationType
    var retryCount: Int = 0
    var nextRetryAt: Date?

    var connection: Connection {
        switch type {
        case .accept(let conn), .create(let conn):
            return conn
        }
    }

    func withIncrementedRetry() -> PendingOperation {
        var updated = self
        updated.retryCount += 1
        // Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped)
        let delay = min(Double(1 << retryCount), 30.0)
        updated.nextRetryAt = Date().addingTimeInterval(delay)
        return updated
    }
}

/// Centralized service for managing connection state with optimistic updates and sync
@MainActor
class ConnectionManager: ObservableObject {
    // Published state for UI observation
    @Published private(set) var connections: [UUID: ManagedConnection] = [:]
    @Published private(set) var syncErrors: [UUID: ConnectionError] = [:]

    private let dependencies: DependencyContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "ConnectionManager")

    // Sync queue for background CloudKit operations
    private var pendingOperations: [UUID: PendingOperation] = [:]
    private var retryTimer: Timer?

    private let maxRetries = 5

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        startRetryTimer()
    }

    // MARK: - Public API

    /// Load connections from local cache and CloudKit
    func loadConnections(forUserId userId: UUID) async {
        logger.info("📥 Loading connections for user: \(userId)")

        // First, load from local cache for instant display
        await loadFromCache(userId: userId)

        // Then fetch from CloudKit in background
        await syncFromCloudKit(userId: userId)
    }

    /// Accept a connection request (optimistic update)
    func acceptConnection(_ connection: Connection) async throws {
        logger.info("✅ Accepting connection: \(connection.id)")

        guard connection.toUserId == currentUserId else {
            throw ConnectionError.permissionDenied
        }

        // Create accepted connection (preserve sender info)
        let acceptedConnection = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date(),
            fromUsername: connection.fromUsername,
            fromDisplayName: connection.fromDisplayName
        )

        // Update local state immediately (optimistic)
        connections[connection.id] = ManagedConnection(
            connection: acceptedConnection,
            syncState: .syncing
        )

        // Save to local cache immediately
        try? await dependencies.connectionRepository.save(acceptedConnection)

        // Queue CloudKit sync in background
        await queueOperation(.accept(acceptedConnection))

        // Update badge count (one less pending request)
        updateBadgeCount()
    }

    /// Reject a connection request (optimistic delete)
    func rejectConnection(_ connection: Connection) async throws {
        logger.info("❌ Rejecting connection: \(connection.id)")

        guard connection.toUserId == currentUserId else {
            throw ConnectionError.permissionDenied
        }

        // Remove from local state immediately (optimistic) - rejection = deletion
        connections.removeValue(forKey: connection.id)

        // Delete from local cache immediately
        try? await dependencies.connectionRepository.delete(connection)

        // Delete from CloudKit (rejection = deletion for cleaner UX)
        do {
            try await dependencies.cloudKitService.rejectConnectionRequest(connection)
            logger.info("✅ Connection rejected and deleted successfully")

            // Update badge count (one less pending request)
            updateBadgeCount()
        } catch {
            logger.error("❌ Failed to reject connection in CloudKit: \(error.localizedDescription)")
            throw error
        }
    }

    /// Send a connection request (optimistic update)
    func sendConnectionRequest(to userId: UUID, user: User) async throws {
        logger.info("📤 Sending connection request to: \(user.username)")

        // Check if there's an existing connection (including rejected ones)
        if let existingConnection = connectionStatus(with: userId) {
            logger.info("Found existing connection with status: \(existingConnection.connection.status.rawValue)")

            // If rejected, delete it first to allow re-requesting
            if existingConnection.connection.status == .rejected {
                logger.info("🗑️ Deleting rejected connection to allow re-request")
                connections.removeValue(forKey: existingConnection.id)
                try? await dependencies.connectionRepository.delete(existingConnection.connection)
                try? await dependencies.cloudKitService.deleteConnection(existingConnection.connection)
            } else if existingConnection.connection.status == .pending || existingConnection.connection.status == .accepted {
                logger.warning("Connection already exists with status: \(existingConnection.connection.status.rawValue)")
                throw ConnectionError.invalidState
            }
        }

        // Get current user's info for the connection request
        let currentUser = CurrentUserSession.shared.currentUser

        // Create pending connection with sender info
        let connection = Connection(
            fromUserId: currentUserId,
            toUserId: userId,
            status: .pending,
            fromUsername: currentUser?.username,
            fromDisplayName: currentUser?.displayName
        )

        // Update local state immediately (optimistic)
        connections[connection.id] = ManagedConnection(
            connection: connection,
            syncState: .syncing
        )

        // Cache the user (so they can see the request on their device)
        try? await dependencies.sharingRepository.save(user)

        // Save to local cache immediately
        try? await dependencies.connectionRepository.save(connection)

        // Queue CloudKit sync in background
        await queueOperation(.create(connection))
    }

    /// Get connection status with a specific user
    func connectionStatus(with userId: UUID) -> ManagedConnection? {
        connections.values.first { conn in
            (conn.connection.fromUserId == currentUserId && conn.connection.toUserId == userId) ||
            (conn.connection.fromUserId == userId && conn.connection.toUserId == currentUserId)
        }
    }

    /// Manually retry a failed operation
    func retryFailedOperation(connectionId: UUID) async {
        guard let operation = pendingOperations[connectionId] else {
            logger.warning("No pending operation found for connection: \(connectionId)")
            return
        }

        logger.info("🔄 Manually retrying operation for connection: \(connectionId)")

        // Reset retry count for manual retry
        var resetOperation = operation
        resetOperation.retryCount = 0
        resetOperation.nextRetryAt = Date()
        pendingOperations[connectionId] = resetOperation

        // Clear error state
        syncErrors.removeValue(forKey: connectionId)

        // Update sync state to syncing
        if var managedConn = connections[connectionId] {
            managedConn = ManagedConnection(
                connection: managedConn.connection,
                syncState: .syncing
            )
            connections[connectionId] = managedConn
        }

        // Process immediately
        await processOperation(operation)
    }

    /// Get all connections (filtered by status if needed)
    func getConnections(status: ConnectionStatus? = nil, excluding: ConnectionStatus? = nil) -> [ManagedConnection] {
        var filtered = Array(connections.values)

        if let status = status {
            filtered = filtered.filter { $0.connection.status == status }
        }

        if let excluding = excluding {
            filtered = filtered.filter { $0.connection.status != excluding }
        }

        return filtered.sorted { $0.connection.createdAt > $1.connection.createdAt }
    }

    /// Delete a connection (removes friend/unfriends)
    func deleteConnection(_ connection: Connection) async throws {
        logger.info("🗑️ Deleting connection: \(connection.id) between \(connection.fromUserId) and \(connection.toUserId)")

        // Remove from local state immediately (optimistic)
        connections.removeValue(forKey: connection.id)

        // Delete from local cache
        do {
            try await dependencies.connectionRepository.delete(connection)
            logger.info("Deleted connection from local cache")
        } catch {
            logger.warning("Failed to delete from cache: \(error.localizedDescription)")
        }

        // Delete from CloudKit
        do {
            try await dependencies.cloudKitService.deleteConnection(connection)
            logger.info("✅ Connection deleted successfully from CloudKit")
        } catch {
            logger.error("❌ Failed to delete connection from CloudKit: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Private Methods

    /// Load connections from local cache
    private func loadFromCache(userId: UUID) async {
        do {
            let cachedConnections = try await dependencies.connectionRepository.fetchConnections(forUserId: userId)

            for connection in cachedConnections {
                // Check if we have a pending operation for this connection
                let syncState: ConnectionSyncState
                if pendingOperations[connection.id] != nil {
                    syncState = .pendingSync(retryCount: 0)
                } else {
                    syncState = .synced
                }

                connections[connection.id] = ManagedConnection(
                    connection: connection,
                    syncState: syncState
                )
            }

            logger.info("Loaded \(cachedConnections.count) connections from cache")
        } catch {
            logger.error("Failed to load from cache: \(error.localizedDescription)")
        }
    }

    /// Sync connections from CloudKit
    private func syncFromCloudKit(userId: UUID) async {
        do {
            let cloudConnections = try await dependencies.cloudKitService.fetchConnections(forUserId: userId)

            // Track cloud connection IDs
            let cloudConnectionIds = Set(cloudConnections.map { $0.id })

            // Update local cache and state with cloud connections
            for connection in cloudConnections {
                try? await dependencies.connectionRepository.save(connection)

                // Only update if not currently syncing
                if connections[connection.id]?.syncState != .syncing {
                    connections[connection.id] = ManagedConnection(
                        connection: connection,
                        syncState: .synced
                    )
                }
            }

            // Remove connections that exist locally but not in CloudKit (they were deleted)
            let localConnectionIds = Set(connections.keys)
            let deletedConnectionIds = localConnectionIds.subtracting(cloudConnectionIds)

            for deletedId in deletedConnectionIds {
                // Skip if it's currently syncing (pending operation)
                if connections[deletedId]?.syncState == .syncing {
                    continue
                }

                logger.info("🗑️ Removing locally cached connection deleted in CloudKit: \(deletedId)")

                // Remove from in-memory state
                if let connection = connections[deletedId]?.connection {
                    connections.removeValue(forKey: deletedId)

                    // Remove from local cache
                    try? await dependencies.connectionRepository.delete(connection)
                }
            }

            logger.info("Synced \(cloudConnections.count) connections from CloudKit (removed \(deletedConnectionIds.count) deleted)")

            // Update badge count after syncing
            updateBadgeCount()
        } catch {
            logger.error("Failed to sync from CloudKit: \(error.localizedDescription)")
        }
    }

    /// Queue an operation for background sync
    private func queueOperation(_ type: OperationType) async {
        let operation: PendingOperation

        switch type {
        case .accept(let conn), .create(let conn):
            operation = PendingOperation(
                id: conn.id,
                type: type,
                retryCount: 0,
                nextRetryAt: Date()
            )
        }

        pendingOperations[operation.id] = operation

        // Try to process immediately
        await processOperation(operation)
    }

    /// Process a pending operation
    private func processOperation(_ operation: PendingOperation) async {
        logger.info("🔄 Processing operation for connection: \(operation.id)")

        // Update sync state to syncing
        if var managedConn = connections[operation.id] {
            managedConn = ManagedConnection(
                connection: managedConn.connection,
                syncState: .syncing
            )
            connections[operation.id] = managedConn
        }

        do {
            // Perform CloudKit operation
            switch operation.type {
            case .accept(let connection):
                try await dependencies.cloudKitService.acceptConnectionRequest(connection)

            case .create(let connection):
                try await dependencies.cloudKitService.saveConnection(connection)
            }

            // Success! Remove from queue and mark as synced
            pendingOperations.removeValue(forKey: operation.id)
            syncErrors.removeValue(forKey: operation.id)

            if var managedConn = connections[operation.id] {
                managedConn = ManagedConnection(
                    connection: managedConn.connection,
                    syncState: .synced
                )
                connections[operation.id] = managedConn
            }

            logger.info("✅ Successfully synced connection: \(operation.id)")

        } catch {
            logger.error("❌ Failed to sync connection: \(error.localizedDescription)")

            // Check if we should retry
            if operation.retryCount < maxRetries {
                // Queue for retry with exponential backoff
                let updatedOperation = operation.withIncrementedRetry()
                pendingOperations[operation.id] = updatedOperation

                if var managedConn = connections[operation.id] {
                    managedConn = ManagedConnection(
                        connection: managedConn.connection,
                        syncState: .pendingSync(retryCount: operation.retryCount + 1)
                    )
                    connections[operation.id] = managedConn
                }

                logger.info("⏳ Scheduled retry \(operation.retryCount + 1)/\(self.maxRetries) for connection: \(operation.id)")
            } else {
                // Max retries exceeded, mark as failed
                pendingOperations.removeValue(forKey: operation.id)
                syncErrors[operation.id] = .maxRetriesExceeded

                if var managedConn = connections[operation.id] {
                    managedConn = ManagedConnection(
                        connection: managedConn.connection,
                        syncState: .syncFailed(error)
                    )
                    connections[operation.id] = managedConn
                }

                logger.error("❌ Max retries exceeded for connection: \(operation.id)")
            }
        }
    }

    /// Start background timer to process pending operations
    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processRetries()
            }
        }
    }

    /// Process operations that are ready for retry
    private func processRetries() async {
        let now = Date()

        for (id, operation) in pendingOperations {
            if let nextRetry = operation.nextRetryAt, nextRetry <= now {
                await processOperation(operation)
            }
        }
    }

    // MARK: - Badge Management

    /// Update app icon badge count based on pending connection requests
    func updateBadgeCount() {
        let pendingRequestsCount = connections.values.filter { managedConn in
            managedConn.connection.toUserId == currentUserId &&
            managedConn.connection.status == .pending
        }.count

        logger.info("📛 Updating badge count to: \(pendingRequestsCount)")

        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(pendingRequestsCount)
            } catch {
                logger.error("Failed to update badge count: \(error.localizedDescription)")
            }
        }
    }

    /// Clear app icon badge (call when user views connection requests)
    func clearBadge() {
        logger.info("📛 Clearing badge")

        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                logger.error("Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        retryTimer?.invalidate()
    }
}
