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

    // Live Activity support
    private var currentActivity: Activity<CookModeActivityAttributes>?

    // Shared UserDefaults for App Group communication
    private let sharedDefaults = UserDefaults(suiteName: "group.Nadav.Cauldron")

    // MARK: - Initialization

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Set up timer change callback
        dependencies.timerManager.onTimersChanged = { [weak self] in
            self?.updateLiveActivityForTimerChange()
        }

        // Listen for recipe deletion notifications
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: NSNotification.Name("RecipeDeleted")) {
                if let deletedRecipeId = notification.object as? UUID {
                    await handleRecipeDeletion(deletedRecipeId: deletedRecipeId)
                }
            }
        }

        // Listen for step changes from Live Activity
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: NSNotification.Name("CookModeStepChanged")) {
                if let userInfo = notification.object as? [String: Int],
                   let newStep = userInfo["step"] {
                    handleStepChangeFromLiveActivity(newStep: newStep)
                }
            }
        }
    }

    /// Handle recipe deletion - check if current recipe was deleted
    private func handleRecipeDeletion(deletedRecipeId: UUID) async {
        guard isActive, let currentRecipeId = currentRecipe?.id else { return }

        // Check if the deleted recipe matches our current cooking recipe
        if deletedRecipeId == currentRecipeId {
            let recipeName = currentRecipe?.title ?? "Unknown"
            AppLogger.general.warning("⚠️ Recipe '\(recipeName)' was deleted - ending cook session")

            // End the session
            endSession()

            // TODO: Show user notification/toast that recipe was deleted
        }
    }

    /// Handle step change initiated from Live Activity
    private func handleStepChangeFromLiveActivity(newStep: Int) {
        guard isActive,
              let recipe = currentRecipe,
              newStep >= 0,
              newStep < recipe.steps.count else {
            return
        }

        // Update current step
        currentStepIndex = newStep
        saveState()

        // Update Live Activity
        Task { await updateLiveActivity() }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        AppLogger.general.info("🔄 Step changed from Live Activity: \(newStep + 1)/\(self.totalSteps)")
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

        // Start Live Activity
        await startLiveActivity()

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

        // Update Live Activity
        Task { await updateLiveActivity() }

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

        // Update Live Activity
        Task { await updateLiveActivity() }

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

        // Batch all state changes together to prevent cascading view updates
        withAnimation(.easeInOut(duration: 0.2)) {
            isActive = false
            showFullScreen = false
            currentRecipe = nil
            currentStepIndex = 0
            totalSteps = 0
            sessionStartTime = nil
        }

        // Clear persisted state
        clearState()

        // End CookSessionManager session (legacy support)
        Task {
            await dependencies.cookSessionManager.endSession()
        }

        // End Live Activity
        Task { await endLiveActivity() }

        AppLogger.general.info("🛑 Ended cooking session: \(recipeName)")
    }

    /// Restore session from persistent storage
    func restoreState() async {
        // Check if we have a saved session
        guard let recipeIdString = sharedDefaults?.string(forKey: "\(storageKey).recipeId"),
              let recipeId = UUID(uuidString: recipeIdString) else {
            AppLogger.general.info("No saved cooking session to restore")
            return
        }

        let stepIndex = sharedDefaults?.integer(forKey: "\(storageKey).stepIndex") ?? 0

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

        sharedDefaults?.set(recipe.id.uuidString, forKey: "\(storageKey).recipeId")
        sharedDefaults?.set(currentStepIndex, forKey: "\(storageKey).stepIndex")
        sharedDefaults?.set(totalSteps, forKey: "\(storageKey).totalSteps")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "\(storageKey).timestamp")

        AppLogger.general.debug("💾 Saved cook session state")
    }

    private func clearState() {
        sharedDefaults?.removeObject(forKey: "\(storageKey).recipeId")
        sharedDefaults?.removeObject(forKey: "\(storageKey).stepIndex")
        sharedDefaults?.removeObject(forKey: "\(storageKey).totalSteps")
        sharedDefaults?.removeObject(forKey: "\(storageKey).timestamp")

        AppLogger.general.debug("🗑️ Cleared cook session state")
    }

    // MARK: - Live Activity Methods

    private func startLiveActivity() async {
        guard let recipe = currentRecipe,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let attributes = CookModeActivityAttributes(
            recipeId: recipe.id.uuidString,
            recipeName: recipe.title,
            recipeEmoji: nil, // Recipe model doesn't have emoji - using Cauldron icon from assets
            sessionStartTime: sessionStartTime ?? Date()
        )

        // Get shortest running timer with valid future end date
        // Add 1-second buffer to prevent race conditions where dates become stale immediately
        let minValidDate = Date().addingTimeInterval(1.0)
        let shortestTimer = dependencies.timerManager.activeTimers
            .filter { !$0.isPaused && $0.endDate > minValidDate }
            .min(by: { $0.endDate < $1.endDate })

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerEndDate: shortestTimer?.endDate,
            progressPercentage: progress,
            lastUpdated: Date()
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
              let _ = currentRecipe else {
            return
        }

        // Get shortest running timer with valid future end date
        // Add 1-second buffer to prevent race conditions where dates become stale immediately
        let minValidDate = Date().addingTimeInterval(1.0)
        let shortestTimer = dependencies.timerManager.activeTimers
            .filter { !$0.isPaused && $0.endDate > minValidDate }
            .min(by: { $0.endDate < $1.endDate })

        // Debug logging to diagnose timer issues
        if dependencies.timerManager.activeTimers.isEmpty {
            AppLogger.general.debug("🔄 Updating Live Activity - No active timers")
        } else {
            AppLogger.general.debug("🔄 Updating Live Activity - \(dependencies.timerManager.activeTimers.count) timer(s)")
            if let timer = shortestTimer {
                let remaining = timer.endDate.timeIntervalSince(Date())
                AppLogger.general.debug("   Primary timer ends in \(Int(remaining))s at \(timer.endDate)")
            } else {
                AppLogger.general.debug("   No valid running timer (all paused or expired)")
            }
        }

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerEndDate: shortestTimer?.endDate,
            progressPercentage: progress,
            lastUpdated: Date()
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

    /// Update Live Activity when timers change
    func updateLiveActivityForTimerChange() {
        guard isActive else { return }
        Task { await updateLiveActivity() }
    }
}
