//
//  ImageSyncViewModel.swift
//  Cauldron
//
//  Created by Claude on 11/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

/// ViewModel that makes image sync state observable to the UI
@MainActor
class ImageSyncViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.cauldron", category: "ImageSyncViewModel")

    /// Recipes with pending image uploads
    @Published private(set) var pendingUploads: Set<UUID> = []

    /// Recipes with pending image downloads
    @Published private(set) var pendingDownloads: Set<UUID> = []

    /// Upload progress for each recipe (0.0 to 1.0)
    @Published private(set) var uploadProgress: [UUID: Double] = [:]

    /// Sync errors for each recipe
    @Published private(set) var syncErrors: [UUID: String] = [:]

    /// Migration status
    @Published private(set) var migrationStatus: MigrationStatus = .notStarted

    /// Whether any sync operations are in progress
    var isSyncing: Bool {
        !pendingUploads.isEmpty || !pendingDownloads.isEmpty
    }

    /// Number of total pending operations
    var totalPendingOperations: Int {
        pendingUploads.count + pendingDownloads.count
    }

    private let imageSyncManager: ImageSyncManager
    private let imageMigrationService: CloudImageMigration?
    private var eventObserverTask: Task<Void, Never>?
    private var statusPollingTask: Task<Void, Never>?

    init(imageSyncManager: ImageSyncManager, imageMigrationService: CloudImageMigration? = nil) {
        self.imageSyncManager = imageSyncManager
        self.imageMigrationService = imageMigrationService
        startObservingEvents()
        startMigrationStatusPolling()
    }

    deinit {
        eventObserverTask?.cancel()
        statusPollingTask?.cancel()
    }

    /// Start observing sync events (event-driven, no polling!)
    private func startObservingEvents() {
        eventObserverTask = Task { [weak self] in
            guard let self = self else { return }

            // Subscribe to event stream
            for await event in await imageSyncManager.events {
                guard !Task.isCancelled else { break }
                await self.handleSyncEvent(event)
            }
        }
    }

    /// Handle a sync event from ImageSyncManager
    private func handleSyncEvent(_ event: SyncEvent) {
        switch event {
        case .uploadAdded(let recipeId):
            pendingUploads.insert(recipeId)

        case .uploadCompleted(let recipeId):
            pendingUploads.remove(recipeId)
            syncErrors.removeValue(forKey: recipeId)

        case .downloadAdded(let recipeId):
            pendingDownloads.insert(recipeId)

        case .downloadCompleted(let recipeId):
            pendingDownloads.remove(recipeId)
            syncErrors.removeValue(forKey: recipeId)

        case .error(let recipeId, let error):
            syncErrors[recipeId] = error

        case .migrationStatusChanged(let status):
            migrationStatus = status
        }
    }

    /// Poll migration status periodically (only for migration UI updates)
    /// This is acceptable since migration is infrequent and time-limited
    private func startMigrationStatusPolling() {
        statusPollingTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                // Only poll if migration service exists and is in progress
                if let migration = self.imageMigrationService {
                    let status = await migration.getStatus()
                    await MainActor.run {
                        self.migrationStatus = status
                    }

                    // If migration complete or failed, stop polling
                    if case .completed = status {
                        break
                    }
                    if case .failed = status {
                        break
                    }
                }

                // Poll every 5 seconds (only while migration active)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    /// Get sync state for a specific recipe
    /// - Parameter recipeId: The recipe ID
    /// - Returns: The current sync state
    func getSyncState(for recipeId: UUID) -> ImageSyncState {
        if pendingUploads.contains(recipeId) {
            return .uploadPending
        }

        if pendingDownloads.contains(recipeId) {
            return .downloadPending
        }

        if let error = syncErrors[recipeId] {
            return .error(error)
        }

        return .synced
    }

    /// Report a sync error for a recipe
    /// - Parameters:
    ///   - error: The error message
    ///   - recipeId: The recipe ID
    func reportError(_ error: String, for recipeId: UUID) {
        syncErrors[recipeId] = error
        logger.error("Sync error for recipe \(recipeId): \(error)")
    }

    /// Clear error for a recipe
    /// - Parameter recipeId: The recipe ID
    func clearError(for recipeId: UUID) {
        syncErrors.removeValue(forKey: recipeId)
    }

    /// Clear all errors
    func clearAllErrors() {
        syncErrors.removeAll()
    }

    /// Retry migration if it failed
    func retryMigration() {
        guard let migration = imageMigrationService else { return }

        Task {
            await migration.retryMigration()
            // No need to updateSyncState() - migration will emit events
        }
    }

    /// Get user-friendly status message
    var statusMessage: String {
        if !pendingUploads.isEmpty && !pendingDownloads.isEmpty {
            return "Syncing \(pendingUploads.count) uploads and \(pendingDownloads.count) downloads..."
        } else if !pendingUploads.isEmpty {
            return "Uploading \(pendingUploads.count) image\(pendingUploads.count == 1 ? "" : "s")..."
        } else if !pendingDownloads.isEmpty {
            return "Downloading \(pendingDownloads.count) image\(pendingDownloads.count == 1 ? "" : "s")..."
        } else {
            return "All images synced"
        }
    }

    /// Get migration progress message
    var migrationMessage: String? {
        switch migrationStatus {
        case .notStarted:
            return nil
        case .inProgress(let completed, let total):
            return "Migrating images to iCloud: \(completed)/\(total)"
        case .completed(let count):
            return "Migration complete: \(count) images uploaded"
        case .failed(let error):
            return "Migration failed: \(error)"
        }
    }

    /// Whether migration is currently running
    var isMigrating: Bool {
        migrationStatus.isInProgress
    }
}

// MARK: - SwiftUI View Helpers

extension ImageSyncViewModel {
    /// View modifier to show sync status banner
    struct SyncStatusBanner: ViewModifier {
        @ObservedObject var viewModel: ImageSyncViewModel

        func body(content: Content) -> some View {
            VStack(spacing: 0) {
                content

                // Migration banner
                if viewModel.isMigrating, let message = viewModel.migrationMessage {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text(message)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                }

                // Sync status banner
                if viewModel.isSyncing {
                    HStack {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                        Text(viewModel.statusMessage)
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.1))
                }

                // Error banner
                if !viewModel.syncErrors.isEmpty {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("\(viewModel.syncErrors.count) image sync error\(viewModel.syncErrors.count == 1 ? "" : "s")")
                            .font(.caption)
                        Spacer()
                        Button("Clear") {
                            viewModel.clearAllErrors()
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1))
                }
            }
        }
    }
}

// MARK: - View Extension

extension View {
    /// Show image sync status banner on this view
    /// - Parameter viewModel: The ImageSyncViewModel to observe
    /// - Returns: View with sync status banner
    func imageSyncStatusBanner(_ viewModel: ImageSyncViewModel) -> some View {
        modifier(ImageSyncViewModel.SyncStatusBanner(viewModel: viewModel))
    }
}
