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

// MARK: - Best-Effort Operation Helper

/// Run a throwing async operation as *best-effort*: if it fails, the error is
/// logged (so it's diagnosable) but swallowed (so it doesn't interrupt the user).
///
/// Use this instead of a bare `try?` for non-critical background work — cache
/// writes, best-effort sync, opportunistic saves — where failure shouldn't stop
/// the flow but should never disappear silently.
///
/// ```swift
/// await bestEffort("Cache shared user") {
///     try await sharingRepository.save(cloudUser)
/// }
/// ```
@discardableResult
func bestEffort<T>(
    _ context: @autoclosure () -> String,
    logger: Logger = AppLogger.general,
    operation: () async throws -> T
) async -> T? {
    do {
        return try await operation()
    } catch {
        logger.warning("\(context()) failed: \(error.localizedDescription)")
        return nil
    }
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
