//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os

struct ContentView: View {
    @Environment(\.dependencies) private var dependencies
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var hasPerformedInitialLoad = false

    var body: some View {
        Group {
            if userSession.isInitialized && hasPerformedInitialLoad {
                if userSession.needsiCloudSignIn, let accountStatus = userSession.cloudKitAccountStatus {
                    // Show iCloud sign-in prompt
                    iCloudSignInPromptView(
                        accountStatus: accountStatus,
                        onRetry: {
                            // Re-check iCloud status
                            await userSession.initialize(dependencies: dependencies)
                        },
                        onContinueWithoutCloud: {
                            // Allow user to continue without cloud sync
                            userSession.needsiCloudSignIn = false
                            userSession.needsOnboarding = true
                        }
                    )
                    .transition(.opacity)
                } else if userSession.needsOnboarding {
                    // Show onboarding for new users
                    OnboardingView(dependencies: dependencies) {
                        // Onboarding completed, will trigger view update
                    }
                    .transition(.opacity)
                } else {
                    // Show main app - data already loaded
                    MainTabView(dependencies: dependencies)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: userSession.isInitialized && hasPerformedInitialLoad)
        .task {
            // Initialize user session and preload data on app launch
            // This all happens while launch screen is still visible
            await userSession.initialize(dependencies: dependencies)

            // Preload recipes to prevent empty state flash
            if userSession.currentUser != nil {
                await performInitialLoad()
            }

            // Small delay to ensure smooth transition
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            hasPerformedInitialLoad = true
        }
    }

    private func performInitialLoad() async {
        // Perform initial sync if CloudKit is available
        if let userId = userSession.userId, userSession.isCloudSyncAvailable {
            do {
                try await dependencies.recipeSyncService.performFullSync(for: userId)
                AppLogger.general.info("Initial recipe sync completed")
            } catch {
                AppLogger.general.warning("Initial sync failed (continuing): \(error.localizedDescription)")
            }
        }

        // Preload ALL data that will be needed by the main view
        do {
            // Fetch recipes to warm up the database
            let recipes = try await dependencies.recipeRepository.fetchAll()
            AppLogger.general.info("Preloaded \(recipes.count) recipes")

            // Preload pantry items for "what can I cook" calculation
            _ = try await dependencies.pantryRepository.fetchAll()

            // Preload cooking history
            _ = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)

            AppLogger.general.info("All data preloaded successfully")
        } catch {
            AppLogger.general.warning("Data preload failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
        .dependencies(.preview())
}
