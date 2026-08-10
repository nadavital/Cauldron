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

nonisolated enum CookSessionRecipePayloadCodec {
    static func encode(_ recipe: Recipe) -> Data? {
        try? JSONEncoder().encode(recipe)
    }

    static func decode(_ data: Data?, recipeID: UUID) -> Recipe? {
        guard let data,
              let recipe = try? JSONDecoder().decode(Recipe.self, from: data),
              recipe.id == recipeID else {
            return nil
        }
        return recipe
    }
}

@MainActor
@Observable
class CookModeCoordinator {

    // MARK: - Published State

    /// Whether cook mode is currently active
    var isActive: Bool = false {
        didSet {
            guard isActive != oldValue else { return }
            updateIdleTimer()
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

    /// The signed-in account that owns this cooking session. This is distinct
    /// from recipe ownership because shared recipes are cookable.
    private var sessionOwnerID: UUID?

    /// Show conflict alert when trying to start new recipe
    var showSessionConflictAlert: Bool = false
    var pendingRecipe: Recipe?

    /// Show toast when recipe is deleted during cooking
    var showRecipeDeletedToast: Bool = false

    // MARK: - Dependencies

    private let dependencies: DependencyContainer
    private let experiencePreferences: ExperiencePreferences
    private let idleTimerController: any IdleTimerControlling
    private var applicationIsActive: Bool
    private let storageKey = "activeCookSession"
    private let recipePayloadKey = "activeCookSession.recipePayload.v1"

    // Live Activity support
    #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    private var currentActivity: Activity<CookModeActivityAttributes>?
    #endif

    // Shared UserDefaults for App Group communication
    private let sharedDefaults = UserDefaults(suiteName: "group.Nadav.Cauldron")

    // MARK: - Initialization

    init(
        dependencies: DependencyContainer,
        experiencePreferences: ExperiencePreferences? = nil,
        idleTimerController: (any IdleTimerControlling)? = nil,
        applicationIsActive: Bool? = nil,
        observesApplicationLifecycle: Bool = true
    ) {
        self.dependencies = dependencies
        self.experiencePreferences = experiencePreferences ?? .shared
        self.idleTimerController = idleTimerController ?? ApplicationIdleTimerController()
        self.applicationIsActive = applicationIsActive ?? (UIApplication.shared.applicationState == .active)

        // Set up timer change callback
        dependencies.timerManager.onTimersChanged = { [weak self] in
            self?.updateLiveActivityForTimerChange()
        }
        if CookSessionSharedStore.read() == nil,
           !dependencies.timerManager.activeTimers.isEmpty {
            dependencies.timerManager.stopAllTimers()
        }

        if observesApplicationLifecycle {
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: UIApplication.didEnterBackgroundNotification
                ) {
                    self?.setApplicationActive(false)
                }
            }
            Task { @MainActor [weak self] in
                for await _ in NotificationCenter.default.notifications(
                    named: UIApplication.didBecomeActiveNotification
                ) {
                    self?.setApplicationActive(true)
                }
            }
        }
        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .experiencePreferencesChanged) {
                self?.updateIdleTimer()
            }
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

    /// Internal lifecycle seam used by application notifications and focused
    /// tests. Backgrounding always restores the system idle timer immediately.
    func setApplicationActive(_ active: Bool) {
        guard applicationIsActive != active else { return }
        applicationIsActive = active
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        idleTimerController.isIdleTimerDisabled = CookAwakePolicy.shouldDisableIdleTimer(
            sessionIsActive: isActive,
            applicationIsActive: applicationIsActive,
            keepScreenAwake: experiencePreferences.keepScreenAwake
        )
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

            // Show toast notification to user
            showRecipeDeletedToast = true
        }
    }

    /// Handle step change initiated from Live Activity
    private func handleStepChangeFromLiveActivity(snapshot: CookSessionSharedSnapshot) {
        guard isActive,
              let recipe = currentRecipe,
              snapshot.recipeID == recipe.id,
              snapshot.ownerID == sessionOwnerID,
              snapshot.ownerID == CurrentUserSession.shared.userId,
              snapshot.sessionStartTime == sessionStartTime,
              let latest = CookSessionSharedStore.read(defaults: sharedDefaults),
              latest.recipeID == snapshot.recipeID,
              latest.ownerID == snapshot.ownerID,
              latest.sessionStartTime == snapshot.sessionStartTime,
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
        guard let currentUserID = CurrentUserSession.shared.userId,
              !recipe.steps.isEmpty else {
            AppLogger.general.warning("Cannot start Cook Mode for a recipe without steps")
            return .invalidRecipe
        }

        if let sessionOwnerID, sessionOwnerID != currentUserID {
            endSession()
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
        sessionOwnerID = currentUserID
        isActive = true

        // Save state
        saveState()
        let startedSessionStartTime = sessionStartTime

        // Update CookSessionManager (legacy support)
        await dependencies.cookSessionManager.startSession(recipe: recipe)

        // MainActor methods are reentrant across the actor await above. Do not
        // resurrect UI or report success if this session ended or was replaced.
        guard matchesActiveSession(
            recipeID: recipe.id,
            ownerID: currentUserID,
            sessionStartTime: startedSessionStartTime
        ) else {
            await reconcileLegacySessionWithAuthority()
            return .invalidRecipe
        }

        // Show full screen cook mode
        showFullScreen = true

        // Start Live Activity
        await startLiveActivity()

        guard matchesActiveSession(
            recipeID: recipe.id,
            ownerID: currentUserID,
            sessionStartTime: startedSessionStartTime
        ) else {
            await reconcileLegacySessionWithAuthority()
            return .invalidRecipe
        }

        AppLogger.general.info("✅ Started cooking session: \(recipe.title)")
        return .started
    }

    /// Start cooking with pending recipe (after conflict resolution)
    @discardableResult
    func startPendingRecipe() async -> CookModeStartOutcome {
        guard let pending = pendingRecipe else { return .invalidRecipe }
        // Release only the request being confirmed before suspension. A newer
        // conflict arriving while startCooking awaits remains pending.
        pendingRecipe = nil

        // End current session
        endSession()

        // Start new session
        let outcome = await startCooking(pending)

        return outcome
    }

    /// Navigate to next step
    func nextStep() {
        guard isActive,
              let recipe = currentRecipe,
              let sessionOwnerID,
              sessionOwnerID == CurrentUserSession.shared.userId,
              let sessionStartTime,
              let expected = CookSessionSharedStore.read(defaults: sharedDefaults),
              expected.recipeID == recipe.id,
              expected.ownerID == sessionOwnerID,
              expected.sessionStartTime == sessionStartTime,
              expected.stepIndex < expected.totalSteps - 1,
              let snapshot = CookSessionSharedStore.move(
                by: 1,
                expected: expected,
                defaults: sharedDefaults
              ) else {
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
        guard isActive,
              let recipe = currentRecipe,
              let sessionOwnerID,
              sessionOwnerID == CurrentUserSession.shared.userId,
              let sessionStartTime,
              let expected = CookSessionSharedStore.read(defaults: sharedDefaults),
              expected.recipeID == recipe.id,
              expected.ownerID == sessionOwnerID,
              expected.sessionStartTime == sessionStartTime,
              expected.stepIndex > 0,
              let snapshot = CookSessionSharedStore.move(
                by: -1,
                expected: expected,
                defaults: sharedDefaults
              ) else { return }

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
        let recipeName = currentRecipe?.title ?? "Unknown"
        let persisted = persistedSnapshot()
        let endedRecipeID = currentRecipe?.id ?? persisted?.recipeID
        let endedSessionStartTime = sessionStartTime ?? persisted?.sessionStartTime

        // Batch all state changes together to prevent cascading view updates
        withAnimation(.easeInOut(duration: 0.2)) {
            isActive = false
            showFullScreen = false
            currentRecipe = nil
            currentStepIndex = 0
            totalSteps = 0
            sessionStartTime = nil
            sessionOwnerID = nil
        }

        // Clear persisted state
        clearState()

        // Stop all active timers and cancel their notifications
        dependencies.timerManager.stopAllTimers()

        // End CookSessionManager session (legacy support)
        Task { [weak self] in
            guard let self else { return }
            await dependencies.cookSessionManager.endSession()
            await reconcileLegacySessionWithAuthority()
        }

        // End Live Activity
        Task {
            await endLiveActivity(
                recipeID: endedRecipeID,
                sessionStartTime: endedSessionStartTime
            )
        }

        AppLogger.general.info("🛑 Ended cooking session: \(recipeName)")
    }

    /// Restore session from persistent storage
    func restoreState() async {
        // Check if we have a saved session
        guard let persisted = persistedSnapshot() else {
            // No saved cooking session to restore (routine)
            await endLiveActivity(recipeID: nil, sessionStartTime: nil)
            return
        }

        guard let currentUserID = CurrentUserSession.shared.userId,
              persisted.belongs(to: currentUserID) else {
            endSession()
            return
        }

        let recipeId = persisted.recipeID
        let stepIndex = persisted.stepIndex
        let sessionBeforeFetch = currentRecipe?.id

        // Fetch recipe from repository
        do {
            let cachedRecipe = persistedRecipePayload(recipeID: recipeId)
            let restoredRecipe: Recipe?
            do {
                if let fetchedRecipe = try await dependencies.recipeRepository.fetch(id: recipeId) {
                    restoredRecipe = fetchedRecipe
                } else if let cachedRecipe,
                          cachedRecipe.isPreview || cachedRecipe.ownerId != currentUserID {
                    // Public/shared recipes are intentionally session-cached
                    // because they are not members of the owner's repository.
                    restoredRecipe = cachedRecipe
                } else {
                    // A successful miss for an owned recipe is a deletion.
                    restoredRecipe = nil
                }
            } catch {
                guard let cachedRecipe else { throw error }
                restoredRecipe = cachedRecipe
            }

            // MainActor is reentrant while the repository fetch is suspended.
            // Never let an old restore overwrite a session started in the meantime.
            guard currentRecipe?.id == sessionBeforeFetch,
                  persistedSnapshot() == persisted,
                  CurrentUserSession.shared.userId == currentUserID else {
                return
            }

            if let recipe = restoredRecipe, !recipe.steps.isEmpty {
                // Restore session state
                currentRecipe = recipe
                currentStepIndex = min(max(stepIndex, 0), recipe.steps.count - 1)
                totalSteps = recipe.steps.count
                isActive = true

                sessionStartTime = persisted.sessionStartTime
                sessionOwnerID = currentUserID

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
                // Clear every session-owned resource, including timers and a
                // stale Live Activity, even during a cold inactive restore.
                endSession()
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
            await endLiveActivity(recipeID: nil, sessionStartTime: nil)
            return true
        }

        guard let currentUserID = CurrentUserSession.shared.userId,
              persisted.belongs(to: currentUserID) else {
            endSession()
            return false
        }
        let recipeId = persisted.recipeID

        if currentRecipe?.id != recipeId
            || sessionStartTime != persisted.sessionStartTime
            || sessionOwnerID != currentUserID
            || !isActive {
            await restoreState()
            return isActive
                && currentRecipe?.id == recipeId
                && sessionOwnerID == currentUserID
                && sessionStartTime == persisted.sessionStartTime
        }

        guard let recipe = currentRecipe,
              sessionOwnerID == currentUserID,
              !recipe.steps.isEmpty else {
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
        guard let recipe = currentRecipe,
              let sessionOwnerID else {
            clearState()
            return
        }

        sharedDefaults?.set(recipe.id.uuidString, forKey: "\(storageKey).recipeId")
        sharedDefaults?.set(currentStepIndex, forKey: "\(storageKey).stepIndex")
        sharedDefaults?.set(totalSteps, forKey: "\(storageKey).totalSteps")
        sharedDefaults?.set(Date().timeIntervalSince1970, forKey: "\(storageKey).timestamp")
        if let payload = CookSessionRecipePayloadCodec.encode(recipe) {
            sharedDefaults?.set(payload, forKey: recipePayloadKey)
        }

        if let synchronized = CookSessionSharedStore.synchronizeSession(
            recipeID: recipe.id,
            ownerID: sessionOwnerID,
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
        sharedDefaults?.removeObject(forKey: recipePayloadKey)
        CookSessionSharedStore.clear(defaults: sharedDefaults)

        AppLogger.general.debug("🗑️ Cleared cook session state")
    }

    private func persistedSnapshot() -> CookSessionSharedSnapshot? {
        CookSessionSharedStore.read(defaults: sharedDefaults)
    }

    private func persistedRecipePayload(recipeID: UUID) -> Recipe? {
        CookSessionRecipePayloadCodec.decode(
            sharedDefaults?.data(forKey: recipePayloadKey),
            recipeID: recipeID
        )
    }

    private func matchesActiveSession(
        recipeID: UUID,
        ownerID: UUID,
        sessionStartTime: Date?
    ) -> Bool {
        guard isActive,
              CurrentUserSession.shared.userId == ownerID,
              sessionOwnerID == ownerID,
              currentRecipe?.id == recipeID,
              self.sessionStartTime == sessionStartTime,
              let snapshot = persistedSnapshot() else {
            return false
        }
        return snapshot.recipeID == recipeID
            && snapshot.ownerID == ownerID
            && snapshot.sessionStartTime == sessionStartTime
    }

    private func reconcileLegacySessionWithAuthority() async {
        while true {
            if let recipe = currentRecipe,
               let ownerID = sessionOwnerID,
               let sessionStartTime,
               matchesActiveSession(
                recipeID: recipe.id,
                ownerID: ownerID,
                sessionStartTime: sessionStartTime
               ) {
                await dependencies.cookSessionManager.startSession(recipe: recipe)
                if matchesActiveSession(
                    recipeID: recipe.id,
                    ownerID: ownerID,
                    sessionStartTime: sessionStartTime
                ) {
                    return
                }
            } else {
                await dependencies.cookSessionManager.endSession()
                guard let recipe = currentRecipe,
                      let ownerID = sessionOwnerID,
                      let sessionStartTime,
                      matchesActiveSession(
                        recipeID: recipe.id,
                        ownerID: ownerID,
                        sessionStartTime: sessionStartTime
                      ) else {
                    return
                }
            }
        }
    }

    // MARK: - Live Activity Methods

    private func startLiveActivity() async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard let recipe = currentRecipe,
              let sessionStartTime,
              let currentUserID = CurrentUserSession.shared.userId,
              sessionOwnerID == currentUserID,
              let expectedSnapshot = CookSessionSharedStore.read(defaults: sharedDefaults),
              expectedSnapshot.recipeID == recipe.id,
              expectedSnapshot.ownerID == currentUserID,
              expectedSnapshot.sessionStartTime == sessionStartTime,
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        let attributes = CookModeActivityAttributes(
            recipeId: recipe.id.uuidString,
            recipeName: recipe.title,
            recipeEmoji: nil, // Recipe model doesn't have emoji - using Cauldron icon from assets
            sessionStartTime: sessionStartTime
        )

        // Get shortest timer (running or paused)
        let shortestTimer = dependencies.timerManager.activeTimers
            .filter { $0.remainingSeconds() > 0 }
            .min(by: { $0.remainingSeconds() < $1.remainingSeconds() })

        let contentState = CookModeActivityAttributes.ContentState(
            currentStep: expectedSnapshot.stepIndex,
            totalSteps: expectedSnapshot.totalSteps,
            stepInstruction: expectedSnapshot.stepInstructions.flatMap {
                $0.indices.contains(expectedSnapshot.stepIndex) ? $0[expectedSnapshot.stepIndex] : nil
            } ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerDurationSeconds: shortestTimer?.spec.seconds,
            primaryTimerIsRunning: shortestTimer?.isRunning ?? false,
            progressPercentage: Double(expectedSnapshot.stepIndex + 1) / Double(expectedSnapshot.totalSteps),
            lastUpdated: Date()
        )

        do {
            let requestedActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil)
            )
            guard isActive,
                  CurrentUserSession.shared.userId == currentUserID,
                  currentRecipe?.id == recipe.id,
                  sessionOwnerID == currentUserID,
                  self.sessionStartTime == sessionStartTime,
                  let latestSnapshot = CookSessionSharedStore.read(defaults: sharedDefaults),
                  latestSnapshot.recipeID == expectedSnapshot.recipeID,
                  latestSnapshot.ownerID == expectedSnapshot.ownerID,
                  latestSnapshot.sessionStartTime == expectedSnapshot.sessionStartTime else {
                await requestedActivity.end(
                    .init(state: contentState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                return
            }
            currentActivity = requestedActivity
            if latestSnapshot.revision != expectedSnapshot.revision {
                await updateLiveActivity()
            }
            AppLogger.general.info("✅ Started Live Activity")
        } catch {
            AppLogger.general.error("❌ Failed to start Live Activity: \(error.localizedDescription)")
        }
        #endif
    }

    private func updateLiveActivity() async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard let recipe = currentRecipe,
              let sessionStartTime,
              let currentUserID = CurrentUserSession.shared.userId,
              sessionOwnerID == currentUserID,
              let snapshot = CookSessionSharedStore.read(defaults: sharedDefaults),
              snapshot.recipeID == recipe.id,
              snapshot.ownerID == currentUserID,
              snapshot.sessionStartTime == sessionStartTime else {
            return
        }
        currentStepIndex = snapshot.stepIndex
        totalSteps = snapshot.totalSteps
        let matchesSession: (Activity<CookModeActivityAttributes>) -> Bool = {
            $0.attributes.recipeId == recipe.id.uuidString
                && $0.attributes.sessionStartTime == sessionStartTime
        }
        let activity = currentActivity.flatMap { matchesSession($0) ? $0 : nil }
            ?? Activity<CookModeActivityAttributes>.activities.first {
                matchesSession($0)
            }
        guard let activity else {
            currentActivity = nil
            return
        }
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
            currentStep: snapshot.stepIndex,
            totalSteps: snapshot.totalSteps,
            stepInstruction: snapshot.stepInstructions.flatMap {
                $0.indices.contains(snapshot.stepIndex) ? $0[snapshot.stepIndex] : nil
            } ?? "",
            activeTimerCount: dependencies.timerManager.activeTimers.count,
            primaryTimerDurationSeconds: shortestTimer?.spec.seconds,
            primaryTimerIsRunning: shortestTimer?.isRunning ?? false,
            progressPercentage: Double(snapshot.stepIndex + 1) / Double(snapshot.totalSteps),
            lastUpdated: Date()
        )

        await activity.update(
            .init(state: contentState, staleDate: nil)
        )
        if let latest = CookSessionSharedStore.read(defaults: sharedDefaults),
           latest.recipeID == snapshot.recipeID,
           latest.ownerID == snapshot.ownerID,
           latest.sessionStartTime == snapshot.sessionStartTime,
           latest.revision != snapshot.revision {
            await CookSessionLiveActivityUpdater.update(from: latest)
        }
        AppLogger.general.debug("🔄 Updated Live Activity - Step \(snapshot.stepIndex + 1)/\(snapshot.totalSteps)")
        #endif
    }

    private func endLiveActivity(recipeID: UUID?, sessionStartTime: Date?) async {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        let isBulkOrphanCleanup = recipeID == nil && sessionStartTime == nil
        let isAuthoritative: (Activity<CookModeActivityAttributes>) -> Bool = { activity in
            guard isBulkOrphanCleanup,
                  let userID = CurrentUserSession.shared.userId,
                  let snapshot = CookSessionSharedStore.read(defaults: self.sharedDefaults),
                  snapshot.belongs(to: userID) else {
                return false
            }
            return activity.attributes.recipeId == snapshot.recipeID.uuidString
                && activity.attributes.sessionStartTime == snapshot.sessionStartTime
        }
        let activities = Activity<CookModeActivityAttributes>.activities.filter { activity in
            if let recipeID, let sessionStartTime {
                return activity.attributes.recipeId == recipeID.uuidString
                    && activity.attributes.sessionStartTime == sessionStartTime
            }
            // With no authoritative session identity (for example after
            // rejecting a pre-owner snapshot), every Cook Mode activity is an
            // orphan and must be removed before a new session can begin.
            if isBulkOrphanCleanup {
                return !isAuthoritative(activity)
            }
            return activity.id == currentActivity?.id
        }
        var endedActivityIDs = Set<String>()
        for activity in activities {
            // Authority is cross-process and may appear after enumeration.
            guard !isAuthoritative(activity) else { continue }
            await activity.end(
                .init(state: activity.content.state, staleDate: nil),
                dismissalPolicy: .immediate
            )
            endedActivityIDs.insert(activity.id)
        }

        if let currentActivity, endedActivityIDs.contains(currentActivity.id) {
            self.currentActivity = nil
        }
        AppLogger.general.info("🛑 Ended Live Activity")
        #endif
    }

    /// Update Live Activity when timers change
    func updateLiveActivityForTimerChange() {
        guard isActive else { return }
        Task { await updateLiveActivity() }
    }
}
