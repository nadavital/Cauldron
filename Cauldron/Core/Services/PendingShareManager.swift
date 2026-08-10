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

    nonisolated static let pendingURLDefaultsKey = "externalShare.pendingURL.v1"

    private var pendingURL: URL?
    private var pendingMetadata: CKShare.Metadata?
    private let defaults: UserDefaults?

    init(defaults: UserDefaults? = UserDefaults(suiteName: CookSessionSharedStore.appGroupID)) {
        self.defaults = defaults
    }

    /// Store the pending share URL. This is intentionally a durable latest-wins
    /// slot: if several links arrive while one is resolving, the most recent
    /// user action supersedes older routes that have not started yet.
    func setPendingURL(_ url: URL) {
        pendingURL = url
        defaults?.set(url.absoluteString, forKey: Self.pendingURLDefaultsKey)
    }

    /// Read the pending route without acknowledging it. The caller clears it
    /// only after successful or terminal handling so a process kill or a
    /// transient network failure cannot silently lose the link.
    func peekPendingURL() -> URL? {
        pendingURL ?? persistedPendingURL()
    }

    /// Retrieve and clear the pending share URL (consume pattern)
    func consumePendingURL() -> URL? {
        let url = pendingURL ?? persistedPendingURL()
        pendingURL = nil
        defaults?.removeObject(forKey: Self.pendingURLDefaultsKey)
        return url
    }

    /// Clear the pending share URL only if it matches the URL already being handled.
    func clearPendingURL(matching url: URL) {
        guard pendingURL == url || persistedPendingURL() == url else { return }
        pendingURL = nil
        defaults?.removeObject(forKey: Self.pendingURLDefaultsKey)
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
        defaults?.removeObject(forKey: Self.pendingURLDefaultsKey)
    }

    private func persistedPendingURL() -> URL? {
        guard let rawURL = defaults?.string(forKey: Self.pendingURLDefaultsKey) else {
            return nil
        }
        guard let url = URL(string: rawURL) else {
            defaults?.removeObject(forKey: Self.pendingURLDefaultsKey)
            return nil
        }
        return url
    }
}
