//
//  SyncDeviceIdentifier.swift
//  Cauldron
//

import Foundation

enum SyncDeviceIdentifier {
    nonisolated private static let storageKey = "com.cauldron.sync.sourceDeviceId"

    /// Stable per-install identifier for diagnosing and reconciling multi-device sync writes.
    nonisolated static func current() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: storageKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: storageKey)
        return generated
    }
}
