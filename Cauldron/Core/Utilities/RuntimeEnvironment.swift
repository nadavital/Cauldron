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

    /// Force the onboarding flow for visual review (it's normally skipped in QA seed mode).
    nonisolated static var shouldForceOnboarding: Bool {
        #if DEBUG
        arguments.contains("--cauldron-show-onboarding")
        #else
        false
        #endif
    }

    nonisolated static var canUseCloudKit: Bool {
        !isRunningTests && !isRunningCI && !isCloudKitForcedOff && !isSimulatorQAMode
    }
}
