//
//  CurrentUserSession.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import os
import Combine

/// Manages the current user's session and authentication state
@MainActor
class CurrentUserSession: ObservableObject {
    static let shared = CurrentUserSession()

    @Published var currentUser: User?
    @Published var isInitialized = false
    @Published var needsOnboarding = false
    @Published var needsiCloudSignIn = false
    @Published var cloudKitAccountStatus: CloudKitAccountStatus?

    private let userIdKey = "currentUserId"
    private let usernameKey = "currentUsername"
    private let displayNameKey = "currentDisplayName"
    private let hasCompletedLocalOnboardingKey = "hasCompletedLocalOnboarding"
    private let logger = Logger(subsystem: "com.cauldron", category: "UserSession")

    var userId: UUID? {
        currentUser?.id
    }

    var isCloudSyncAvailable: Bool {
        cloudKitAccountStatus?.isAvailable ?? false
    }

    private init() {}

    /// Fetch CloudKit user with retry logic for network reliability
    private func fetchCloudUserWithRetry(dependencies: DependencyContainer, maxAttempts: Int = 3) async throws -> User? {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                logger.info("Attempting to fetch CloudKit user profile (attempt \(attempt)/\(maxAttempts))")
                let user = try await dependencies.cloudKitService.fetchCurrentUserProfile()
                if user != nil {
                    logger.info("Successfully fetched CloudKit user on attempt \(attempt)")
                }
                return user
            } catch {
                lastError = error
                logger.warning("Failed to fetch CloudKit user (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")

                // Don't retry if it's a definitive "no account" error
                if let cloudKitError = error as? CloudKitError,
                   case .accountNotAvailable = cloudKitError {
                    logger.info("Account not available - no need to retry")
                    return nil
                }

                // Wait before retrying (exponential backoff)
                if attempt < maxAttempts {
                    let delay = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000) // 0.5s, 1s, 2s
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }

        // All retries failed
        if let error = lastError {
            logger.error("All CloudKit fetch attempts failed: \(error.localizedDescription)")
            throw error
        }

        return nil
    }

    /// Initialize user session on app launch
    func initialize(dependencies: DependencyContainer) async {
        logger.info("Initializing user session...")

        // Step 1: Check iCloud account status
        let accountStatus = await dependencies.cloudKitService.checkAccountStatus()
        cloudKitAccountStatus = accountStatus
        logger.info("iCloud account status: \(String(describing: accountStatus))")

        // Step 2: Try to fetch existing user from CloudKit if available (with retries)
        if accountStatus.isAvailable {
            if let cloudUser = try? await fetchCloudUserWithRetry(dependencies: dependencies) {
                // Found existing user in CloudKit - use it
                logger.info("Found existing user in CloudKit: \(cloudUser.username)")
                currentUser = cloudUser
                saveUserToDefaults(cloudUser)

                // Set up push notification subscription for connection requests
                await setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)

                isInitialized = true
                needsOnboarding = false
                needsiCloudSignIn = false
                return
            } else {
                logger.info("No existing CloudKit user profile found after retries")
            }
        }

        // Step 3: Check local storage for existing user
        if let userIdString = UserDefaults.standard.string(forKey: userIdKey),
           let userId = UUID(uuidString: userIdString),
           let username = UserDefaults.standard.string(forKey: usernameKey),
           let displayName = UserDefaults.standard.string(forKey: displayNameKey) {

            logger.info("Found existing local user: \(username)")

            // Recreate user object from local storage
            currentUser = User(
                id: userId,
                username: username,
                displayName: displayName
            )

            // If iCloud is available, try to sync
            if accountStatus.isAvailable {
                do {
                    let cloudUser = try await dependencies.cloudKitService.fetchOrCreateCurrentUser(
                        username: username,
                        displayName: displayName
                    )
                    currentUser = cloudUser
                    saveUserToDefaults(cloudUser)

                    // Set up push notification subscription
                    await setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)

                    logger.info("Synced local user to CloudKit successfully")
                } catch {
                    logger.warning("CloudKit sync failed: \(error.localizedDescription)")
                    // Continue with local user
                }
            }

            isInitialized = true
            needsOnboarding = false
            needsiCloudSignIn = false
        } else {
            // Step 4: No existing user - determine what to show
            if accountStatus.isAvailable {
                // iCloud available but no user profile - show onboarding
                logger.info("No existing user - showing onboarding")
                isInitialized = true
                needsOnboarding = true
                needsiCloudSignIn = false
            } else {
                // iCloud not available - show iCloud sign-in prompt (required for Cauldron)
                logger.info("iCloud not available - showing sign-in prompt (status: \(String(describing: accountStatus)))")
                isInitialized = true
                needsOnboarding = false
                needsiCloudSignIn = true
            }
        }
    }

    /// Save user data to UserDefaults
    private func saveUserToDefaults(_ user: User) {
        UserDefaults.standard.set(user.id.uuidString, forKey: userIdKey)
        UserDefaults.standard.set(user.username, forKey: usernameKey)
        UserDefaults.standard.set(user.displayName, forKey: displayNameKey)
    }
    
    /// Create and save a new user during onboarding
    func createUser(username: String, displayName: String, dependencies: DependencyContainer) async throws {
        logger.info("Creating new user: \(username)")
        
        let userId = UUID()
        
        // Try to create in CloudKit first
        var cloudUser: User?
        do {
            cloudUser = try await dependencies.cloudKitService.fetchOrCreateCurrentUser(
                username: username,
                displayName: displayName
            )
            logger.info("User created in CloudKit")
        } catch {
            logger.warning("CloudKit user creation failed (ok if not enabled): \(error.localizedDescription)")
            // Continue with local user
        }
        
        // Use CloudKit user if available, otherwise create local
        let user = cloudUser ?? User(
            id: userId,
            username: username,
            displayName: displayName
        )

        // Save to UserDefaults
        saveUserToDefaults(user)

        currentUser = user
        needsOnboarding = false
        needsiCloudSignIn = false

        // Set up push notification subscription for new user
        await setupNotificationSubscription(for: user.id, dependencies: dependencies)

        logger.info("User session created successfully")
    }

    /// Set up CloudKit push notification subscriptions for connection requests and shared recipes
    private func setupNotificationSubscription(for userId: UUID, dependencies: DependencyContainer) async {
        // Subscribe to connection requests
        do {
            try await dependencies.cloudKitService.subscribeToConnectionRequests(forUserId: userId)
            logger.info("Successfully set up connection request notifications")
        } catch {
            logger.warning("Failed to set up connection request notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }

        // TODO: Re-enable shared recipe notifications once new architecture is implemented
        /*
        // Subscribe to shared recipes
        do {
            try await dependencies.cloudKitService.subscribeToSharedRecipes(forUserId: userId)
            logger.info("Successfully set up shared recipe notifications")
        } catch {
            logger.warning("Failed to set up shared recipe notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }
        */
    }
    
    /// Update user profile
    func updateUser(username: String, displayName: String, dependencies: DependencyContainer) async throws {
        guard let currentUser = currentUser else {
            throw UserSessionError.notAuthenticated
        }
        
        logger.info("Updating user profile: \(username)")
        
        let updatedUser = User(
            id: currentUser.id,
            username: username,
            displayName: displayName,
            cloudRecordName: currentUser.cloudRecordName
        )
        
        // Try to update in CloudKit
        do {
            try await dependencies.cloudKitService.saveUser(updatedUser)
            logger.info("User updated in CloudKit")
        } catch {
            logger.warning("CloudKit update failed (ok if not enabled): \(error.localizedDescription)")
        }

        // Save to UserDefaults
        saveUserToDefaults(updatedUser)

        self.currentUser = updatedUser

        logger.info("User profile updated successfully")
    }
    
    /// Perform initial recipe sync after user authentication
    func performInitialSync(dependencies: DependencyContainer) async {
        guard let userId = userId, isCloudSyncAvailable else {
            logger.info("Skipping initial sync - user not authenticated or CloudKit unavailable")
            return
        }

        logger.info("Performing initial recipe sync...")

        do {
            try await dependencies.recipeSyncService.performFullSync(for: userId)
            logger.info("Initial sync completed successfully")
        } catch {
            logger.error("Initial sync failed: \(error.localizedDescription)")
            // Don't throw - sync failure shouldn't block app usage
        }
    }

    /// Sign out and clear user session
    func signOut() {
        logger.info("Signing out user")

        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: displayNameKey)

        currentUser = nil
        needsOnboarding = true

        logger.info("User signed out")
    }
}

enum UserSessionError: LocalizedError {
    case notAuthenticated
    case invalidUsername
    case invalidDisplayName
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "No user is currently signed in"
        case .invalidUsername:
            return "Username must be between 3 and 20 characters"
        case .invalidDisplayName:
            return "Display name cannot be empty"
        }
    }
}
