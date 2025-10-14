//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.dependencies) private var dependencies
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var hasPerformedInitialSync = false

    var body: some View {
        Group {
            if !userSession.isInitialized {
                // Loading state
                ProgressView("Initializing...")
            } else if userSession.needsiCloudSignIn, let accountStatus = userSession.cloudKitAccountStatus {
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
            } else if userSession.needsOnboarding {
                // Show onboarding for new users
                OnboardingView(dependencies: dependencies) {
                    // Onboarding completed, will trigger view update
                }
            } else {
                // Show main app
                MainTabView(dependencies: dependencies)
                    .task {
                        // Perform initial sync after user is authenticated
                        if !hasPerformedInitialSync && userSession.currentUser != nil {
                            hasPerformedInitialSync = true
                            await userSession.performInitialSync(dependencies: dependencies)
                        }
                    }
            }
        }
        .task {
            // Initialize user session on app launch
            if !userSession.isInitialized {
                await userSession.initialize(dependencies: dependencies)
            }
        }
    }
}

#Preview {
    ContentView()
        .dependencies(.preview())
}
