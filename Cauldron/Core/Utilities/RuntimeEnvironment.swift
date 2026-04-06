//
//  RuntimeEnvironment.swift
//  Cauldron
//
//  Created by Codex on 4/6/26.
//

import Foundation

enum RuntimeEnvironment {
    nonisolated static var isRunningTests: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
    }
}
