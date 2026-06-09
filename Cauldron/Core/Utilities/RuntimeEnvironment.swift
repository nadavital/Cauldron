//
//  RuntimeEnvironment.swift
//  Cauldron
//
//  Created by Codex on 4/6/26.
//

import Foundation

enum RuntimeEnvironment {
    nonisolated private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    nonisolated private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    nonisolated static var isRunningTests: Bool {
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    nonisolated static var isRunningCI: Bool {
        environment["CI"] == "true"
    }

    nonisolated static var isCloudKitForcedOff: Bool {
        environment["CAULDRON_DISABLE_CLOUDKIT"] == "1"
    }

    nonisolated static var isSimulatorQAMode: Bool {
        #if DEBUG
        environment["CAULDRON_SIMULATOR_QA"] == "1" ||
            arguments.contains("--cauldron-simulator-qa")
        #else
        false
        #endif
    }

    nonisolated static var shouldForceWhatsNew: Bool {
        #if DEBUG
        arguments.contains("--cauldron-show-whats-new")
        #else
        false
        #endif
    }

    nonisolated static var screenshotTab: String? {
        #if DEBUG
        guard isSimulatorQAMode else { return nil }
        let prefix = "--cauldron-screenshot-tab="
        return arguments
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)) }
        #else
        nil
        #endif
    }

    /// Force the onboarding flow for visual review (it's normally skipped in QA seed mode).
    nonisolated static var shouldForceOnboarding: Bool {
        #if DEBUG
        arguments.contains("--cauldron-show-onboarding")
        #else
        false
        #endif
    }

    /// Treat the AI generator UI as available even where Apple Intelligence
    /// isn't (e.g. the simulator), so the input layout can be reviewed.
    /// Generation itself still requires real on-device support.
    nonisolated static var forceAIGeneratorUI: Bool {
        #if DEBUG
        arguments.contains("--cauldron-ai-preview")
        #else
        false
        #endif
    }

    nonisolated static var canUseCloudKit: Bool {
        !isRunningTests && !isRunningCI && !isCloudKitForcedOff && !isSimulatorQAMode
    }
}
