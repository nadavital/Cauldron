//
//  CookModeCoordinator.swift
//  Cauldron
//
//  Created by Claude on 10/31/25.
//

import Foundation
import SwiftUI
import os

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Coordinates the persistent cook mode session across the app
enum CookModeStartOutcome: Sendable, Equatable {
    case started
    case alreadyActive
    case conflict
    case invalidRecipe
}

@MainActor
@Observable
class CookModeCoordinator {

    // MARK: - Published State

    /// Whether cook mode is currently active
    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            // Keep the screen awake while actively cooking so the recipe stays
            // visible with hands full; restore normal behavior when finished.
            UIApplication.shared.isIdleTimerDisabled = isActive
        }
    }

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

    /// Show toast when recipe is deleted during cooking
    var showRecipeDeletedToast: Bool = false

    // MARK: - Dependencies

    private let dependencies: DependencyContainer
    private let storageKey = "activeCookSession"

    // Live Activity support
    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private var currentActivity: Activity<CookModeActivityAttributes>?
    #endif

    // Shared UserDefaults for App Group communication
    private let sharedDefaults = UserDefaults(suiteName: "group.Nadav.Cauldron")

    // MARK: - Initialization

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Set up timer change callback
        dependencies.timerManager.onTimersChanged = { [weak self] in
            self?.updateLiveActivityForTimerChange()
        }
        if CookSessionSharedStore.read() == nil,
           !dependencies.timerManager.activeTimers.isEmpty {
            dependencies.timerManager.stopAllTimers()
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
                if let snapshot = notification.object as? CookSessionSharedSnapshot {
                    handleStepChangeFromLiveActivity(snapshot: snapshot)
                }
            }
        }
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    /// Handle recipe deletion - check if current recipe was deleted
    private func handleRecipeDeletion(deletedRecipeId: UUID) async {
        guard isActive, let currentRecipeId = currentRecipe?.id else { return }

        // Check if the deleted recipe matches our current cooking recipe
        if deletedRecipeId == currentRecipeId {
            let recipeName = currentRecipe?.title ?? "Unknown"
            AppLogger.general.warning("⚠️ Recipe '\(recipeName)' was deleted - ending cook session")

            // End the session
            endSession()

            // Show toast notification to user
            showRecipeDeletedToast = true
        }
    }

    /// Handle step change initiated from Live Activity
    private func handleStepChangeFromLiveActivity(snapshot: CookSessionSharedSnapshot) {
        guard isActive,
              let recipe = currentRecipe,
              snapshot.recipeID == recipe.id,
              let latest = CookSessionSharedStore.read(defaults: sharedDefaults),
              latest.recipeID == snapshot.recipeID,
              latest.revision == snapshot.revision,
              snapshot.stepIndex >= 0,
              snapshot.stepIndex < recipe.steps.count else {
            return
        }

        // Update current step
        currentStepIndex = snapshot.stepIndex

        // Update Live Activity
        Task { await updateLiveActivity() }

        Haptics.light()

        AppLogger.general.info("🔄 Step changed from Live Activity: \(snapshot.stepIndex + 1)/\(self.totalSteps)")
    }

    // MARK: - Public Methods

    /// Start cooking a recipe
    @discardableResult
    func startCooking(_ recipe: Recipe) async -> CookModeStartOutcome {
        guard !recipe.steps.isEmpty else {
            AppLogger.general.warning("Cannot start Cook Mode for a recipe without steps")
            return .invalidRecipe
        }

        // Check if different recipe is already cooking
        if isActive, let current = currentRecipe, current.id != recipe.id {
            // Show conflict alert
            pendingRecipe = recipe
            showSessionConflictAlert = true
            return .conflict
        } else if isActive, currentRecipe?.id == recipe.id {
            showFullScreen = true
            return .alreadyActive
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
        return .started
    }

    /// Start cooking with pending recipe (after conflict resolution)
    func startPendingRecipe() async {
        guard let pending = pendingRecipe else { return }

        // End current session
        endSession()

        // Start new session
        _ = await startCooking(pending)

        // Clear pending
        pendingRecipe = nil
    }

    /// Navigate to next step
    func nextStep() {
        guard let recipe = currentRecipe, currentStepIndex < recipe.steps.count - 1,
              let snapshot = CookSessionSharedStore.move(by: 1, defaults: sharedDefaults) else {
            return
        }

        currentStepIndex = min(snapshot.stepIndex, recipe.steps.count - 1)

        // Update Live Activity
        Task { await updateLiveActivity() }

        Haptics.light()

        AppLogger.general.info("→ Next step: \(self.currentStepIndex + 1)/\(self.totalSteps)")
    }

    /// Navigate to previous step
    func previousStep() {
        guard currentStepIndex > 0,
              let snapshot = CookSessionSharedStore.move(by: -1, defaults: sharedDefaults) else { return }

        currentStepIndex = snapshot.stepIndex

        // Update Live Activity
        Task { await updateLiveActivity() }

        Haptics.light()

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
        let endedRecipeID = currentRecipe?.id

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

        // Stop all active timers and cancel their notifications
        dependencies.timerManager.stopAllTimers()

        // End CookSessionManager session (legacy support)
        Task {
            await dependencies.cookSessionManager.endSession()
        }

        // End Live Activity
        Task { await endLiveActivity(recipeID: endedRecipeID) }

        AppLogger.general.info("🛑 Ended cooking session: \(recipeName)")
    }

    /// Restore session from persistent storage
    func restoreState() async {
        // Check if we have a saved session
        guard let persisted = persistedSnapshot() else {
            // No saved cooking session to restore (routine)
            return
        }

        let recipeId = persisted.recipeID
        let stepIndex = persisted.stepIndex
        let sessionBeforeFetch = currentRecipe?.id

        // Fetch recipe from repository
        do {
            let fetchedRecipe = try await dependencies.recipeRepository.fetch(id: recipeId)

            // MainActor is reentrant while the repository fetch is suspended.
            // Never let an old restore overwrite a session started in the meantime.
            guard currentRecipe?.id == sessionBeforeFetch,
                  persistedSnapshot()?.recipeID == recipeId else {
                return
            }

            if let recipe = fetchedRecipe,
               !recipe.steps.isEmpty {
                // Restore session state
                currentRecipe = recipe
                currentStepIndex = min(max(stepIndex, 0), recipe.steps.count - 1)
                totalSteps = recipe.steps.count
                isActive = true

                sessionStartTime = persisted.sessionStartTime

                // Don't auto-show full screen - just show banner
                showFullScreen = false

                // Normalize the app-group state as well. Live Activity intents
                // read these values in another process and must not continue
                // using stale bounds after recipe steps change.
                saveState()
                await updateLiveActivity()

                AppLogger.general.info("✅ Restored cooking session: \(recipe.title) at step \(self.currentStepIndex + 1)")
            } else {
                // Recipe was deleted
                AppLogger.general.warning("⚠️ Recipe from saved session no longer exists")
                if isActive {
                    endSession()
                } else {
                    clearState()
                }
            }
        } catch {
            AppLogger.general.error("❌ Failed to restore cooking session: \(error.localizedDescription)")
            // Preserve both persisted and in-memory state on transient fetch
            // failures so a later foreground reconciliation can retry safely.
        }
    }

    /// Reconciles changes made by a Live Activity intent running in the widget
    /// process. NotificationCenter is process-local, so persisted app-group
    /// state is the authority when the app becomes active again.
    @discardableResult
    func reconcileExternalState() async -> Bool {
        guard let persisted = persistedSnapshot() else {
            if isActive {
                endSession()
            }
            return true
        }
        let recipeId = persisted.recipeID

        if currentRecipe?.id != recipeId || !isActive {
            await restoreState()
            return isActive && currentRecipe?.id == recipeId
        }

        guard let recipe = currentRecipe, !recipe.steps.isEmpty else {
            endSession()
            return false
        }

        let persistedStep = persisted.stepIndex
        let validatedStep = min(max(persistedStep, 0), recipe.steps.count - 1)
        guard validatedStep != currentStepIndex else { return true }

        currentStepIndex = validatedStep
        totalSteps = recipe.steps.count
        Task { await updateLiveActivity() }
        return true
    }

    // MARK: - Current Step Helpers

    /// Get the current step object
    var currentStep: CookStep? {
        guard let recipe = currentRecipe,
              currentStepIndex >= 0,
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

        if let synchronized = CookSessionSharedStore.synchronizeSession(
            recipeID: recipe.id,
            preferredStep: currentStepIndex,
            totalSteps: totalSteps,
            sessionStartTime: sessionStartTime ?? Date(),
            stepInstructions: recipe.steps.map(\.text),
            defaults: sharedDefaults
        ) {
            currentStepIndex = synchronized.stepIndex
        }

        AppLogger.general.debug("💾 Saved cook session state")
    }

    private func clearState() {
        sharedDefaults?.removeObject(forKey: "\(storageKey).recipeId")
        sharedDefaults?.removeObject(forKey: "\(storageKey).stepIndex")
        sharedDefaults?.removeObject(forKey: "\(storageKey).totalSteps")
        sharedDefaults?.removeObject(forKey: "\(storageKey).timestamp")
        CookSessionSharedStore.clear(defaults: sharedDefaults)

        AppLogger.general.debug("🗑️ Cleared cook session state")
    }

    private func persistedSnapshot() -> CookSessionSharedSnapshot? {
        if let snapshot = CookSessionSharedStore.read(defaults: sharedDefaults) {
            return snapshot
        }
        guard let recipeIdString = sharedDefaults?.string(forKey: "\(storageKey).recipeId"),
              let recipeID = UUID(uuidString: recipeIdString) else {
            return nil
        }
        let totalSteps = sharedDefaults?.integer(forKey: "\(storageKey).totalSteps") ?? 0
        guard totalSteps > 0 else { return nil }
        let stepIndex = sharedDefaults?.integer(forKey: "\(storageKey).stepIndex") ?? 0
        let timestamp = sharedDefaults?.double(forKey: "\(storageKey).timestamp") ?? 0
        return CookSessionSharedSnapshot(
            recipeID: recipeID,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            sessionStartTime: timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : Date()
        )
    }

    // MARK: - Live Activity Methods

    private func startLiveActivity() async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
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

        // Get shortest timer (running or paused)
        let shortestTimer = dependencies.timerManager.activeTimers
            .filter { $0.remainingSeconds() > 0 }
            .min(by: { $0.remainingSeconds() < $1.remainingSeconds() })

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerDurationSeconds: shortestTimer?.spec.seconds,
            primaryTimerIsRunning: shortestTimer?.isRunning ?? false,
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
        #endif
    }

    private func updateLiveActivity() async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard let recipe = currentRecipe else {
            return
        }
        let activity = currentActivity ?? Activity<CookModeActivityAttributes>.activities.first {
            $0.attributes.recipeId == recipe.id.uuidString
        }
        guard let activity else { return }
        currentActivity = activity

        // Get shortest timer (running or paused)
        let shortestTimer = dependencies.timerManager.activeTimers
            .filter { $0.remainingSeconds() > 0 }
            .min(by: { $0.remainingSeconds() < $1.remainingSeconds() })

        // Debug logging
        if dependencies.timerManager.activeTimers.isEmpty {
            AppLogger.general.debug("🔄 Updating Live Activity - No active timers")
        } else {
            AppLogger.general.debug("🔄 Updating Live Activity - \(dependencies.timerManager.activeTimers.count) timer(s)")
            if let timer = shortestTimer {
                let status = timer.isRunning ? "RUNNING" : "PAUSED"
                AppLogger.general.debug("   Primary timer: \(timer.spec.seconds)s total (\(status))")
            }
        }

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: currentStepIndex,
            totalSteps: totalSteps,
            stepInstruction: currentStep?.text ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerDurationSeconds: shortestTimer?.spec.seconds,
            primaryTimerIsRunning: shortestTimer?.isRunning ?? false,
            progressPercentage: progress,
            lastUpdated: Date()
        )

        await activity.update(
            .init(state: contentState, staleDate: nil)
        )
        AppLogger.general.debug("🔄 Updated Live Activity - Step \(currentStepIndex + 1)/\(totalSteps)")
        #endif
    }

    private func endLiveActivity(recipeID: UUID?) async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        let activities = Activity<CookModeActivityAttributes>.activities.filter { activity in
            if let recipeID {
                return activity.attributes.recipeId == recipeID.uuidString
            }
            return activity.id == currentActivity?.id
        }
        for activity in activities {
            await activity.end(
                .init(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }

        currentActivity = nil
        AppLogger.general.info("🛑 Ended Live Activity")
        #endif
    }

    /// Update Live Activity when timers change
    func updateLiveActivityForTimerChange() {
        guard isActive else { return }
        Task { await updateLiveActivity() }
    }
}
