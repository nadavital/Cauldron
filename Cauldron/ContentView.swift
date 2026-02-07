//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
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
    // When you ship a feature update, set this to match that version (e.g., "1.1.2").
    // When you ship a bug fix, leave this unchanged so no splash appears.
    private static let whatsNewContentVersion = "1.1.2"

    @Environment(\.dependencies) private var dependencies
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var isDataReady = false
    @State private var preloadedData: PreloadedRecipeData?
    @State private var sharedContentWrapper: SharedContentWrapper?
    @State private var isLoadingShare = false
    @State private var showShareError = false
    @State private var shareErrorMessage = ""

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
                    } else if userSession.needsOnboarding {
                        // Show onboarding for new users
                        OnboardingView(dependencies: dependencies) {
                            // Onboarding completed, will trigger view update
                        }
                    } else {
                        // CRITICAL: Pass preloadedData to MainTabView → CookTabView → CookTabViewModel
                        // This data pipeline ensures CookTabViewModel initializes with populated arrays
                        // instead of empty arrays, preventing the empty state from ever rendering.
                        MainTabView(dependencies: dependencies, preloadedData: preloadedData)
                    }
                }
            }
            .opacity(isDataReady ? 1 : 0)

            // OPTIMIZATION: Show loading overlay to prevent white screen
            // This appears immediately when ContentView loads, before data is ready
            // It uses the same background color as the system, creating a seamless transition
            // from the iOS launch screen
            if !isDataReady {
                Color(uiColor: .systemBackground)
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
                Task {
                    await loadSharedContent(url: url)
                }
            }
        }
        .task {
            // CRITICAL LOADING SEQUENCE:
            // Step 1: Initialize user session (determines which view to show)
            await userSession.initialize(dependencies: dependencies)

            // Step 2: Preload ALL recipe data BEFORE showing UI
            // This is the key to preventing empty state flash - we load everything
            // synchronously before setting isDataReady = true
            if userSession.currentUser != nil {
                preloadedData = await performInitialLoad()
            }

            // Step 3: Restore cook mode session if exists
            await dependencies.cookModeCoordinator.restoreState()

            // Step 4: Signal that we're ready to show UI with populated data
            // Only NOW will the view hierarchy render, and CookTabViewModel will
            // receive preloadedData in its initializer, preventing empty arrays
            isDataReady = true

            // Step 5: Check for pending share URL from PendingShareManager
            // This handles cold-start scenarios where the app was opened via Universal Link
            if let pendingURL = await PendingShareManager.shared.consumePendingURL() {
                AppLogger.general.info("🔔 ContentView: Found pending share URL from cold start: \(pendingURL)")
                Task {
                    await loadSharedContent(url: pendingURL)
                }
            }

            if let pendingImportURL = ShareExtensionImportStore.consumePendingRecipeURL() {
                AppLogger.general.info("🔔 ContentView: Found pending recipe import URL: \(pendingImportURL)")
                NotificationCenter.default.post(
                    name: .openRecipeImportURL,
                    object: pendingImportURL
                )
            }

            maybeShowSplashScreen()
        }
        .onChange(of: userSession.isInitialized) { _ in
            maybeShowSplashScreen()
        }
        .onChange(of: userSession.needsOnboarding) { _ in
            maybeShowSplashScreen()
        }
        .onChange(of: userSession.needsiCloudSignIn) { _ in
            maybeShowSplashScreen()
        }
        .onChange(of: isDataReady) { _ in
            maybeShowSplashScreen()
        }
    }

    private func maybeShowSplashScreen() {
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
        if !hasSeenWelcomeScreen {
            showWelcome = true
            return
        }

        // Priority 2: What's New for existing users when content version changes
        let forceShow = Bundle.main.object(forInfoDictionaryKey: "WhatsNewForceShow") as? Bool == true
        if forceShow || whatsNewLastSeenContentVersion != Self.whatsNewContentVersion {
            showWhatsNew = true
        }
    }

    private func loadSharedContent(url: URL) async {
        isLoadingShare = true
        defer { isLoadingShare = false }
        
        do {
            let content = try await dependencies.externalShareService.importFromShareURL(url)
            
            // If it's a recipe, we need to fetch the full details
            // because the share data only contains a summary
            if case .recipe(let partialRecipe, let owner) = content {
                AppLogger.general.info("🌐 ContentView: Processing recipe share for \(partialRecipe.title)")

                // 1. Check if we already have this recipe locally (e.g. we are the owner)
                // This prevents fetching a stale public version if we just made it private
                if let localRecipe = try? await dependencies.recipeRepository.fetch(id: partialRecipe.id) {
                    AppLogger.general.info("✅ ContentView: Found local copy of recipe, using that")
                    await MainActor.run {
                        let wrapper = SharedContentWrapper(content: .recipe(localRecipe, originalCreator: owner))
                        NotificationCenter.default.post(name: .navigateToSharedContent, object: wrapper)
                    }
                    return
                }

                // 2. If not found locally, fetch from CloudKit public database
                AppLogger.general.info("🌐 ContentView: Fetching full recipe details from CloudKit")
                if let fullRecipe = try await dependencies.recipeCloudService.fetchPublicRecipe(id: partialRecipe.id) {
                    AppLogger.general.info("✅ ContentView: Successfully fetched full recipe")
                    await MainActor.run {
                        // Post notification to navigate to the recipe in the Search tab
                        // Use the full recipe but keep the owner info from the share if available
                        let wrapper = SharedContentWrapper(content: .recipe(fullRecipe, originalCreator: owner))
                        NotificationCenter.default.post(name: .navigateToSharedContent, object: wrapper)
                    }
                } else {
                    AppLogger.general.error("❌ ContentView: Recipe not found in public database")
                    // CRITICAL: Do NOT fallback to partial recipe. If it's not in public DB, it's private or deleted.
                    await MainActor.run {
                        shareErrorMessage = "This recipe is no longer available or has been made private."
                        showShareError = true
                    }
                }
            } else {
                // For profiles and collections, the share data is usually sufficient or handled differently
                await MainActor.run {
                    let wrapper = SharedContentWrapper(content: content)
                    NotificationCenter.default.post(name: .navigateToSharedContent, object: wrapper)
                }
            }
        } catch {
            AppLogger.general.error("❌ ContentView: Failed to load shared content: \(error)")
            await MainActor.run {
                shareErrorMessage = "Failed to load shared content. The link may be invalid or expired."
                showShareError = true
            }
        }
    }

    private func performInitialLoad() async -> PreloadedRecipeData? {
        // Preload ALL data that will be needed by the main view
        do {
            // IMPORTANT: On first app launch (or after reinstall), we need to sync from CloudKit FIRST
            // to download recipe images before showing the UI. On subsequent launches, we can skip
            // the initial sync and just show local data immediately (images already downloaded).
            let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

            if !hasLaunchedBefore {
                // First launch - sync from CloudKit FIRST to download images
                AppLogger.general.info("🚀 First launch detected - syncing from CloudKit before showing UI...")

                // Run one-time migration to fix recipe ownership from old reference system
                if let userId = userSession.userId {
                    do {
                        try await dependencies.recipeRepository.migrateRecipeOwnership(currentUserId: userId)
                    } catch {
                        AppLogger.general.warning("Recipe ownership migration failed (continuing): \(error.localizedDescription)")
                    }
                }

                // Perform sync (this will download images)
                if let userId = userSession.userId, userSession.isCloudSyncAvailable {
                    do {
                        try await dependencies.recipeSyncService.performFullSync(for: userId)
                        AppLogger.general.info("✅ Initial CloudKit sync completed with images")
                    } catch {
                        AppLogger.general.warning("Initial sync failed (continuing): \(error.localizedDescription)")
                    }
                }

                // Mark as launched
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }

            // Clean up any duplicate recipes that may have been created
            do {
                let removedCount = try await dependencies.recipeRepository.removeDuplicateRecipes()
                if removedCount > 0 {
                    AppLogger.general.info("🧹 Cleaned up \(removedCount) duplicate recipes")
                }
            } catch {
                AppLogger.general.warning("Failed to remove duplicate recipes: \(error.localizedDescription)")
            }

            // OPTIMIZATION: Parallelize independent data fetches using async let
            async let ownedRecipes = dependencies.recipeRepository.fetchAll()
            async let cookingHistory = dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            async let localCollections = dependencies.collectionRepository.fetchAll()

            // Wait for all to complete in parallel
            let allRecipes = try await ownedRecipes
            let recentlyCookedIds = try await cookingHistory
            let collections = try await localCollections
            // Data preloaded successfully (don't log routine operations)

            // Run one-time migrations (for existing users)
            if hasLaunchedBefore, let userId = userSession.userId {
                do {
                    // Fix recipe ownership from old reference system
                    try await dependencies.recipeRepository.migrateRecipeOwnership(currentUserId: userId)

                    // Fix corrupted image filenames (CloudKit version suffixes)
                    try await dependencies.recipeRepository.fixCorruptedImageFilenames()

                    // Run migration to ensure public recipes are in the public database
                    // This runs in the background
                    Task.detached(priority: .utility) {
                        await dependencies.recipeRepository.migratePublicRecipesToPublicDatabase()
                    }
                } catch {
                    AppLogger.general.warning("Migration failed (continuing): \(error.localizedDescription)")
                }
            }

            // OPTIMIZATION: For subsequent launches, start background sync AFTER UI is shown
            // This keeps the UI responsive while CloudKit syncs in the background
            if hasLaunchedBefore, let userId = userSession.userId, userSession.isCloudSyncAvailable {
                Task.detached(priority: .utility) {
                    do {
                        try await dependencies.recipeSyncService.performFullSync(for: userId)
                        // Background sync completed (don't log routine operations)
                    } catch {
                        AppLogger.general.warning("Background sync failed: \(error.localizedDescription)")
                    }
                }
            }

            // Preload shared recipes feed in background
            Task.detached(priority: .utility) { @MainActor in
                FriendsTabViewModel.shared.configure(dependencies: dependencies)
                await FriendsTabViewModel.shared.loadSharedRecipes()
            }

            // Preload connections/friends list in background
            // This prevents the "slow population" effect when navigating to friends tab
            if let userId = userSession.userId {
                Task.detached(priority: .utility) { @MainActor in
                    // Load connections first
                    await dependencies.connectionManager.loadConnections(forUserId: userId)

                    // Then preload user details for all connections
                    // This eliminates the flicker when opening the friends list
                    let connections = dependencies.connectionManager.connections.values.map { $0.connection }
                    var userIds = Set<UUID>()
                    for connection in connections {
                        userIds.insert(connection.fromUserId)
                        userIds.insert(connection.toUserId)
                    }

                    // Build a map of users for profile image preloading
                    var usersMap: [UUID: User] = [:]

                    // Load from local cache first (instant)
                    for userId in userIds {
                        if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
                            usersMap[userId] = cachedUser
                        }
                    }

                    // Batch fetch from CloudKit to get latest data (single query instead of N queries)
                    if let cloudUsers = try? await dependencies.userCloudService.fetchUsers(byUserIds: Array(userIds)) {
                        for cloudUser in cloudUsers {
                            usersMap[cloudUser.id] = cloudUser
                            try? await dependencies.sharingRepository.save(cloudUser)
                        }
                    }

                    // Preload profile images for all friends into memory cache
                    // Preloading during app launch (don't log routine operations)

                    await withTaskGroup(of: (UUID, UIImage?).self) { group in
                        for user in usersMap.values {
                            // Skip if user doesn't have a cloud profile image and no local image
                            guard user.cloudProfileImageRecordName != nil || user.profileImageURL != nil else {
                                continue
                            }

                            group.addTask {
                                // Try to load from local file first
                                if let imageURL = user.profileImageURL,
                                   let imageData = try? Data(contentsOf: imageURL),
                                   let image = UIImage(data: imageData) {
                                    return (user.id, image)
                                }

                                // If no local file, download from CloudKit
                                if user.cloudProfileImageRecordName != nil {
                                    do {
                                        if let downloadedURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id),
                                           let imageData = try? Data(contentsOf: downloadedURL),
                                           let image = UIImage(data: imageData) {
                                            // Downloaded profile image (don't log routine operations)
                                            return (user.id, image)
                                        }
                                    } catch {
                                        AppLogger.general.warning("⚠️ Failed to download profile image for \(user.username): \(error.localizedDescription)")
                                    }
                                }

                                return (user.id, nil)
                            }
                        }

                        // Collect results and load into memory cache
                        for await (userId, image) in group {
                            if let image = image {
                                let cacheKey = ImageCache.profileImageKey(userId: userId)
                                await ImageCache.shared.set(cacheKey, image: image)
                            }
                        }
                    }

                    // Finished preloading friend profile images (don't log routine operations)

                    // Set the shared cache timestamp so ConnectionsViewModel knows data is fresh
                    // This is a workaround since we can't directly access the static variable
                    // But loading connections will trigger ConnectionsViewModel to set it
                }
            }

            return PreloadedRecipeData(allRecipes: allRecipes, recentlyCookedIds: recentlyCookedIds, collections: collections)
        } catch {
            AppLogger.general.warning("Data preload failed: \(error.localizedDescription)")
            return nil
        }
    }
}

#Preview {
    ContentView()
        .dependencies(.preview())
}
