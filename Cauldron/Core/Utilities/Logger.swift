//
//  Logger.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import os.log

/// Centralized logging for the app
/// Uses os.log for production and print for debug builds to ensure visibility in Xcode console
struct AppLogger {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cauldron.app"

    nonisolated static let general = Logger(subsystem: subsystem, category: "general")
    nonisolated static let parsing = Logger(subsystem: subsystem, category: "parsing")
    nonisolated static let persistence = Logger(subsystem: subsystem, category: "persistence")
    nonisolated static let cooking = Logger(subsystem: subsystem, category: "cooking")
    nonisolated static let network = Logger(subsystem: subsystem, category: "network")
}

// MARK: - Debug Logging Helper
/// Extension to make logs visible in Xcode console during development
extension Logger {
    /// Log info message (visible in Xcode console in debug builds)
    nonisolated func info(_ message: String) {
        #if DEBUG
        print("ℹ️  \(message)")
        #else
        self.log(level: .info, "\(message)")
        #endif
    }

    /// Log debug message (visible in Xcode console in debug builds)
    nonisolated func debug(_ message: String) {
        #if DEBUG
        print("🔍 \(message)")
        #else
        self.log(level: .debug, "\(message)")
        #endif
    }

    /// Log error message (visible in Xcode console in debug builds)
    nonisolated func error(_ message: String) {
        #if DEBUG
        print("❌ \(message)")
        #else
        self.log(level: .error, "\(message)")
        #endif
    }

    /// Log warning message (visible in Xcode console in debug builds)
    nonisolated func warning(_ message: String) {
        #if DEBUG
        print("⚠️  \(message)")
        #else
        self.log(level: .default, "\(message)")
        #endif
    }
}
