//
//  Logger.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import os.log

/// Centralized logging for the app
struct AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.cauldron.app"
    
    static let general = Logger(subsystem: subsystem, category: "general")
    static let parsing = Logger(subsystem: subsystem, category: "parsing")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let cooking = Logger(subsystem: subsystem, category: "cooking")
    static let network = Logger(subsystem: subsystem, category: "network")
}
