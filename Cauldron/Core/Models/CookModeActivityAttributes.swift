//
//  CookModeActivityAttributes.swift
//  Cauldron
//
//  Created for Live Activities support
//

import Foundation

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// Attributes for the Cook Mode Live Activity
/// Defines the static and dynamic content shown on lock screen and Dynamic Island
struct CookModeActivityAttributes: ActivityAttributes {
    /// Dynamic state that changes during cooking
    public struct ContentState: Codable, Hashable {
        /// Current step index (0-based)
        var currentStep: Int

        /// Total number of steps in recipe
        var totalSteps: Int

        /// Text of the current step instruction
        var stepInstruction: String

        /// Number of active timers currently running
        var activeTimerCount: Int

        /// Primary timer information (if any)
        var primaryTimerDurationSeconds: Int?
        var primaryTimerIsRunning: Bool

        /// Overall progress through the recipe (0.0 to 1.0)
        var progressPercentage: Double

        /// Timestamp of last update for sync verification
        var lastUpdated: Date
    }

    // MARK: - Static Attributes (Set Once)

    /// Unique identifier for the recipe
    var recipeId: String

    /// Name of the recipe being cooked
    var recipeName: String

    /// Emoji representing the recipe (optional)
    var recipeEmoji: String?

    /// Time when cooking session started
    var sessionStartTime: Date
}
#endif
