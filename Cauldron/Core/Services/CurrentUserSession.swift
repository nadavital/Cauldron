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
    private let profileEmojiKey = "currentProfileEmoji"
    private let profileColorKey = "currentProfileColor"
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
                // Only log on retries (not first attempt)
                if attempt > 1 {
                    logger.info("Retrying CloudKit user profile fetch (attempt \(attempt)/\(maxAttempts))")
                }
                let user = try await dependencies.cloudKitService.fetchCurrentUserProfile()
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
        // Step 1: Check iCloud account status
        let accountStatus = await dependencies.cloudKitService.checkAccountStatus()
        cloudKitAccountStatus = accountStatus

        // Step 2: Try to fetch existing user from CloudKit if available (with retries)
        if accountStatus.isAvailable {
            if let cloudUser = try? await fetchCloudUserWithRetry(dependencies: dependencies) {
                // Found existing user in CloudKit - use it
                currentUser = cloudUser
                saveUserToDefaults(cloudUser)

                // Download profile image from CloudKit if it exists and local copy is missing
                await downloadProfileImageIfNeeded(for: cloudUser, dependencies: dependencies)

                // Set up push notification subscription for connection requests
                await setupNotificationSubscription(for: cloudUser.id, dependencies: dependencies)

                isInitialized = true
                needsOnboarding = false
                needsiCloudSignIn = false
                return
            }
        }

        // Step 3: Check local storage for existing user
        if let userIdString = UserDefaults.standard.string(forKey: userIdKey),
           let userId = UUID(uuidString: userIdString),
           let username = UserDefaults.standard.string(forKey: usernameKey),
           let displayName = UserDefaults.standard.string(forKey: displayNameKey) {

            // Retrieve optional profile emoji and color
            let profileEmoji = UserDefaults.standard.string(forKey: profileEmojiKey)
            let profileColor = UserDefaults.standard.string(forKey: profileColorKey)

            // Recreate user object from local storage
            currentUser = User(
                id: userId,
                username: username,
                displayName: displayName,
                profileEmoji: profileEmoji,
                profileColor: profileColor
            )

            // If iCloud is available, try to sync
            if accountStatus.isAvailable {
                do {
                    let cloudUser = try await dependencies.cloudKitService.fetchOrCreateCurrentUser(
                        username: username,
                        displayName: displayName,
                        profileEmoji: profileEmoji,
                        profileColor: profileColor
                    )
                    currentUser = cloudUser
                    saveUserToDefaults(cloudUser)

                    // Download profile image from CloudKit if it exists and local copy is missing
                    await downloadProfileImageIfNeeded(for: cloudUser, dependencies: dependencies)

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
        UserDefaults.standard.set(user.profileEmoji, forKey: profileEmojiKey)
        UserDefaults.standard.set(user.profileColor, forKey: profileColorKey)
    }

    /// Download profile image from CloudKit if it exists in cloud but not locally
    private func downloadProfileImageIfNeeded(for user: User, dependencies: DependencyContainer) async {
        // Only download if:
        // 1. User has a cloud profile image record
        // 2. Local image file doesn't exist
        guard user.cloudProfileImageRecordName != nil else {
            return
        }

        let imageExists = await dependencies.profileImageManager.imageExists(userId: user.id)
        guard !imageExists else {
            logger.info("Profile image already exists locally - skipping download")
            return
        }

        logger.info("Downloading profile image from CloudKit for user \(user.username)")

        do {
            if let imageURL = try await dependencies.profileImageManager.downloadImageFromCloud(userId: user.id) {
                // Update the current user with the local image URL
                let updatedUser = user.updatedProfile(
                    profileEmoji: user.profileEmoji,
                    profileColor: user.profileColor,
                    profileImageURL: imageURL,
                    cloudProfileImageRecordName: user.cloudProfileImageRecordName,
                    profileImageModifiedAt: user.profileImageModifiedAt
                )
                currentUser = updatedUser
                logger.info("✅ Downloaded and set profile image")
            } else {
                logger.info("No profile image found in CloudKit (record may be stale)")
            }
        } catch {
            logger.warning("Failed to download profile image: \(error.localizedDescription)")
            // Don't block user session if image download fails
        }
    }
    
    /// Create and save a new user during onboarding
    func createUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        profileImage: UIImage? = nil,
        dependencies: DependencyContainer
    ) async throws {
        logger.info("Creating new user: \(username)")

        let userId = UUID()

        // Handle profile image if provided (mutually exclusive with emoji)
        var profileImageURL: URL?
        if let profileImage = profileImage {
            // Save profile image locally
            profileImageURL = try await dependencies.profileImageManager.saveImage(profileImage, userId: userId)
            logger.info("Saved profile image locally")
        }

        // Try to create in CloudKit first
        var cloudUser: User?
        do {
            cloudUser = try await dependencies.cloudKitService.fetchOrCreateCurrentUser(
                username: username,
                displayName: displayName,
                profileEmoji: profileImage == nil ? profileEmoji : nil,  // Clear emoji if using photo
                profileColor: profileColor
            )
            logger.info("User created in CloudKit")

            // Upload profile image to CloudKit if provided
            if let profileImage = profileImage, let cloudUser = cloudUser {
                do {
                    let recordName = try await dependencies.profileImageManager.uploadImageToCloud(userId: cloudUser.id)
                    logger.info("Uploaded profile image to CloudKit: \(recordName)")
                } catch {
                    logger.warning("Failed to upload profile image to CloudKit: \(error.localizedDescription)")
                    // Continue - local image is still available
                }
            }
        } catch {
            logger.warning("CloudKit user creation failed (ok if not enabled): \(error.localizedDescription)")
            // Continue with local user
        }

        // Use CloudKit user if available, otherwise create local
        let user = cloudUser ?? User(
            id: userId,
            username: username,
            displayName: displayName,
            profileEmoji: profileImage == nil ? profileEmoji : nil,  // Clear emoji if using photo
            profileColor: profileColor,
            profileImageURL: profileImageURL
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
        } catch {
            logger.warning("Failed to set up connection request notifications: \(error.localizedDescription)")
            // Don't block user flow if subscription fails
        }

        // Subscribe to connection acceptances
        do {
            try await dependencies.cloudKitService.subscribeToConnectionAcceptances(forUserId: userId)
        } catch {
            logger.warning("Failed to set up connection acceptance notifications: \(error.localizedDescription)")
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
    func updateUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        dependencies: DependencyContainer
    ) async throws {
        guard let currentUser = currentUser else {
            throw UserSessionError.notAuthenticated
        }

        logger.info("Updating user profile: \(username)")

        let updatedUser = User(
            id: currentUser.id,
            username: username,
            displayName: displayName,
            email: currentUser.email,
            cloudRecordName: currentUser.cloudRecordName,
            createdAt: currentUser.createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor
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
        UserDefaults.standard.removeObject(forKey: profileEmojiKey)
        UserDefaults.standard.removeObject(forKey: profileColorKey)

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
