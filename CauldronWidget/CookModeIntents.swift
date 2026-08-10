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

    @Parameter(title: "Recipe ID") var recipeID: String
    @Parameter(title: "Session Start") var sessionStartTime: Date

    init() {}

    init(recipeID: String, sessionStartTime: Date) {
        self.recipeID = recipeID
        self.sessionStartTime = sessionStartTime
    }

    func perform() async throws -> some IntentResult {
        if let expected = CookSessionSharedStore.read(),
           expected.recipeID.uuidString == recipeID,
           expected.sessionStartTime == sessionStartTime,
           let snapshot = CookSessionSharedStore.move(by: 1, expected: expected) {
            await CookSessionLiveActivityUpdater.update(from: snapshot)
        }
        return .result()
    }
}

/// App Intent to navigate to the previous step in cook mode
struct PreviousStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Step"
    static var description = IntentDescription("Move to the previous cooking step")

    @Parameter(title: "Recipe ID") var recipeID: String
    @Parameter(title: "Session Start") var sessionStartTime: Date

    init() {}

    init(recipeID: String, sessionStartTime: Date) {
        self.recipeID = recipeID
        self.sessionStartTime = sessionStartTime
    }

    func perform() async throws -> some IntentResult {
        // Read current session from shared UserDefaults
        if let expected = CookSessionSharedStore.read(),
           expected.recipeID.uuidString == recipeID,
           expected.sessionStartTime == sessionStartTime,
           let snapshot = CookSessionSharedStore.move(by: -1, expected: expected) {
            await CookSessionLiveActivityUpdater.update(from: snapshot)
        }
        return .result()
    }
}
