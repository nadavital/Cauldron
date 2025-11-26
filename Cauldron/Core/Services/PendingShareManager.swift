//
//  PendingShareManager.swift
//  Cauldron
//
//  Thread-safe actor for managing pending share URLs and metadata
//

import Foundation
import CloudKit

/// Thread-safe actor for managing pending share URLs and CloudKit metadata.
/// Replaces the unsafe static variables in AppDelegate.
///
/// This actor ensures serial access to pending share data from any thread,
/// preventing race conditions when URLs arrive via AppDelegate callbacks.
actor PendingShareManager {
    static let shared = PendingShareManager()

    private var pendingURL: URL?
    private var pendingMetadata: CKShare.Metadata?

    private init() {}

    /// Store a pending share URL
    func setPendingURL(_ url: URL) {
        pendingURL = url
    }

    /// Retrieve and clear the pending share URL (consume pattern)
    func consumePendingURL() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }

    /// Store pending CloudKit share metadata
    func setPendingMetadata(_ metadata: CKShare.Metadata) {
        pendingMetadata = metadata
    }

    /// Retrieve and clear the pending metadata (consume pattern)
    func consumePendingMetadata() -> CKShare.Metadata? {
        defer { pendingMetadata = nil }
        return pendingMetadata
    }

    /// Clear all pending data
    func clear() {
        pendingURL = nil
        pendingMetadata = nil
    }
}
