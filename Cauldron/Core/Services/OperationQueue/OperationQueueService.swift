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

nonisolated struct DeadLetteredSyncOperation: Codable, Equatable, Sendable {
    let operationId: String
    let errorDescription: String
    let capturedAt: Date
    let rawJSON: Data?
}

/// Actor responsible for managing pending operations and retry logic
actor OperationQueueService {
    // MARK: - Properties

    private var operations: [UUID: SyncOperation] = [:]
    private var retryTask: Task<Void, Never>?
    private let eventContinuation: AsyncStream<OperationQueueEvent>.Continuation
    let events: AsyncStream<OperationQueueEvent>

    // Persistence
    private let persistenceKey: String
    private let deadLetterPersistenceKey: String

    // MARK: - Initialization

    init() {
        let env = ProcessInfo.processInfo.environment
        let isRunningTests = env["XCTestConfigurationFilePath"] != nil
        let isCI = env["CI"] == "true"
        if isRunningTests || isCI || RuntimeEnvironment.isSimulatorQAMode {
            // Keep queue persistence process-local in tests to avoid leaking operations
            // across test cases and causing nondeterministic retries.
            self.persistenceKey = "com.cauldron.operationQueue.operations.test.\(UUID().uuidString)"
            self.deadLetterPersistenceKey = "\(self.persistenceKey).deadLetters"
        } else {
            self.persistenceKey = "com.cauldron.operationQueue.operations"
            self.deadLetterPersistenceKey = "com.cauldron.operationQueue.operations.deadLetters"
        }

        var continuation: AsyncStream<OperationQueueEvent>.Continuation!
        self.events = AsyncStream<OperationQueueEvent> { cont in
            continuation = cont
        }
        self.eventContinuation = continuation

        if !RuntimeEnvironment.isRunningTests && !RuntimeEnvironment.isSimulatorQAMode {
            // Hydrate synchronously before the actor is published so an immediate
            // mutation can never overwrite durable operations that are still decoding.
            var recoveredDeadLetters: [DeadLetteredSyncOperation] = []
            if let data = UserDefaults.standard.data(forKey: persistenceKey) {
                let decoded = Self.decodePersistedOperations(data)
                self.operations = decoded.operations
                recoveredDeadLetters = decoded.deadLetters
            }
            Task {
                await self.finishStartup(deadLetters: recoveredDeadLetters)
            }
        }
    }

    // MARK: - Public API

    /// Add a new operation to the queue
    @discardableResult
    func addOperation(
        type: SyncOperationType,
        entityType: EntityType,
        entityId: UUID,
        payload: Data? = nil
    ) -> UUID {
        // Check if there's already a pending operation for this entity
        let matchingOperations = operations.values.filter {
            $0.entityId == entityId && $0.entityType == entityType && $0.status != .completed
        }
        // Coalesce into an existing successor when one is waiting. An in-flight
        // operation remains immutable and will be followed by the latest intent.
        if let existingOp = matchingOperations.first(where: { $0.status != .inProgress }) {
            AppLogger.general.info("Updating existing pending operation for \(entityType) \(entityId)")
            let updated = SyncOperation(
                id: UUID(),
                type: type,
                entityType: entityType,
                entityId: entityId,
                payload: payload ?? existingOp.payload,
                status: .pending,
                attempts: 0,
                createdAt: existingOp.createdAt
            )
            operations.removeValue(forKey: existingOp.id)
            operations[updated.id] = updated
            persistOperations()
            eventContinuation.yield(.operationAdded(updated))
            return updated.id
        }

        if let existingOp = matchingOperations.first {
            // An in-flight mutation cannot be cancelled. Preserve it and queue a
            // distinct successor so completion of the old intent cannot erase the
            // newer one. Consumers serialize successors per entity.
            let successor = SyncOperation(
                type: type,
                entityType: entityType,
                entityId: entityId,
                payload: payload
            )
            operations[successor.id] = successor
            persistOperations()
            eventContinuation.yield(.operationAdded(successor))
            AppLogger.general.info("Queued successor after in-progress operation \(existingOp.id)")
            return successor.id
        }

        // Create new operation
        let operation = SyncOperation(
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload
        )

        operations[operation.id] = operation
        persistOperations()
        eventContinuation.yield(.operationAdded(operation))

        AppLogger.general.info("📝 Added operation to queue: \(operation.displayDescription) for entity \(entityId)")
        return operation.id
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

    /// Remove every queued intent for an entity. Destructive account cleanup
    /// uses this instead of single-operation completion because an immutable
    /// in-flight operation may coexist with a pending successor.
    func removeAllOperations(entityId: UUID, entityType: EntityType) {
        let operationIds = operations.values.compactMap { operation in
            operation.entityId == entityId && operation.entityType == entityType
                ? operation.id
                : nil
        }
        guard !operationIds.isEmpty else { return }
        for operationId in operationIds {
            operations.removeValue(forKey: operationId)
            eventContinuation.yield(.operationCompleted(operationId))
        }
        persistOperations()
        if operations.isEmpty {
            eventContinuation.yield(.queueEmpty)
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

    /// Get the first operation for a specific entity/type pair
    func getOperation(for entityId: UUID, entityType: EntityType) -> SyncOperation? {
        operations.values
            .first { $0.entityId == entityId && $0.entityType == entityType }
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
                payload: operation.payload,
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

    /// Retry a specific failed operation by entity
    @discardableResult
    func retryOperation(entityId: UUID, entityType: EntityType) -> SyncOperation? {
        guard let operation = operations.values.first(where: {
            $0.entityId == entityId && $0.entityType == entityType
        }) else {
            return nil
        }

        let updated = SyncOperation(
            id: operation.id,
            type: operation.type,
            entityType: operation.entityType,
            entityId: operation.entityId,
            payload: operation.payload,
            status: .pending,
            attempts: operation.attempts,
            createdAt: operation.createdAt
        )
        operations[operation.id] = updated
        persistOperations()
        eventContinuation.yield(.operationRetrying(updated))
        return updated
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

    func removeAllOperations() {
        operations.removeAll()
        persistOperations()
        eventContinuation.yield(.queueEmpty)
    }

    /// Remove a specific operation (useful for user-initiated cancellation)
    func removeOperation(operationId: UUID) {
        operations.removeValue(forKey: operationId)
        persistOperations()
        AppLogger.general.info("🗑️ Removed operation: \(operationId)")
    }

    // MARK: - Private Methods

    private func finishStartup(deadLetters: [DeadLetteredSyncOperation]) {
        if !deadLetters.isEmpty {
            persistDeadLetteredOperations(deadLetters)
            persistOperations()
            AppLogger.general.warning("Recovered \(operations.count) sync operations and dead-lettered \(deadLetters.count) invalid persisted operations")
        }
        recoverStalledOperations()
        startRetryLoop()
    }

    nonisolated static func decodePersistedOperations(
        _ data: Data,
        capturedAt: Date = Date()
    ) -> (operations: [UUID: SyncOperation], deadLetters: [DeadLetteredSyncOperation]) {
        let decoder = JSONDecoder()

        if let decoded = try? decoder.decode([UUID: SyncOperation].self, from: data) {
            return (decoded, [])
        }

        var recovered: [UUID: SyncOperation] = [:]
        var deadLetters: [DeadLetteredSyncOperation] = []

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let operationObjects = jsonObject as? [String: Any] else {
            return (
                [:],
                [
                    DeadLetteredSyncOperation(
                        operationId: "queue",
                        errorDescription: "Persisted sync queue is not a decodable dictionary",
                        capturedAt: capturedAt,
                        rawJSON: data
                    )
                ]
            )
        }

        for (operationId, operationObject) in operationObjects {
            do {
                let operationData = try JSONSerialization.data(withJSONObject: operationObject)
                let operation = try decoder.decode(SyncOperation.self, from: operationData)
                recovered[operation.id] = operation
            } catch {
                let rawJSON = try? JSONSerialization.data(withJSONObject: operationObject)
                deadLetters.append(
                    DeadLetteredSyncOperation(
                        operationId: operationId,
                        errorDescription: error.localizedDescription,
                        capturedAt: capturedAt,
                        rawJSON: rawJSON
                    )
                )
            }
        }

        return (recovered, deadLetters)
    }

    /// Recover operations that have been stuck in progress too long (e.g., app was killed)
    /// These operations were marked inProgress but never completed - reset them for retry
    private func recoverStalledOperations() {
        let stalledThreshold: TimeInterval = 300 // 5 minutes
        let now = Date()
        var recoveredCount = 0

        for operation in operations.values where operation.status == .inProgress {
            // Check if operation has been in progress too long
            if let lastAttempt = operation.lastAttemptDate,
               now.timeIntervalSince(lastAttempt) > stalledThreshold {
                // Mark as pending for retry
                let recovered = SyncOperation(
                    id: operation.id,
                    type: operation.type,
                    entityType: operation.entityType,
                    entityId: operation.entityId,
                    payload: operation.payload,
                    status: .pending,
                    attempts: operation.attempts,
                    lastAttemptDate: operation.lastAttemptDate,
                    nextRetryDate: nil, // Ready to retry immediately
                    errorMessage: "Recovered from stalled state",
                    createdAt: operation.createdAt
                )
                operations[operation.id] = recovered
                eventContinuation.yield(.operationRetrying(recovered))
                recoveredCount += 1
                AppLogger.general.info("🔄 Recovered stalled operation: \(operation.displayDescription)")
            }
        }

        if recoveredCount > 0 {
            persistOperations()
            AppLogger.general.info("🔄 Recovered \(recoveredCount) stalled operations")
        }
    }

    /// Persist operations to UserDefaults
    private func persistOperations() {
        guard !RuntimeEnvironment.isRunningTests else { return }

        guard let data = try? JSONEncoder().encode(operations) else {
            AppLogger.general.error("Failed to encode operations for persistence")
            return
        }

        UserDefaults.standard.set(data, forKey: persistenceKey)
    }

    private func persistDeadLetteredOperations(_ newDeadLetters: [DeadLetteredSyncOperation]) {
        guard !RuntimeEnvironment.isRunningTests, !newDeadLetters.isEmpty else { return }

        var deadLetters: [DeadLetteredSyncOperation] = []
        if let existingData = UserDefaults.standard.data(forKey: deadLetterPersistenceKey),
           let existing = try? JSONDecoder().decode([DeadLetteredSyncOperation].self, from: existingData) {
            deadLetters = existing
        }

        deadLetters.append(contentsOf: newDeadLetters)

        guard let data = try? JSONEncoder().encode(deadLetters) else {
            AppLogger.general.error("Failed to encode dead-lettered sync operations")
            return
        }

        UserDefaults.standard.set(data, forKey: deadLetterPersistenceKey)
    }

    /// Start the retry loop that processes pending operations
    private func startRetryLoop() {
        guard !RuntimeEnvironment.isRunningTests else { return }

        // Cancel existing task if any
        retryTask?.cancel()

        retryTask = Task {
            while !Task.isCancelled {
                // An operation may become stale after startup, so recovery must
                // run continuously rather than only during initial hydration.
                recoverStalledOperations()

                // Process operations that are ready for retry
                processReadyOperations()

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
                    payload: operation.payload,
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
