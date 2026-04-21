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

    nonisolated static var isRunningTests: Bool {
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }

    nonisolated static var isRunningCI: Bool {
        environment["CI"] == "true"
    }

    nonisolated static var isCloudKitForcedOff: Bool {
        environment["CAULDRON_DISABLE_CLOUDKIT"] == "1"
    }

    nonisolated static var canUseCloudKit: Bool {
        !isRunningTests && !isRunningCI && !isCloudKitForcedOff
    }
}
