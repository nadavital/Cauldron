//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import CloudKit
import os

/// Preloaded data to pass to view models
/// CRITICAL: This structure is the key to preventing empty state flash!
/// By loading ALL data BEFORE showing the UI and passing them directly to view models,
/// we ensure the view never renders with empty arrays.
struct PreloadedRecipeData {
    let allRecipes: [Recipe]           // All recipes (owned + referenced) loaded from storage
    let recentlyCookedIds: [UUID]      // IDs of recently cooked recipes for quick filtering
    let collections: [Collection]      // All collections loaded from storage
}

struct ImportContext: Identifiable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    // MARK: - What's New Content Versioning
    // Only update this when you have NEW FEATURES to announce.
    // This is separate from the build number - the app can have multiple builds without triggering What's New.
    // When you ship a feature update, set this to match that version (e.g., "1.4.1").
    // When you ship a bug fix, leave this unchanged so no splash appears.
    /// Independent content gate so material release-note changes can be shown
    /// even when they ship within the same marketing version.
    static let whatsNewContentVersion = "1.8.2"

    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var isDataReady = false
    @State private var preloadedData: PreloadedRecipeData?
    @State private var loadedUserId: UUID?
    @State private var sessionReloadTask: Task<Void, Never>?
    @State private var backgroundMaintenanceTask: Task<Void, Never>?
    @State private var backgroundWarmupTask: Task<Void, Never>?
    @State private var sharedContentWrapper: SharedContentWrapper?
    @State private var isLoadingShare = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""
    @State private var activeShareURL: URL?
    @State private var suppressLaunchSheetsForIncomingLink = false
    @State private var showPersistenceRecovery = false

    // Splash screen state
    @AppStorage("whatsNewLastSeenContentVersion") private var whatsNewLastSeenContentVersion = ""
    @AppStorage("hasSeenWelcomeScreen") private var hasSeenWelcomeScreen = false
    @State private var showWhatsNew = false
    @State private var showWelcome = false

    struct SharedContentWrapper: Identifiable {
        let id = UUID()
        let content: ImportedContent
    }

    var body: some View {
        ZStack {
            // Main content
            Group {
                // CRITICAL: Only show UI when BOTH conditions are met:
                // 1. userSession.isInitialized - User authentication is complete
                // 2. isDataReady - Recipe data has been preloaded
                // This prevents the empty state flash by ensuring data exists before rendering CookTabView
                if userSession.isInitialized && isDataReady {
                    if userSession.needsiCloudSignIn, let accountStatus = userSession.cloudKitAccountStatus {
                        // Show iCloud sign-in prompt
                        iCloudSignInPromptView(
                            accountStatus: accountStatus,
                            onRetry: {
                                // Re-check iCloud status
                                await userSession.initialize(dependencies: dependencies)
                            }
                        )
                    } else if userSession.needsOnboarding || RuntimeEnvironment.shouldForceOnboarding {
                        // Show onboarding for new users (or when previewing via launch flag)
                        OnboardingView(dependencies: dependencies) {
                            // Onboarding completed, will trigger view update
                        }
                    } else {
                        if Self.shouldRenderMainTab(
                            isInitialized: userSession.isInitialized,
                            isDataReady: isDataReady,
                            loadedUserId: loadedUserId,
                            currentUserId: userSession.userId
                        ) {
                            // Only render account-owned data after its owner matches the verified session.
                        #if DEBUG
                        if let scene = RuntimeEnvironment.screenshotScene {
                            ScreenshotSceneView(
                                scene: scene,
                                dependencies: dependencies,
                                preloadedData: preloadedData
                            )
                            .id(userSession.userId)
                        } else {
                            MainTabView(
                                dependencies: dependencies,
                                preloadedData: preloadedData,
                                pendingSharedContent: $sharedContentWrapper
                            )
                            .id(userSession.userId)
                        }
                        #else
                        MainTabView(
                            dependencies: dependencies,
                            preloadedData: preloadedData,
                            pendingSharedContent: $sharedContentWrapper
                        )
                        .id(userSession.userId)
                        #endif
                        } else {
                            Color.appBackground
                                .ignoresSafeArea()
                        }
                    }
                }
            }
            .opacity(isDataReady ? 1 : 0)

            // OPTIMIZATION: Show loading overlay to prevent white screen
            // This appears immediately when ContentView loads, before data is ready
            // It uses the same background color as the system, creating a seamless transition
            // from the iOS launch screen
            if !isDataReady {
                Color.appBackground
                    .ignoresSafeArea()
            }
            
            // Share Loading Overlay
            if isLoadingShare {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Loading shared content...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Material.ultraThinMaterial)
                    .cornerRadius(16)
                }
            }
            }
            
            // Share Error Alert
            .alert("Cannot Open Link", isPresented: $showShareError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(shareErrorMessage)
            }
            .alert("Local Library Recovered", isPresented: $showPersistenceRecovery) {
                Button("Continue", role: .cancel) { }
            } message: {
                Text("Cauldron preserved the unreadable local database and created a clean one. Synced recipes will return from iCloud; recent offline changes remain in the recovery backup.")
            }
            .onAppear {
                showPersistenceRecovery = dependencies.persistenceRecoveryReport != nil
            }
            .sheet(isPresented: $showWhatsNew) {
                WhatsNewView {
                    whatsNewLastSeenContentVersion = Self.whatsNewContentVersion
                    showWhatsNew = false
                }
            }
            .sheet(isPresented: $showWelcome) {
                WelcomeView {
                    hasSeenWelcomeScreen = true
                    showWelcome = false
                }
            }
        .animation(.easeInOut(duration: 0.25), value: isDataReady)
        .animation(.easeInOut(duration: 0.2), value: isLoadingShare)
        .onReceive(NotificationCenter.default.publisher(for: .openExternalShare)) { notification in
            AppLogger.general.info("🔔 ContentView: Received OpenExternalShare notification")
            if let url = notification.object as? URL {
                AppLogger.general.info("🔔 ContentView: Loading share from URL: \(url)")
                openIncomingShare(url)
            }
        }
        .task {
            // CRITICAL LOADING SEQUENCE:
            // Step 1: Initialize user session (determines which view to show)
            await userSession.ensureInitialized(dependencies: dependencies)
            await RecipeIntentDonation.reconcileAccountBoundary(
                currentOwnerID: userSession.userId
            )
            RecipeSpotlightIndexer.shared.scheduleAccountBoundaryReconciliation()

            #if DEBUG
            if RuntimeEnvironment.isSimulatorQAMode {
                await SimulatorQASeed.seedIfNeeded(dependencies: dependencies)
            }
            #endif

            // Step 2: Preload ALL recipe data BEFORE showing UI
            // This is the key to preventing empty state flash - we load everything
            // synchronously before setting isDataReady = true
            if let userId = userSession.userId {
                preloadedData = await performInitialLoad(for: userId)
                loadedUserId = userId
            } else {
                loadedUserId = nil
            }

            // Step 3: Restore cook mode session if exists
            await dependencies.cookModeCoordinator.restoreState()

            // Step 4: Signal that we're ready to show UI with populated data
            // Only NOW will the view hierarchy render, and CookTabViewModel will
            // receive preloadedData in its initializer, preventing empty arrays
            isDataReady = true
            RecipeSpotlightIndexer.shared.scheduleReconciliation(
                preloadedRecipes: preloadedData?.allRecipes
            )

            // Step 5: Check for pending share URL from PendingShareManager
            // This handles cold-start scenarios where the app was opened via Universal Link
            let pendingURL = await PendingShareManager.shared.peekPendingURL()
            if let pendingURL {
                AppLogger.general.info("🔔 ContentView: Found pending share URL from cold start: \(pendingURL)")
                openIncomingShare(pendingURL)
            }

            if Self.shouldPresentLaunchSplash(
                hasPendingExternalShare: pendingURL != nil,
                isRoutingExternalShare: activeShareURL != nil || suppressLaunchSheetsForIncomingLink
            ) {
                maybeShowSplashScreen()
            }
        }
        .onChange(of: userSession.isInitialized) { _, _ in
            // A live CloudKit account change locks the session before replacing
            // its user ID. Those intermediate ID changes are intentionally
            // ignored; once verification completes, rebuild the preload boundary
            // for the newly verified account (including the signed-out case).
            scheduleSessionReloadIfNeeded()
            maybeShowSplashScreen()
        }
        .onChange(of: userSession.userId) { oldUserId, newUserId in
            guard userSession.isInitialized,
                  isDataReady,
                  oldUserId != newUserId else {
                return
            }

            sessionReloadTask?.cancel()
            sessionReloadTask = Task {
                await handleSessionChange(to: newUserId)
            }
        }
        .onChange(of: userSession.needsOnboarding) { _, _ in
            scheduleSessionReloadIfNeeded()
            maybeShowSplashScreen()
        }
        .onChange(of: userSession.needsiCloudSignIn) { _, _ in
            scheduleSessionReloadIfNeeded()
            maybeShowSplashScreen()
        }
        .onChange(of: isDataReady) { _, _ in
            maybeShowSplashScreen()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard Self.shouldRetryPendingShare(
                scenePhase: newPhase,
                isDataReady: isDataReady,
                hasActiveShare: activeShareURL != nil
            ) else { return }
            retryPendingShareIfNeeded()
        }
    }

    @MainActor
    private func handleSessionChange(to userId: UUID?) async {
        resetSessionScopedState()
        await RecipeIntentDonation.reconcileAccountBoundary(currentOwnerID: userId)
        RecipeSpotlightIndexer.shared.scheduleAccountBoundaryReconciliation()

        dependencies.connectionManager.resetSessionState()
        FriendsTabViewModel.shared.resetSessionState()
        await dependencies.sharingService.resetSharedRecipeCache()

        guard let userId,
              !userSession.needsOnboarding,
              !userSession.needsiCloudSignIn else {
            loadedUserId = nil
            isDataReady = true
            maybeShowSplashScreen()
            return
        }

        preloadedData = await performInitialLoad(for: userId)
        guard !Task.isCancelled, userSession.userId == userId else { return }

        loadedUserId = userId
        isDataReady = true
        RecipeSpotlightIndexer.shared.scheduleReconciliation(
            preloadedRecipes: preloadedData?.allRecipes
        )
        maybeShowSplashScreen()
    }

    @MainActor
    private func scheduleSessionReloadIfNeeded() {
        let userId = userSession.userId
        guard Self.shouldReloadSession(
            isInitialized: userSession.isInitialized,
            isDataReady: isDataReady,
            loadedUserId: loadedUserId,
            currentUserId: userId
        ) else {
            return
        }

        sessionReloadTask?.cancel()
        sessionReloadTask = Task {
            await handleSessionChange(to: userId)
        }
    }

    nonisolated static func shouldReloadSession(
        isInitialized: Bool,
        isDataReady: Bool,
        loadedUserId: UUID?,
        currentUserId: UUID?
    ) -> Bool {
        isInitialized && isDataReady && loadedUserId != currentUserId
    }

    nonisolated static func shouldRenderMainTab(
        isInitialized: Bool,
        isDataReady: Bool,
        loadedUserId: UUID?,
        currentUserId: UUID?
    ) -> Bool {
        guard isInitialized,
              isDataReady,
              let currentUserId else {
            return false
        }
        return loadedUserId == currentUserId
    }

    @MainActor
    private func resetSessionScopedState() {
        // Cook Mode owns account-scoped recipe data, timers, and a Live
        // Activity. Tear it down synchronously at the account boundary so the
        // prior user's session cannot remain visible during the reload.
        dependencies.cookModeCoordinator.endSession()
        backgroundMaintenanceTask?.cancel()
        backgroundMaintenanceTask = nil
        backgroundWarmupTask?.cancel()
        backgroundWarmupTask = nil
        isDataReady = false
        preloadedData = nil
        loadedUserId = nil
        isLoadingShare = false
        showShareError = false
        shareErrorMessage = ""
        dependencies.libraryPresentationStore.clear()
    }

    private func maybeShowSplashScreen() {
        guard !suppressLaunchSheetsForIncomingLink,
              activeShareURL == nil else {
            return
        }
        if RuntimeEnvironment.shouldForceWhatsNew,
           userSession.isInitialized,
           isDataReady,
           !showWhatsNew,
           !showWelcome {
            showWhatsNew = true
            return
        }

        // Don't show any splash if not ready or already showing one
        guard userSession.isInitialized,
              isDataReady,
              !userSession.needsOnboarding,
              !userSession.needsiCloudSignIn,
              !showWhatsNew,
              !showWelcome else {
            return
        }

        // Migration: Existing users (hasLaunchedBefore = true) should NOT see the Welcome screen.
        // If they haven't seen any splash under the new system, mark Welcome as seen.
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if hasLaunchedBefore && !hasSeenWelcomeScreen {
            // Existing user upgrading - skip Welcome screen, mark it as seen
            hasSeenWelcomeScreen = true
        }

        // Priority 1: Welcome screen for brand new users who haven't seen it yet
        if !RuntimeEnvironment.isSimulatorQAMode && !hasSeenWelcomeScreen {
            showWelcome = true
            return
        }

        // Priority 2: What's New for existing users when content version changes
        let forceShow = Bundle.main.object(forInfoDictionaryKey: "WhatsNewForceShow") as? Bool == true
        if !RuntimeEnvironment.isSimulatorQAMode &&
            (forceShow || whatsNewLastSeenContentVersion != Self.whatsNewContentVersion) {
            showWhatsNew = true
        }
    }

    @MainActor
    private func openIncomingShare(_ url: URL) {
        suppressLaunchSheetsForIncomingLink = true
        dismissLaunchSheetsForIncomingLink()
        guard activeShareURL == nil else { return }
        activeShareURL = url
        Task {
            await loadSharedContent(url: url)
        }
    }

    private func loadSharedContent(url: URL) async {
        isLoadingShare = true
        defer {
            isLoadingShare = false
            activeShareURL = nil
            Task {
                guard let nextURL = await PendingShareManager.shared.peekPendingURL(),
                      nextURL != url else { return }
                await MainActor.run {
                    openIncomingShare(nextURL)
                }
            }
        }
        
        do {
            let content = try await dependencies.externalShareService.importFromShareURL(url)
            
            // If it's a recipe, we need to fetch the full details
            // because the share data only contains a summary
            if case .recipe(let partialRecipe, let owner) = content {
                AppLogger.general.info("🌐 ContentView: Processing recipe share for \(partialRecipe.title)")

                // 1. Check if we already have this recipe locally (e.g. we are the owner)
                // This prevents fetching a stale public version if we just made it private
                if let localRecipe = try? await dependencies.recipeRepository.fetch(id: partialRecipe.id),
                   localRecipe.ownerId == userSession.userId,
                   !localRecipe.isPreview {
                    AppLogger.general.info("✅ ContentView: Found local copy of recipe, using that")
                    await MainActor.run {
                        let wrapper = SharedContentWrapper(content: .recipe(localRecipe, originalCreator: owner))
                        sharedContentWrapper = wrapper
                    }
                    await PendingShareManager.shared.clearPendingURL(matching: url)
                    return
                }

                // 2. If not found locally, fetch from CloudKit public database
                AppLogger.general.info("🌐 ContentView: Fetching full recipe details from CloudKit")
                if let fullRecipe = try await dependencies.recipeDiscoveryCache.fetchPublicRecipe(id: partialRecipe.id) {
                    AppLogger.general.info("✅ ContentView: Successfully fetched full recipe")
                    await MainActor.run {
                        // Post notification to navigate to the recipe in the Search tab
                        // Use the full recipe but keep the owner info from the share if available
                        let wrapper = SharedContentWrapper(content: .recipe(fullRecipe, originalCreator: owner))
                        sharedContentWrapper = wrapper
                    }
                    await PendingShareManager.shared.clearPendingURL(matching: url)
                } else {
                    AppLogger.general.error("❌ ContentView: Recipe not found in public database")
                    // CRITICAL: Do NOT fallback to partial recipe. If it's not in public DB, it's private or deleted.
                    await MainActor.run {
                        shareErrorMessage = "This recipe is no longer available or has been made private."
                        showShareError = true
                    }
                    await PendingShareManager.shared.clearPendingURL(matching: url)
                }
            } else {
                // For profiles and collections, the share data is usually sufficient or handled differently
                await MainActor.run {
                    let wrapper = SharedContentWrapper(content: content)
                    sharedContentWrapper = wrapper
                }
                await PendingShareManager.shared.clearPendingURL(matching: url)
            }
        } catch {
            AppLogger.general.error("❌ ContentView: Failed to load shared content: \(error)")
            await MainActor.run {
                shareErrorMessage = "Failed to load shared content. The link may be invalid or expired."
                showShareError = true
            }
            if !Self.isTransientShareError(error) {
                await PendingShareManager.shared.clearPendingURL(matching: url)
            }
        }
    }

    nonisolated static func shouldPresentLaunchSplash(
        hasPendingExternalShare: Bool,
        isRoutingExternalShare: Bool
    ) -> Bool {
        !hasPendingExternalShare && !isRoutingExternalShare
    }

    nonisolated static func isTransientShareError(_ error: Error) -> Bool {
        if let shareError = error as? ExternalShareError {
            switch shareError {
            case .networkError(let underlyingError):
                return isTransientNetworkError(underlyingError)
            case .temporarilyUnavailable:
                return true
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            return isTransientURLError(urlError)
        }
        guard let cloudError = error as? CKError else { return false }
        switch cloudError.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .requestRateLimited,
             .zoneBusy,
             .serverResponseLost:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldRetryPendingShare(
        scenePhase: ScenePhase,
        isDataReady: Bool,
        hasActiveShare: Bool
    ) -> Bool {
        scenePhase == .active && isDataReady && !hasActiveShare
    }

    nonisolated private static func isTransientNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isTransientURLError(urlError)
        }
        if let cloudError = error as? CKError {
            return isTransientShareError(cloudError)
        }
        return false
    }

    nonisolated private static func isTransientURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    @MainActor
    private func retryPendingShareIfNeeded() {
        Task {
            guard let pendingURL = await PendingShareManager.shared.peekPendingURL() else {
                return
            }
            await MainActor.run {
                guard Self.shouldRetryPendingShare(
                    scenePhase: scenePhase,
                    isDataReady: isDataReady,
                    hasActiveShare: activeShareURL != nil
                ) else { return }
                AppLogger.general.info("🔔 ContentView: Retrying pending share after activation: \(pendingURL)")
                openIncomingShare(pendingURL)
            }
        }
    }

    @MainActor
    private func dismissLaunchSheetsForIncomingLink() {
        showWhatsNew = false
        showWelcome = false
    }

    private func performInitialLoad(for userId: UUID) async -> PreloadedRecipeData? {
        // Preload ALL data that will be needed by the main view
        do {
            // IMPORTANT: On first app launch (or after reinstall), we need to sync from CloudKit FIRST
            // to download recipe images before showing the UI. On subsequent launches, we can skip
            // the initial sync and just show local data immediately (images already downloaded).
            let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

            if !hasLaunchedBefore {
                // The launch marker controls one-time presentation only. CloudKit
                // hydration and repair work happens after local content is visible.
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }

            // OPTIMIZATION: Parallelize independent data fetches using async let
            async let ownedRecipes = dependencies.recipeRepository.fetchLibraryRecipes(ownerId: userId)
            async let cookingHistory = dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            async let localCollections = dependencies.collectionRepository.fetchUserCollections(ownerId: userId)

            // Wait for all to complete in parallel
            let allRecipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await ownedRecipes,
                currentUserId: userId
            )
            let recentlyCookedIds = try await cookingHistory
            let collections = try await localCollections
            // Data preloaded successfully (don't log routine operations)

            scheduleBackgroundMaintenance(for: userId)
            scheduleBackgroundWarmup(for: userId)

            return PreloadedRecipeData(allRecipes: allRecipes, recentlyCookedIds: recentlyCookedIds, collections: collections)
        } catch {
            AppLogger.general.warning("Data preload failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func scheduleBackgroundMaintenance(for userId: UUID) {
        let recipeRepository = dependencies.recipeRepository
        let recipeSyncService = dependencies.recipeSyncService

        backgroundMaintenanceTask?.cancel()
        backgroundMaintenanceTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            guard await MainActor.run(body: { CurrentUserSession.shared.userId == userId }) else {
                return
            }

            // Repair passes are deliberately off the readiness path. They are
            // idempotent and run serially to avoid competing SwiftData contexts.
            do {
                try await recipeRepository.migrateRecipeOwnership(currentUserId: userId)
                try await recipeRepository.fixCorruptedImageFilenames()
                _ = try await recipeRepository.removeDuplicateRecipes()
                _ = try await recipeRepository.removeSelfSavedRecipeCopies(currentUserId: userId)
            } catch {
                AppLogger.general.warning("Background library maintenance failed: \(error.localizedDescription)")
            }

            guard !Task.isCancelled,
                  await MainActor.run(body: { CurrentUserSession.shared.userId == userId }) else {
                return
            }

            await recipeRepository.migratePublicRecipesToPublicDatabase()
            await recipeRepository.migratePublicRecipeSearchMetadata()

            guard !Task.isCancelled,
                  await MainActor.run(body: {
                      CurrentUserSession.shared.userId == userId &&
                      CurrentUserSession.shared.isCloudSyncAvailable
                  }) else {
                return
            }

            do {
                try await recipeSyncService.performFullSync(for: userId)
            } catch {
                AppLogger.general.warning("Background sync failed: \(error.localizedDescription)")
            }
        }
    }

    private func scheduleBackgroundWarmup(for userId: UUID) {
        let sharingService = dependencies.sharingService
        let connectionCloudService = dependencies.connectionCloudService
        let userCloudService = dependencies.userCloudService
        let sharingRepository = dependencies.sharingRepository
        let profileImageManager = dependencies.profileImageManager

        backgroundWarmupTask?.cancel()
        backgroundWarmupTask = Task.detached(priority: .background) {
            // Let the local UI settle and give higher-priority sync/maintenance
            // work the first opportunity to finish before speculative prefetch.
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }

            guard await MainActor.run(body: { CurrentUserSession.shared.userId == userId }) else {
                return
            }

            _ = try? await sharingService.getSharedRecipes()

            guard await MainActor.run(body: { CurrentUserSession.shared.userId == userId }) else {
                return
            }

            guard let connections = try? await connectionCloudService.fetchConnections(forUserId: userId) else {
                return
            }

            var relatedUserIds = Set<UUID>()
            for connection in connections {
                relatedUserIds.insert(connection.fromUserId)
                relatedUserIds.insert(connection.toUserId)
            }
            relatedUserIds.remove(userId)

            guard !relatedUserIds.isEmpty else { return }

            var usersById: [UUID: User] = [:]
            for relatedUserId in relatedUserIds {
                if let cachedUser = try? await sharingRepository.fetchUser(id: relatedUserId) {
                    usersById[relatedUserId] = cachedUser
                }
            }

            if let cloudUsers = try? await userCloudService.fetchUsers(byUserIds: Array(relatedUserIds)) {
                guard await MainActor.run(body: { CurrentUserSession.shared.userId == userId }) else {
                    return
                }

                for cloudUser in cloudUsers {
                    usersById[cloudUser.id] = cloudUser
                    await bestEffort("Cache related user") {
                        try await sharingRepository.save(cloudUser)
                    }
                }
            }

            await withTaskGroup(of: (UUID, UIImage?).self) { group in
                for user in usersById.values {
                    guard user.cloudProfileImageRecordName != nil || user.profileImageURL != nil else {
                        continue
                    }

                    group.addTask {
                        if let imageURL = user.profileImageURL,
                           let image = try? await ImageLoadingPipeline.loadImage(fromFileURL: imageURL, maxPixelSize: 300) {
                            return (user.id, image)
                        }

                        guard user.cloudProfileImageRecordName != nil else {
                            return (user.id, nil)
                        }

                        do {
                            if let downloadedURL = try await profileImageManager.downloadImageFromCloud(userId: user.id),
                               let image = try? await ImageLoadingPipeline.loadImage(fromFileURL: downloadedURL, maxPixelSize: 300) {
                                return (user.id, image)
                            }
                        } catch {
                            AppLogger.general.warning("⚠️ Failed to warm profile image for \(user.username): \(error.localizedDescription)")
                        }

                        return (user.id, nil)
                    }
                }

                for await (warmedUserId, image) in group {
                    if let image {
                        let cacheKey = ImageCache.profileImageKey(userId: warmedUserId)
                        await MainActor.run {
                            guard CurrentUserSession.shared.userId == userId else { return }
                            ImageCache.shared.set(cacheKey, image: image)
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
private struct ScreenshotSceneView: View {
    let scene: String
    let dependencies: DependencyContainer
    let preloadedData: PreloadedRecipeData?

    private var recipes: [Recipe] {
        preloadedData?.allRecipes ?? []
    }

    private var collections: [Collection] {
        preloadedData?.collections ?? []
    }

    private var featuredRecipe: Recipe? {
        recipes.first { $0.title == "Pot Roast" }
            ?? recipes.first
    }

    private var featuredCollection: Collection? {
        collections.first { !$0.recipeIds.isEmpty }
            ?? collections.first
    }

    var body: some View {
        NavigationStack {
            switch scene {
            case "recipe_view":
                if let recipe = featuredRecipe {
                    RecipeDetailView(recipe: recipe, dependencies: dependencies)
                } else {
                    CookTabView(dependencies: dependencies, preloadedData: preloadedData)
                }
            case "generate_recipe":
                AIRecipeGeneratorView(dependencies: dependencies)
            case "cook_mode", "live_activity":
                if let recipe = featuredRecipe {
                    ScreenshotCookModeScene(
                        recipe: recipe,
                        coordinator: dependencies.cookModeCoordinator,
                        dependencies: dependencies
                    )
                } else {
                    CookTabView(dependencies: dependencies, preloadedData: preloadedData)
                }
            case "profile_view":
                UserProfileView(user: SimulatorQASeed.currentUser, dependencies: dependencies)
            case "collection_view":
                if let collection = featuredCollection {
                    CollectionDetailView(collection: collection, dependencies: dependencies)
                } else {
                    CollectionsListView(dependencies: dependencies)
                }
            default:
                MainTabView(dependencies: dependencies, preloadedData: preloadedData)
            }
        }
    }
}

private struct ScreenshotCookModeScene: View {
    let recipe: Recipe
    let coordinator: CookModeCoordinator
    let dependencies: DependencyContainer

    var body: some View {
        CookModeView(
            recipe: recipe,
            coordinator: coordinator,
            dependencies: dependencies
        )
        .onAppear {
            if coordinator.currentRecipe?.id != recipe.id || coordinator.totalSteps == 0 {
                coordinator.currentRecipe = recipe
                coordinator.currentStepIndex = 0
                coordinator.totalSteps = recipe.steps.count
                coordinator.sessionStartTime = Date()
                coordinator.isActive = true
            }
        }
    }
}
#endif

#Preview {
    ContentView()
        .dependencies(.preview())
}
