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

    nonisolated var description: String {
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

/// Which CloudKit database an image upload targets. Pending-upload retry state
/// is tracked per-scope so a successful private upload cannot clear a still-needed
/// public upload retry (and vice-versa).
enum ImageUploadScope: String, Sendable, CaseIterable {
    case privateDB
    case publicDB
}

/// Actor to manage pending image sync operations
actor ImageSyncManager {
    /// Recipe IDs with a pending private-database image upload.
    private(set) var pendingPrivateUploads: Set<UUID> = []

    /// Recipe IDs with a pending public-database image upload.
    private(set) var pendingPublicUploads: Set<UUID> = []

    /// All recipe IDs with any pending upload (either scope). Read-only convenience
    /// for status/aggregate callers; retries operate on the scoped sets directly.
    var pendingUploads: Set<UUID> { pendingPrivateUploads.union(pendingPublicUploads) }

    /// Set of recipe IDs with pending image downloads
    private(set) var pendingDownloads: Set<UUID> = []

    // UserDefaults keys for persistence
    private let pendingPrivateUploadsKey = "com.cauldron.pendingImageUploads.private"
    private let pendingPublicUploadsKey = "com.cauldron.pendingImageUploads.public"
    private let legacyPendingUploadsKey = "com.cauldron.pendingImageUploads"
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
        Task {
            await self.loadPendingOperations()
        }
    }

    /// Subscribe to sync events
    var events: AsyncStream<SyncEvent> {
        eventStream
    }

    /// Load pending operations from UserDefaults
    private func loadPendingOperations() {
        // Load scoped pending uploads
        pendingPrivateUploads = Self.loadUUIDSet(forKey: pendingPrivateUploadsKey)
        pendingPublicUploads = Self.loadUUIDSet(forKey: pendingPublicUploadsKey)

        // One-time migration from the legacy unscoped key: a legacy pending id
        // could need either database, so retry both scopes to be safe.
        if let data = UserDefaults.standard.data(forKey: legacyPendingUploadsKey),
           let uuidStrings = try? JSONDecoder().decode([String].self, from: data) {
            let legacy = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            if !legacy.isEmpty {
                pendingPrivateUploads.formUnion(legacy)
                pendingPublicUploads.formUnion(legacy)
                savePendingUploads()
            }
            UserDefaults.standard.removeObject(forKey: legacyPendingUploadsKey)
        }

        // Load pending downloads
        pendingDownloads = Self.loadUUIDSet(forKey: pendingDownloadsKey)
    }

    private static func loadUUIDSet(forKey key: String) -> Set<UUID> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let uuidStrings = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(uuidStrings.compactMap { UUID(uuidString: $0) })
    }

    /// Save both scoped pending-upload sets to UserDefaults
    private func savePendingUploads() {
        saveUUIDSet(pendingPrivateUploads, forKey: pendingPrivateUploadsKey)
        saveUUIDSet(pendingPublicUploads, forKey: pendingPublicUploadsKey)
    }

    private func saveUUIDSet(_ set: Set<UUID>, forKey key: String) {
        if let data = try? JSONEncoder().encode(set.map { $0.uuidString }) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Save pending downloads to UserDefaults
    private func savePendingDownloads() {
        let uuidStrings = pendingDownloads.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(uuidStrings) {
            UserDefaults.standard.set(data, forKey: pendingDownloadsKey)
        }
    }

    /// Add a recipe ID to pending uploads for a specific database scope.
    func addPendingUpload(_ recipeId: UUID, scope: ImageUploadScope) {
        switch scope {
        case .privateDB: pendingPrivateUploads.insert(recipeId)
        case .publicDB: pendingPublicUploads.insert(recipeId)
        }
        savePendingUploads()
        eventContinuation.yield(.uploadAdded(recipeId))
    }

    /// Remove a recipe ID from pending uploads for a specific database scope.
    /// Only emits completion once the recipe has no pending upload in EITHER scope.
    func removePendingUpload(_ recipeId: UUID, scope: ImageUploadScope) {
        switch scope {
        case .privateDB: pendingPrivateUploads.remove(recipeId)
        case .publicDB: pendingPublicUploads.remove(recipeId)
        }
        savePendingUploads()
        if !pendingPrivateUploads.contains(recipeId) && !pendingPublicUploads.contains(recipeId) {
            eventContinuation.yield(.uploadCompleted(recipeId))
        }
    }

    /// Remove a recipe ID from pending uploads in BOTH scopes (e.g. on delete or
    /// when there is no local image to upload at all).
    func removeAllPendingUploads(_ recipeId: UUID) {
        pendingPrivateUploads.remove(recipeId)
        pendingPublicUploads.remove(recipeId)
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

        pendingPrivateUploads.removeAll()
        pendingPublicUploads.removeAll()
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
