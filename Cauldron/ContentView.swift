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

struct ContentView: View {
    @Environment(\.dependencies) private var dependencies
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var isDataReady = false
    @State private var preloadedData: PreloadedRecipeData?

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
        }
        .animation(.easeInOut(duration: 0.25), value: isDataReady)
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
        }
    }

    private func performInitialLoad() async -> PreloadedRecipeData? {
        // OPTIMIZATION: Load local data immediately WITHOUT syncing from CloudKit first
        // This makes launch much faster - sync happens in background after UI is shown
        // The periodic sync will keep data up to date

        // Preload ALL data that will be needed by the main view
        do {
            // OPTIMIZATION: Parallelize independent data fetches using async let
            async let ownedRecipes = dependencies.recipeRepository.fetchAll()
            async let cookingHistory = dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            async let localCollections = dependencies.collectionRepository.fetchAll()

            // Wait for all to complete in parallel
            let allRecipes = try await ownedRecipes
            let recentlyCookedIds = try await cookingHistory
            let collections = try await localCollections
            AppLogger.general.info("✅ All data preloaded successfully: \(allRecipes.count) recipes, \(recentlyCookedIds.count) recent, \(collections.count) collections")

            // Run one-time migration to fix recipe ownership from old reference system
            if let userId = userSession.userId {
                do {
                    try await dependencies.recipeRepository.migrateRecipeOwnership(currentUserId: userId)
                } catch {
                    AppLogger.general.warning("Recipe ownership migration failed (continuing): \(error.localizedDescription)")
                }
            }

            // OPTIMIZATION: Start background sync AFTER UI is shown
            // This keeps the UI responsive while CloudKit syncs in the background
            if let userId = userSession.userId, userSession.isCloudSyncAvailable {
                Task.detached(priority: .utility) {
                    do {
                        try await dependencies.recipeSyncService.performFullSync(for: userId)
                        AppLogger.general.info("🔄 Background sync completed")
                    } catch {
                        AppLogger.general.warning("Background sync failed: \(error.localizedDescription)")
                    }
                }
            }

            // Preload shared recipes feed in background
            Task.detached(priority: .utility) { @MainActor in
                SharingTabViewModel.shared.configure(dependencies: dependencies)
                await SharingTabViewModel.shared.loadSharedRecipes()
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

                    // Fetch and cache all user details
                    for userId in userIds {
                        if let cloudUser = try? await dependencies.cloudKitService.fetchUser(byUserId: userId) {
                            try? await dependencies.sharingRepository.save(cloudUser)
                        }
                    }
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
