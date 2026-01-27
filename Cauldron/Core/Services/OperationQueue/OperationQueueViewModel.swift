//
//  OperationQueueViewModel.swift
//  Cauldron
//
//  Created by Claude on 11/14/25.
//

import Foundation
import SwiftUI
import os

/// MainActor view model that exposes operation queue state to the UI
@MainActor
@Observable
final class OperationQueueViewModel {
    // MARK: - Properties

    private(set) var pendingOperations: [SyncOperation] = []
    private(set) var pendingRecipeCount: Int = 0
    private(set) var pendingCollectionCount: Int = 0
    private(set) var totalPendingCount: Int = 0
    private(set) var hasFailedOperations: Bool = false

    // MARK: - Private Properties

    @ObservationIgnored
    private let service: OperationQueueService
    @ObservationIgnored
    private var eventTask: Task<Void, Never>?

    // MARK: - Initialization

    init(service: OperationQueueService) {
        self.service = service

        // Start listening to events
        startEventListener()

        // Load initial state
        Task {
            await loadState()
        }
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    // MARK: - Public API

    /// Check if a specific entity has pending operations
    func hasPendingOperation(for entityId: UUID) async -> Bool {
        await service.hasPendingOperation(for: entityId)
    }

    /// Get the sync status for a specific entity
    func getStatus(for entityId: UUID) async -> OperationStatus? {
        await service.getStatus(for: entityId)
    }

    /// Get operations for a specific entity
    func getOperations(for entityId: UUID) async -> [SyncOperation] {
        await service.getOperations(for: entityId)
    }

    /// Manually retry all failed operations
    func retryFailedOperations() {
        Task {
            await service.retryFailedOperations()
            await loadState()
        }
    }

    /// Remove a specific operation
    func removeOperation(_ operationId: UUID) {
        Task {
            await service.removeOperation(operationId: operationId)
            await loadState()
        }
    }

    /// Clear all completed operations
    func clearCompletedOperations() {
        Task {
            await service.clearCompletedOperations()
            await loadState()
        }
    }

    /// Helper to check if entity is currently syncing
    func isSyncing(_ entityId: UUID) -> Bool {
        pendingOperations.contains { operation in
            operation.entityId == entityId && operation.status == .inProgress
        }
    }

    /// Helper to check if entity has failed sync
    func hasFailed(_ entityId: UUID) -> Bool {
        pendingOperations.contains { operation in
            operation.entityId == entityId && operation.status == .failed
        }
    }

    /// Helper to check if entity is pending sync
    func isPending(_ entityId: UUID) -> Bool {
        pendingOperations.contains { operation in
            operation.entityId == entityId && operation.status == .pending
        }
    }

    /// Get sync indicator color for an entity
    func syncIndicatorColor(for entityId: UUID) -> Color? {
        if hasFailed(entityId) {
            return .red
        } else if isSyncing(entityId) || isPending(entityId) {
            return .orange
        }
        return nil
    }

    /// Get sync indicator icon for an entity
    func syncIndicatorIcon(for entityId: UUID) -> String? {
        if hasFailed(entityId) {
            return "exclamationmark.triangle.fill"
        } else if isSyncing(entityId) {
            return "arrow.triangle.2.circlepath"
        } else if isPending(entityId) {
            return "clock.fill"
        }
        return nil
    }

    // MARK: - Private Methods

    /// Load current state from service
    private func loadState() async {
        let operations = await service.getAllOperations()
        let recipeCount = await service.getPendingCount(for: .recipe)
        let collectionCount = await service.getPendingCount(for: .collection)
        let totalCount = await service.getTotalPendingCount()

        await MainActor.run {
            self.pendingOperations = operations
            self.pendingRecipeCount = recipeCount
            self.pendingCollectionCount = collectionCount
            self.totalPendingCount = totalCount
            self.hasFailedOperations = operations.contains { $0.status == .failed }
        }
    }

    /// Listen to operation queue events and update UI state
    private func startEventListener() {
        eventTask = Task {
            for await event in service.events {
                await handleEvent(event)
            }
        }
    }

    /// Handle operation queue events
    private func handleEvent(_ event: OperationQueueEvent) async {
        switch event {
        case .operationAdded(let operation):
            AppLogger.general.info("🔔 Operation added: \(operation.displayDescription)")
            await loadState()

        case .operationStarted(let operation):
            AppLogger.general.info("▶️ Operation started: \(operation.displayDescription)")
            await loadState()

        case .operationCompleted(let id):
            AppLogger.general.info("✅ Operation completed: \(id)")
            await loadState()

        case .operationFailed(let operation):
            AppLogger.general.warning("⚠️ Operation failed: \(operation.displayDescription)")
            await loadState()

        case .operationRetrying(let operation):
            AppLogger.general.info("🔄 Operation retrying: \(operation.displayDescription)")
            await loadState()

        case .queueEmpty:
            AppLogger.general.info("📭 Operation queue is now empty")
            await loadState()
        }
    }
}

// MARK: - Preview Support

extension OperationQueueViewModel {
    static func preview() -> OperationQueueViewModel {
        OperationQueueViewModel(service: OperationQueueService())
    }
}
