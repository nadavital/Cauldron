//
//  CookModeCoordinator.swift
//  Cauldron
//
//  Created by Claude on 10/31/25.
//

import Foundation
import SwiftUI
import ActivityKit
import os

/// Coordinates the persistent cook mode session across the app
@MainActor
@Observable
class CookModeCoordinator {

    // MARK: - Published State

    /// Whether cook mode is currently active
    var isActive: Bool = false

    /// Whether to show full screen cook mode
    var showFullScreen: Bool = false

    /// Current recipe being cooked (nil when inactive)
    var currentRecipe: Recipe?

    /// Current step index in the recipe
    var currentStepIndex: Int = 0

    /// Total number of steps
    var totalSteps: Int = 0

    /// Session start time
    var sessionStartTime: Date?

    /// Show conflict alert when trying to start new recipe
    var showSessionConflictAlert: Bool = false
    var pendingRecipe: Recipe?

    // MARK: - Dependencies

    private let dependencies: DependencyContainer
    private let storageKey = "activeCookSession"

    // Live Activity support (will be implemented in Phase 4)
    // private var currentActivity: Activity<CookModeActivityAttributes>?

    // MARK: - Initialization

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    // MARK: - Public Methods

    /// Start cooking a recipe
    func startCooking(_ recipe: Recipe) async {
        // Check if different recipe is already cooking
        if isActive, let current = currentRecipe, current.id != recipe.id {
            // Show conflict alert
            pendingRecipe = recipe
            showSessionConflictAlert = true
            return
        }

        // Start new session
        currentRecipe = recipe
        currentStepIndex = 0
        totalSteps = recipe.steps.count
        sessionStartTime = Date()
        isActive = true

        // Save state
        saveState()

        // Update CookSessionManager (legacy support)
        await dependencies.cookSessionManager.startSession(recipe: recipe)

        // Show full screen cook mode
        showFullScreen = true

        // Start Live Activity (Phase 4)
        // await startLiveActivity()

        AppLogger.general.info("✅ Started cooking session: \(recipe.title)")
    }

    /// Start cooking with pending recipe (after conflict resolution)
    func startPendingRecipe() async {
        guard let pending = pendingRecipe else { return }

        // End current session
        endSession()

        // Start new session
        await startCooking(pending)

        // Clear pending
        pendingRecipe = nil
    }

    /// Navigate to next step
    func nextStep() {
        guard let recipe = currentRecipe, currentStepIndex < recipe.steps.count - 1 else {
            return
        }

        currentStepIndex += 1
        saveState()

        // Update Live Activity (Phase 4)
        // Task { await updateLiveActivity() }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        AppLogger.general.info("→ Next step: \(self.currentStepIndex + 1)/\(self.totalSteps)")
    }

    /// Navigate to previous step
    func previousStep() {
        guard currentStepIndex > 0 else { return }

        currentStepIndex -= 1
        saveState()

        // Update Live Activity (Phase 4)
        // Task { await updateLiveActivity() }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        AppLogger.general.info("← Previous step: \(self.currentStepIndex + 1)/\(self.totalSteps)")
    }

    /// Minimize to banner (from full screen)
    func minimizeToBackground() {
        showFullScreen = false
        AppLogger.general.info("🔽 Minimized cook mode to banner")
    }

    /// Expand to full screen (from banner)
    func expandToFullScreen() {
        showFullScreen = true
        AppLogger.general.info("🔼 Expanded cook mode to full screen")
    }

    /// End the cooking session
    func endSession() {
        guard isActive else { return }

        let recipeName = currentRecipe?.title ?? "Unknown"

        // Clear state
        isActive = false
        showFullScreen = false
        currentRecipe = nil
        currentStepIndex = 0
        totalSteps = 0
        sessionStartTime = nil

        // Clear persisted state
        clearState()

        // End CookSessionManager session (legacy support)
        Task {
            await dependencies.cookSessionManager.endSession()
        }

        // End Live Activity (Phase 4)
        // Task { await endLiveActivity() }

        AppLogger.general.info("🛑 Ended cooking session: \(recipeName)")
    }

    /// Restore session from persistent storage
    func restoreState() async {
        // Check if we have a saved session
        guard let recipeIdString = UserDefaults.standard.string(forKey: "\(storageKey).recipeId"),
              let recipeId = UUID(uuidString: recipeIdString) else {
            AppLogger.general.info("No saved cooking session to restore")
            return
        }

        let stepIndex = UserDefaults.standard.integer(forKey: "\(storageKey).stepIndex")

        // Fetch recipe from repository
        do {
            if let recipe = try await dependencies.recipeRepository.fetch(id: recipeId) {
                // Restore session state
                currentRecipe = recipe
                currentStepIndex = min(stepIndex, recipe.steps.count - 1) // Validate step index
                totalSteps = recipe.steps.count
                isActive = true

                // Don't restore session start time - use current time
                sessionStartTime = Date()

                // Don't auto-show full screen - just show banner
                showFullScreen = false

                AppLogger.general.info("✅ Restored cooking session: \(recipe.title) at step \(self.currentStepIndex + 1)")
            } else {
                // Recipe was deleted
                AppLogger.general.warning("⚠️ Recipe from saved session no longer exists")
                clearState()
            }
        } catch {
            AppLogger.general.error("❌ Failed to restore cooking session: \(error.localizedDescription)")
            clearState()
        }
    }

    // MARK: - Current Step Helpers

    /// Get the current step object
    var currentStep: CookStep? {
        guard let recipe = currentRecipe,
              currentStepIndex < recipe.steps.count else {
            return nil
        }
        return recipe.steps[currentStepIndex]
    }

    /// Get progress as a percentage (0.0 to 1.0)
    var progress: Double {
        guard totalSteps > 0 else { return 0.0 }
        return Double(currentStepIndex + 1) / Double(totalSteps)
    }

    /// Check if we're on the last step
    var isLastStep: Bool {
        currentStepIndex == totalSteps - 1
    }

    /// Check if we're on the first step
    var isFirstStep: Bool {
        currentStepIndex == 0
    }

    // MARK: - Private Methods

    private func saveState() {
        guard let recipe = currentRecipe else {
            clearState()
            return
        }

        UserDefaults.standard.set(recipe.id.uuidString, forKey: "\(storageKey).recipeId")
        UserDefaults.standard.set(currentStepIndex, forKey: "\(storageKey).stepIndex")
        UserDefaults.standard.set(totalSteps, forKey: "\(storageKey).totalSteps")
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(storageKey).timestamp")

        AppLogger.general.debug("💾 Saved cook session state")
    }

    private func clearState() {
        UserDefaults.standard.removeObject(forKey: "\(storageKey).recipeId")
        UserDefaults.standard.removeObject(forKey: "\(storageKey).stepIndex")
        UserDefaults.standard.removeObject(forKey: "\(storageKey).totalSteps")
        UserDefaults.standard.removeObject(forKey: "\(storageKey).timestamp")

        AppLogger.general.debug("🗑️ Cleared cook session state")
    }

    // MARK: - Live Activity Methods (Phase 4)

    /*
    private func startLiveActivity() async {
        guard let recipe = currentRecipe,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let attributes = CookModeActivityAttributes(
            recipeId: recipe.id.uuidString,
            recipeName: recipe.title,
            recipeEmoji: recipe.emoji
        )

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerSeconds: dependencies.timerManager.activeTimers.first?.remainingSeconds,
            progressPercentage: progress
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
            AppLogger.general.info("✅ Started Live Activity")
        } catch {
            AppLogger.general.error("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    private func updateLiveActivity() async {
        guard let activity = currentActivity,
              let recipe = currentRecipe else {
            return
        }

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerSeconds: dependencies.timerManager.activeTimers.first?.remainingSeconds,
            progressPercentage: progress
        )

        await activity.update(
            .init(state: contentState, staleDate: nil)
        )

        AppLogger.general.debug("🔄 Updated Live Activity")
    }

    private func endLiveActivity() async {
        guard let activity = currentActivity else { return }

        await activity.end(
            .init(state: activity.content.state, staleDate: nil),
            dismissalPolicy: .immediate
        )

        currentActivity = nil
        AppLogger.general.info("🛑 Ended Live Activity")
    }
    */
}
