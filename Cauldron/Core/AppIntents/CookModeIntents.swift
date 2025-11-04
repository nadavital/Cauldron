//
//  CookModeIntents.swift
//  Cauldron
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
        // Read current session from shared UserDefaults
        guard let sharedDefaults = UserDefaults(suiteName: "group.Nadav.Cauldron"),
              let recipeIdString = sharedDefaults.string(forKey: "activeCookSession.recipeId"),
              let _ = UUID(uuidString: recipeIdString) else {
            return .result()
        }

        let currentStep = sharedDefaults.integer(forKey: "activeCookSession.stepIndex")
        let totalSteps = sharedDefaults.integer(forKey: "activeCookSession.totalSteps")

        // Don't navigate past the last step
        guard currentStep < totalSteps - 1 else {
            return .result()
        }

        // Update step index
        let newStep = currentStep + 1
        sharedDefaults.set(newStep, forKey: "activeCookSession.stepIndex")
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: "activeCookSession.timestamp")

        // Post notification to update the main app
        NotificationCenter.default.post(
            name: NSNotification.Name("CookModeStepChanged"),
            object: ["step": newStep]
        )

        return .result()
    }
}

/// App Intent to navigate to the previous step in cook mode
struct PreviousStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Previous Step"
    static var description = IntentDescription("Move to the previous cooking step")

    func perform() async throws -> some IntentResult {
        // Read current session from shared UserDefaults
        guard let sharedDefaults = UserDefaults(suiteName: "group.Nadav.Cauldron"),
              let recipeIdString = sharedDefaults.string(forKey: "activeCookSession.recipeId"),
              let _ = UUID(uuidString: recipeIdString) else {
            return .result()
        }

        let currentStep = sharedDefaults.integer(forKey: "activeCookSession.stepIndex")

        // Don't navigate before the first step
        guard currentStep > 0 else {
            return .result()
        }

        // Update step index
        let newStep = currentStep - 1
        sharedDefaults.set(newStep, forKey: "activeCookSession.stepIndex")
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: "activeCookSession.timestamp")

        // Post notification to update the main app
        NotificationCenter.default.post(
            name: NSNotification.Name("CookModeStepChanged"),
            object: ["step": newStep]
        )

        return .result()
    }
}
