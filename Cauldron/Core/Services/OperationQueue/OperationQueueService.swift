//
//  OperationQueueService.swift
//  Cauldron
//
//  Created by Claude on 11/14/25.
//

import Foundation
import os

/// Events emitted by the operation queue
enum OperationQueueEvent {
    case operationAdded(SyncOperation)
    case operationStarted(SyncOperation)
    case operationCompleted(UUID)
    case operationFailed(SyncOperation)
    case operationRetrying(SyncOperation)
    case queueEmpty
}

/// Actor responsible for managing pending operations and retry logic
actor OperationQueueService {
    // MARK: - Properties

    private var operations: [UUID: SyncOperation] = [:]
    private var retryTask: Task<Void, Never>?
    private let eventContinuation: AsyncStream<OperationQueueEvent>.Continuation
    let events: AsyncStream<OperationQueueEvent>

    // Persistence
    private let persistenceKey = "com.cauldron.operationQueue.operations"

    // MARK: - Initialization

    init() {
        var continuation: AsyncStream<OperationQueueEvent>.Continuation!
        self.events = AsyncStream<OperationQueueEvent> { cont in
            continuation = cont
        }
        self.eventContinuation = continuation

        // Load persisted operations
        Task {
            await self.loadPersistedOperations()
            await self.startRetryLoop()
        }
    }

    // MARK: - Public API

    /// Add a new operation to the queue
    func addOperation(
        type: SyncOperationType,
        entityType: EntityType,
        entityId: UUID
    ) {
        // Check if there's already a pending operation for this entity
        if let existingOp = operations.values.first(where: {
            $0.entityId == entityId && $0.entityType == entityType && $0.status != .completed
        }) {
            // If there's already a pending operation, update it instead of adding a new one
            AppLogger.general.info("Updating existing pending operation for \(entityType) \(entityId)")

            // For updates, just reset the type to update
            let updated = SyncOperation(
                id: existingOp.id,
                type: type,
                entityType: entityType,
                entityId: entityId,
                status: .pending,
                attempts: 0,
                createdAt: existingOp.createdAt
            )
            operations[updated.id] = updated
            persistOperations()
            eventContinuation.yield(.operationAdded(updated))
            return
        }

        // Create new operation
        let operation = SyncOperation(
            type: type,
            entityType: entityType,
            entityId: entityId
        )

        operations[operation.id] = operation
        persistOperations()
        eventContinuation.yield(.operationAdded(operation))

        AppLogger.general.info("📝 Added operation to queue: \(operation.displayDescription) for entity \(entityId)")
    }

    /// Mark an operation as in progress
    func markInProgress(operationId: UUID) {
        guard let operation = operations[operationId] else { return }
        let updated = operation.markInProgress()
        operations[operationId] = updated
        persistOperations()
        eventContinuation.yield(.operationStarted(updated))
    }

    /// Mark an operation as completed
    func markCompleted(operationId: UUID) {
        guard let operation = operations[operationId] else { return }
        operations.removeValue(forKey: operationId)
        persistOperations()
        eventContinuation.yield(.operationCompleted(operationId))

        AppLogger.general.info("✅ Completed operation: \(operation.displayDescription)")

        if operations.isEmpty {
            eventContinuation.yield(.queueEmpty)
        }
    }

    /// Mark an operation as completed by entity ID
    func markCompleted(entityId: UUID, entityType: EntityType) {
        if let operation = operations.values.first(where: {
            $0.entityId == entityId && $0.entityType == entityType
        }) {
            markCompleted(operationId: operation.id)
        }
    }

    /// Mark an operation as failed and schedule for retry
    func markFailed(operationId: UUID, error: String) {
        guard let operation = operations[operationId] else { return }
        let updated = operation.withRetry(error: error)
        operations[operationId] = updated
        persistOperations()
        eventContinuation.yield(.operationFailed(updated))

        AppLogger.general.warning("⚠️ Operation failed (attempt \(updated.attempts)): \(operation.displayDescription) - \(error)")
    }

    /// Get all pending operations
    func getAllOperations() -> [SyncOperation] {
        Array(operations.values).sorted { $0.createdAt < $1.createdAt }
    }

    /// Get operations for a specific entity
    func getOperations(for entityId: UUID) -> [SyncOperation] {
        operations.values.filter { $0.entityId == entityId }
    }

    /// Check if an entity has pending operations
    func hasPendingOperation(for entityId: UUID) -> Bool {
        operations.values.contains { $0.entityId == entityId && $0.status != .completed }
    }

    /// Get the status of an entity's sync
    func getStatus(for entityId: UUID) -> OperationStatus? {
        operations.values
            .first { $0.entityId == entityId }?
            .status
    }

    /// Get count of pending operations by type
    func getPendingCount(for entityType: EntityType) -> Int {
        operations.values.filter { $0.entityType == entityType && $0.status != .completed }.count
    }

    /// Get total count of pending operations
    func getTotalPendingCount() -> Int {
        operations.values.filter { $0.status != .completed }.count
    }

    /// Manually retry all failed operations
    func retryFailedOperations() {
        for operation in operations.values where operation.status == .failed {
            let updated = SyncOperation(
                id: operation.id,
                type: operation.type,
                entityType: operation.entityType,
                entityId: operation.entityId,
                status: .pending,
                attempts: operation.attempts,
                createdAt: operation.createdAt
            )
            operations[operation.id] = updated
            eventContinuation.yield(.operationRetrying(updated))
        }
        persistOperations()
        AppLogger.general.info("🔄 Manually retrying all failed operations")
    }

    /// Clear all completed operations
    func clearCompletedOperations() {
        let completedIds = operations.values
            .filter { $0.status == .completed }
            .map { $0.id }

        for id in completedIds {
            operations.removeValue(forKey: id)
        }
        persistOperations()
    }

    /// Remove a specific operation (useful for user-initiated cancellation)
    func removeOperation(operationId: UUID) {
        operations.removeValue(forKey: operationId)
        persistOperations()
        AppLogger.general.info("🗑️ Removed operation: \(operationId)")
    }

    // MARK: - Private Methods

    /// Load operations from UserDefaults
    private func loadPersistedOperations() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let loaded = try? JSONDecoder().decode([UUID: SyncOperation].self, from: data) else {
            AppLogger.general.info("No persisted operations found")
            return
        }

        operations = loaded
        AppLogger.general.info("📂 Loaded \(operations.count) persisted operations")
    }

    /// Persist operations to UserDefaults
    private func persistOperations() {
        guard let data = try? JSONEncoder().encode(operations) else {
            AppLogger.general.error("Failed to encode operations for persistence")
            return
        }

        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    /// Start the retry loop that processes pending operations
    private func startRetryLoop() {
        // Cancel existing task if any
        retryTask?.cancel()

        retryTask = Task {
            while !Task.isCancelled {
                // Process operations that are ready for retry
                await processReadyOperations()

                // Wait 30 seconds before next check
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Process operations that are ready to be retried
    private func processReadyOperations() {
        let readyOps = operations.values.filter { operation in
            operation.status == .pending || operation.isReadyForRetry
        }

        for operation in readyOps {
            // Mark as pending so it can be picked up by repositories
            if operation.status != .pending {
                let updated = SyncOperation(
                    id: operation.id,
                    type: operation.type,
                    entityType: operation.entityType,
                    entityId: operation.entityId,
                    status: .pending,
                    attempts: operation.attempts,
                    createdAt: operation.createdAt
                )
                operations[operation.id] = updated
                eventContinuation.yield(.operationRetrying(updated))
                AppLogger.general.info("🔄 Retrying operation: \(operation.displayDescription)")
            }
        }

        if !readyOps.isEmpty {
            persistOperations()
        }
    }

    /// Stop the retry loop
    func stop() {
        retryTask?.cancel()
        retryTask = nil
    }

    deinit {
        eventContinuation.finish()
        retryTask?.cancel()
    }
}
