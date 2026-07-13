//
//  CookModeIntents.swift
//  CauldronWidget
//
//  App Intents for Live Activity interactions
//

import AppIntents
import Foundation

/// App Intent to navigate to the next step in cook mode
struct NextStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Step"
    static var description = IntentDescription("Move to the next cooking step")

    func perform() async throws -> some IntentResult {
        if let snapshot = CookSessionSharedStore.move(by: 1) {
            await CookSessionLiveActivityUpdater.update(from: snapshot)
        }
        return .result()
    }
}

/// App Intent to navigate to the previous step in cook mode
struct PreviousStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Step"
    static var description = IntentDescription("Move to the previous cooking step")

    func perform() async throws -> some IntentResult {
        // Read current session from shared UserDefaults
        if let snapshot = CookSessionSharedStore.move(by: -1) {
            await CookSessionLiveActivityUpdater.update(from: snapshot)
        }
        return .result()
    }
}
