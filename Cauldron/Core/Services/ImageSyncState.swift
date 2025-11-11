//
//  ImageSyncState.swift
//  Cauldron
//
//  Created by Claude on 11/5/25.
//

import Foundation

/// Sync event emitted when image sync state changes
enum SyncEvent: Sendable {
    case uploadAdded(UUID)
    case uploadCompleted(UUID)
    case downloadAdded(UUID)
    case downloadCompleted(UUID)
    case error(UUID, String)
    case migrationStatusChanged(MigrationStatus)
}

/// Tracks the synchronization state of recipe images between local storage and CloudKit
enum ImageSyncState: Sendable {
    /// Image is synchronized between local and cloud
    case synced

    /// Local image is newer than cloud, needs upload
    case uploadPending

    /// Cloud image is newer than local, needs download
    case downloadPending

    /// Image only exists locally, no cloud copy
    case localOnly

    /// Image sync failed with an error
    case error(String)

    var description: String {
        switch self {
        case .synced:
            return "Synced"
        case .uploadPending:
            return "Upload Pending"
        case .downloadPending:
            return "Download Pending"
        case .localOnly:
            return "Local Only"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

/// Actor to manage pending image sync operations
actor ImageSyncManager {
    /// Set of recipe IDs with pending image uploads
    private(set) var pendingUploads: Set<UUID> = []

    /// Set of recipe IDs with pending image downloads
    private(set) var pendingDownloads: Set<UUID> = []

    // UserDefaults keys for persistence
    private let pendingUploadsKey = "com.cauldron.pendingImageUploads"
    private let pendingDownloadsKey = "com.cauldron.pendingImageDownloads"

    // Event stream for reactive updates
    private let eventContinuation: AsyncStream<SyncEvent>.Continuation
    private let eventStream: AsyncStream<SyncEvent>

    init() {
        // Create event stream
        var continuation: AsyncStream<SyncEvent>.Continuation!
        self.eventStream = AsyncStream { continuation = $0 }
        self.eventContinuation = continuation

        // Load persisted pending operations
        loadPendingOperations()
    }

    /// Subscribe to sync events
    var events: AsyncStream<SyncEvent> {
        eventStream
    }

    /// Load pending operations from UserDefaults
    private func loadPendingOperations() {
        // Load pending uploads
        if let data = UserDefaults.standard.data(forKey: pendingUploadsKey),
           let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
            pendingUploads = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
        }

        // Load pending downloads
        if let data = UserDefaults.standard.data(forKey: pendingDownloadsKey),
           let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
            pendingDownloads = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
        }
    }

    /// Save pending uploads to UserDefaults
    private func savePendingUploads() {
        let uuidStrings = pendingUploads.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(uuidStrings) {
            UserDefaults.standard.set(data, forKey: pendingUploadsKey)
        }
    }

    /// Save pending downloads to UserDefaults
    private func savePendingDownloads() {
        let uuidStrings = pendingDownloads.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(uuidStrings) {
            UserDefaults.standard.set(data, forKey: pendingDownloadsKey)
        }
    }

    /// Add a recipe ID to pending uploads
    func addPendingUpload(_ recipeId: UUID) {
        pendingUploads.insert(recipeId)
        savePendingUploads()
        eventContinuation.yield(.uploadAdded(recipeId))
    }

    /// Remove a recipe ID from pending uploads
    func removePendingUpload(_ recipeId: UUID) {
        pendingUploads.remove(recipeId)
        savePendingUploads()
        eventContinuation.yield(.uploadCompleted(recipeId))
    }

    /// Add a recipe ID to pending downloads
    func addPendingDownload(_ recipeId: UUID) {
        pendingDownloads.insert(recipeId)
        savePendingDownloads()
        eventContinuation.yield(.downloadAdded(recipeId))
    }

    /// Remove a recipe ID from pending downloads
    func removePendingDownload(_ recipeId: UUID) {
        pendingDownloads.remove(recipeId)
        savePendingDownloads()
        eventContinuation.yield(.downloadCompleted(recipeId))
    }

    /// Report an error for a recipe
    func reportError(_ error: String, for recipeId: UUID) {
        eventContinuation.yield(.error(recipeId, error))
    }

    /// Check if a recipe has any pending operations
    func hasPendingOperation(for recipeId: UUID) -> Bool {
        return pendingUploads.contains(recipeId) || pendingDownloads.contains(recipeId)
    }

    /// Get the current sync state for a recipe
    func getSyncState(for recipeId: UUID, hasLocalImage: Bool, hasCloudImage: Bool, localModified: Date?, cloudModified: Date?) -> ImageSyncState {
        // Check for pending operations first
        if pendingUploads.contains(recipeId) {
            return .uploadPending
        }

        if pendingDownloads.contains(recipeId) {
            return .downloadPending
        }

        // Determine state based on image existence and modification dates
        if !hasLocalImage && !hasCloudImage {
            return .localOnly
        }

        if !hasCloudImage && hasLocalImage {
            return .localOnly
        }

        if hasCloudImage && !hasLocalImage {
            return .downloadPending
        }

        // Both exist - compare modification dates
        guard let localDate = localModified, let cloudDate = cloudModified else {
            return .synced
        }

        if localDate > cloudDate {
            return .uploadPending
        } else if cloudDate > localDate {
            return .downloadPending
        }

        return .synced
    }

    /// Clear all pending operations
    func clearAll() {
        let clearedUploads = pendingUploads
        let clearedDownloads = pendingDownloads

        pendingUploads.removeAll()
        pendingDownloads.removeAll()
        savePendingUploads()
        savePendingDownloads()

        // Emit completion events for cleared items
        for recipeId in clearedUploads {
            eventContinuation.yield(.uploadCompleted(recipeId))
        }
        for recipeId in clearedDownloads {
            eventContinuation.yield(.downloadCompleted(recipeId))
        }
    }

    deinit {
        eventContinuation.finish()
    }
}
