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
struct ManagedConnection: Equatable, Identifiable {
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
    case alreadySentRequest
    case alreadyConnected

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
        case .alreadySentRequest:
            return "You already sent a friend request to this person"
        case .alreadyConnected:
            return "You're already friends with this person"
        }
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

    private var queueEventTask: Task<Void, Never>?

    private let maxRetries = 5
    private let pendingRejectsKey = "pendingRejectedConnectionIds"
    private var pendingRejectIds: Set<UUID> = []

    // Cache management
    private var lastSyncTime: Date?
    private let cacheValidityDuration: TimeInterval = 1800 // 30 minutes

    // Fallback UUID for when CurrentUserSession has no user (e.g., in tests)
    private lazy var fallbackUserId: UUID = UUID()

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? fallbackUserId
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        self.pendingRejectIds = loadPendingRejectIds()
        startQueueEventListener()

        Task {
            await processPendingConnectionOperations()
        }
    }

    // MARK: - Public API

    /// Load connections from local cache and CloudKit
    /// - Parameters:
    ///   - userId: The user ID to load connections for
    ///   - forceRefresh: If true, bypasses cache and forces a CloudKit sync
    func loadConnections(forUserId userId: UUID, forceRefresh: Bool = false) async {
        // Check if cache is still valid (don't log routine cache hits)
        if !forceRefresh, let lastSync = lastSyncTime {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < cacheValidityDuration {
                // Only load from cache if we don't have any connections yet
                if connections.isEmpty {
                    await loadFromCache(userId: userId)
                }
                return
            }
        }

        // First, load from local cache for instant display
        await loadFromCache(userId: userId)

        // Then fetch from CloudKit in background
        await syncFromCloudKit(userId: userId)

        // Update last sync time
        lastSyncTime = Date()
    }

    /// Accept a connection request (optimistic update)
    func acceptConnection(_ connection: Connection) async throws {
        guard connection.toUserId == currentUserId else {
            throw ConnectionError.permissionDenied
        }

        // Idempotency guard: ignore duplicate accepts while already accepted/syncing.
        if let existing = connections[connection.id], existing.connection.status == .accepted {
            return
        }

        if let queued = await queuedConnectionOperation(for: connection.id), queued.type == .acceptConnection {
            return
        }

        // Get current user's info for the acceptor fields
        let currentUser = CurrentUserSession.shared.currentUser

        // Create accepted connection (preserve sender info, add acceptor info)
        let acceptedConnection = Connection(
            id: connection.id,
            fromUserId: connection.fromUserId,
            toUserId: connection.toUserId,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date(),
            fromUsername: connection.fromUsername,
            fromDisplayName: connection.fromDisplayName,
            toUsername: currentUser?.username,
            toDisplayName: currentUser?.displayName ?? currentUser?.username
        )

        // Update local state immediately (optimistic)
        connections[connection.id] = ManagedConnection(
            connection: acceptedConnection,
            syncState: .syncing
        )

        // Save to local cache immediately
        try? await dependencies.connectionRepository.save(acceptedConnection)

        // Queue CloudKit sync via shared queue service
        await enqueueConnectionOperation(type: .acceptConnection, connection: acceptedConnection)

        // Update badge count (one less pending request)
        updateBadgeCount()
    }

    /// Reject a connection request (optimistic delete)
    func rejectConnection(_ connection: Connection) async throws {
        guard connection.toUserId == currentUserId else {
            throw ConnectionError.permissionDenied
        }

        // Remove from local state immediately (optimistic) - rejection = deletion
        connections.removeValue(forKey: connection.id)

        // Delete from local cache immediately
        try? await dependencies.connectionRepository.delete(connection)

        // Track pending reject to avoid re-adding from CloudKit during sync
        pendingRejectIds.insert(connection.id)
        persistPendingRejectIds()

        // Queue CloudKit delete in background (rejection = deletion for cleaner UX)
        await enqueueConnectionOperation(type: .rejectConnection, connection: connection)

        // Update badge count (one less pending request)
        updateBadgeCount()
    }

    /// Send a connection request (optimistic update)
    func sendConnectionRequest(to userId: UUID, user: User) async throws {
        // Check if there's an existing connection (including rejected ones)
        if let existingConnection = connectionStatus(with: userId) {
            let conn = existingConnection.connection

            if conn.status == .accepted {
                // Already friends
                throw ConnectionError.alreadyConnected
            }

            if conn.status == .pending {
                // Check if this is an incoming request we can accept
                if conn.toUserId == currentUserId {
                    // They sent us a request - just accept it!
                    logger.info("Auto-accepting incoming request from \(userId)")
                    try await acceptConnection(conn)
                    return
                } else {
                    // We already sent them a request
                    throw ConnectionError.alreadySentRequest
                }
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

        // Queue CloudKit sync via shared queue service
        await enqueueConnectionOperation(type: .create, connection: connection)
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
        syncErrors.removeValue(forKey: connectionId)

        if let _ = await dependencies.operationQueueService.retryOperation(entityId: connectionId, entityType: .connection) {
            if let managedConnection = connections[connectionId] {
                connections[connectionId] = ManagedConnection(
                    connection: managedConnection.connection,
                    syncState: .syncing
                )
            }
            await processQueuedConnectionOperation(connectionId: connectionId)
            return
        }

        // If queue operation was already removed after max retries, recreate from local connection state.
        guard let managedConnection = connections[connectionId] else {
            logger.warning("No connection found for manual retry: \(connectionId)")
            return
        }

        let operationType: SyncOperationType = managedConnection.connection.status == .accepted
            ? .acceptConnection
            : .create

        await enqueueConnectionOperation(type: operationType, connection: managedConnection.connection)
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
        // Remove from local state immediately (optimistic)
        connections.removeValue(forKey: connection.id)

        // Delete from local cache
        do {
            try await dependencies.connectionRepository.delete(connection)
        } catch {
            logger.warning("Failed to delete from cache: \(error.localizedDescription)")
        }

        // Delete from CloudKit
        do {
            try await dependencies.connectionCloudService.deleteConnection(connection)
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
                if pendingRejectIds.contains(connection.id) {
                    // Clean up any cached entries for pending rejects
                    try? await dependencies.connectionRepository.delete(connection)
                    continue
                }

                let syncState = await syncStateForConnection(connection.id)
                connections[connection.id] = ManagedConnection(
                    connection: connection,
                    syncState: syncState
                )
            }
        } catch {
            logger.error("Failed to load from cache: \(error.localizedDescription)")
        }
    }

    private func loadPendingRejectIds() -> Set<UUID> {
        let stored = UserDefaults.standard.stringArray(forKey: pendingRejectsKey) ?? []
        return Set(stored.compactMap { UUID(uuidString: $0) })
    }

    private func persistPendingRejectIds() {
        let stored = pendingRejectIds.map { $0.uuidString }
        UserDefaults.standard.set(stored, forKey: pendingRejectsKey)
    }

    /// Sync connections from CloudKit
    private func syncFromCloudKit(userId: UUID) async {
        do {
            let cloudConnections = try await dependencies.connectionCloudService.fetchConnections(forUserId: userId)

            // Track cloud connection IDs
            let cloudConnectionIds = Set(cloudConnections.map { $0.id })

            // Clear pending rejects that are no longer in CloudKit
            if !pendingRejectIds.isEmpty {
                let resolvedRejects = pendingRejectIds.subtracting(cloudConnectionIds)
                if !resolvedRejects.isEmpty {
                    pendingRejectIds.subtract(resolvedRejects)
                    persistPendingRejectIds()
                }
            }

            // Filter out pending rejects to prevent reappearing requests
            let filteredConnections = cloudConnections.filter { !pendingRejectIds.contains($0.id) }
            let filteredConnectionIds = Set(filteredConnections.map { $0.id })

            // Update local cache and state with cloud connections
            for connection in filteredConnections {
                try? await dependencies.connectionRepository.save(connection)

                // Don't override optimistic local states while an operation is queued.
                if !(await hasQueuedConnectionOperation(for: connection.id)) {
                    connections[connection.id] = ManagedConnection(
                        connection: connection,
                        syncState: .synced
                    )
                }
            }

            // Remove connections that exist locally but not in CloudKit (they were deleted)
            let localConnectionIds = Set(connections.keys)
            let deletedConnectionIds = localConnectionIds.subtracting(filteredConnectionIds)

            for deletedId in deletedConnectionIds {
                // Skip if operation is currently queued for this connection
                if await hasQueuedConnectionOperation(for: deletedId) {
                    continue
                }

                // Remove from in-memory state
                if let connection = connections[deletedId]?.connection {
                    connections.removeValue(forKey: deletedId)

                    // Remove from local cache
                    try? await dependencies.connectionRepository.delete(connection)
                }
            }

            // Update badge count after syncing
            updateBadgeCount()
        } catch {
            logger.error("Failed to sync from CloudKit: \(error.localizedDescription)")
        }
    }

    private func startQueueEventListener() {
        let queueService = dependencies.operationQueueService
        queueEventTask = Task { @MainActor [weak self, queueService] in
            for await event in queueService.events {
                await self?.handleQueueEvent(event)
            }
        }
    }

    private func handleQueueEvent(_ event: OperationQueueEvent) async {
        switch event {
        case .operationAdded(let operation), .operationRetrying(let operation):
            guard operation.entityType == .connection else { return }
            await processQueuedConnectionOperation(connectionId: operation.entityId)

        case .operationStarted(let operation):
            guard operation.entityType == .connection else { return }
            if let managed = connections[operation.entityId] {
                connections[operation.entityId] = ManagedConnection(
                    connection: managed.connection,
                    syncState: .syncing
                )
            }

        case .operationFailed(let operation):
            guard operation.entityType == .connection else { return }
            if let managed = connections[operation.entityId] {
                connections[operation.entityId] = ManagedConnection(
                    connection: managed.connection,
                    syncState: .pendingSync(retryCount: operation.attempts)
                )
            }

        case .operationCompleted, .queueEmpty:
            break
        }
    }

    private func processPendingConnectionOperations() async {
        let operations = await dependencies.operationQueueService.getAllOperations()
            .filter { operation in
                operation.entityType == .connection &&
                (operation.status == .pending || operation.isReadyForRetry)
            }

        for operation in operations {
            await processQueuedConnectionOperation(connectionId: operation.entityId)
        }
    }

    private func enqueueConnectionOperation(type: SyncOperationType, connection: Connection) async {
        let payload = try? JSONEncoder().encode(connection)

        await dependencies.operationQueueService.addOperation(
            type: type,
            entityType: .connection,
            entityId: connection.id,
            payload: payload
        )

        syncErrors.removeValue(forKey: connection.id)
        await processQueuedConnectionOperation(connectionId: connection.id)
    }

    private func queuedConnectionOperation(for connectionId: UUID) async -> SyncOperation? {
        let operations = await dependencies.operationQueueService.getOperations(for: connectionId)
            .filter { $0.entityType == .connection }
            .sorted { $0.createdAt > $1.createdAt }

        return operations.first
    }

    private func hasQueuedConnectionOperation(for connectionId: UUID) async -> Bool {
        guard let operation = await queuedConnectionOperation(for: connectionId) else {
            return false
        }

        return operation.status != .completed
    }

    private func syncStateForConnection(_ connectionId: UUID) async -> ConnectionSyncState {
        guard let operation = await queuedConnectionOperation(for: connectionId) else {
            return .synced
        }

        switch operation.status {
        case .inProgress:
            return .syncing
        case .pending, .failed:
            return .pendingSync(retryCount: operation.attempts)
        case .completed:
            return .synced
        }
    }

    private func processQueuedConnectionOperation(connectionId: UUID) async {
        guard let operation = await queuedConnectionOperation(for: connectionId) else {
            return
        }

        guard operation.status == .pending else {
            return
        }

        if let managed = connections[connectionId] {
            connections[connectionId] = ManagedConnection(
                connection: managed.connection,
                syncState: .syncing
            )
        }

        await dependencies.operationQueueService.markInProgress(operationId: operation.id)

        guard let connection = await connectionFromOperation(operation) else {
            await dependencies.operationQueueService.markFailed(
                operationId: operation.id,
                error: "Missing connection payload for queued operation"
            )
            return
        }

        do {
            switch operation.type {
            case .create:
                try await dependencies.connectionCloudService.saveConnection(connection)

            case .acceptConnection, .update:
                try await dependencies.connectionCloudService.acceptConnectionRequest(connection)

            case .rejectConnection, .delete:
                try await dependencies.connectionCloudService.rejectConnectionRequest(connection)
                pendingRejectIds.remove(connection.id)
                persistPendingRejectIds()
            }

            syncErrors.removeValue(forKey: connection.id)
            await dependencies.operationQueueService.markCompleted(entityId: connection.id, entityType: .connection)

            if let managed = connections[connection.id] {
                connections[connection.id] = ManagedConnection(
                    connection: managed.connection,
                    syncState: .synced
                )
            }
        } catch {
            let nextAttempt = operation.attempts + 1

            if nextAttempt >= maxRetries {
                await dependencies.operationQueueService.removeOperation(operationId: operation.id)
                syncErrors[connection.id] = .maxRetriesExceeded

                if let managed = connections[connection.id] {
                    connections[connection.id] = ManagedConnection(
                        connection: managed.connection,
                        syncState: .syncFailed(error)
                    )
                }

                logger.error("❌ Max retries exceeded for connection: \(connection.id)")
            } else {
                await dependencies.operationQueueService.markFailed(
                    operationId: operation.id,
                    error: error.localizedDescription
                )

                if let managed = connections[connection.id] {
                    connections[connection.id] = ManagedConnection(
                        connection: managed.connection,
                        syncState: .pendingSync(retryCount: nextAttempt)
                    )
                }
            }
        }
    }

    private func connectionFromOperation(_ operation: SyncOperation) async -> Connection? {
        if let payload = operation.payload,
           let connection = try? JSONDecoder().decode(Connection.self, from: payload) {
            return connection
        }

        return try? await dependencies.connectionRepository.fetch(id: operation.entityId)
    }

    // MARK: - Badge Management

    /// Get the count of pending friend requests for the current user
    var pendingRequestsCount: Int {
        connections.values.filter { managedConn in
            managedConn.connection.toUserId == currentUserId &&
            managedConn.connection.status == .pending
        }.count
    }

    /// Update app icon badge count based on pending connection requests
    func updateBadgeCount() {
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
        Task {
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                logger.error("Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }

    deinit {
        queueEventTask?.cancel()
    }
}
