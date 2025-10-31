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
/// By loading ALL recipes BEFORE showing the UI and passing them directly to CookTabViewModel,
/// we ensure the view never renders with empty arrays.
struct PreloadedRecipeData {
    let allRecipes: [Recipe]           // All recipes (owned + referenced) loaded from storage
    let recentlyCookedIds: [UUID]      // IDs of recently cooked recipes for quick filtering
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

            // Wait for both to complete in parallel
            var allRecipes = try await ownedRecipes
            let recentlyCookedIds = try await cookingHistory
            AppLogger.general.info("⚡️ Fast-loaded \(allRecipes.count) owned recipes and \(recentlyCookedIds.count) recent")

            // Preload recipe references (for shared recipes saved by user)
            if let userId = userSession.userId, userSession.isCloudSyncAvailable {
                do {
                    let references = try await dependencies.recipeReferenceManager.fetchReferences(for: userId)
                    AppLogger.general.info("Preloaded \(references.count) recipe references")

                    // OPTIMIZATION: Fetch all recipe references in parallel using TaskGroup
                    if !references.isEmpty {
                        await withTaskGroup(of: Recipe?.self) { group in
                            for reference in references {
                                group.addTask {
                                    do {
                                        return try await self.dependencies.cloudKitService.fetchPublicRecipe(
                                            recipeId: reference.originalRecipeId,
                                            ownerId: reference.originalOwnerId
                                        )
                                    } catch {
                                        AppLogger.general.warning("Failed to preload reference: \(reference.recipeTitle)")
                                        return nil
                                    }
                                }
                            }

                            // Collect all successfully fetched recipes
                            for await recipe in group {
                                if let recipe = recipe, !allRecipes.contains(where: { $0.id == recipe.id }) {
                                    allRecipes.append(recipe)
                                }
                            }
                        }
                    }
                } catch {
                    AppLogger.general.warning("Failed to preload recipe references: \(error.localizedDescription)")
                }
            }

            AppLogger.general.info("✅ All data preloaded successfully: \(allRecipes.count) recipes, \(recentlyCookedIds.count) recent")

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

            return PreloadedRecipeData(allRecipes: allRecipes, recentlyCookedIds: recentlyCookedIds)
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
