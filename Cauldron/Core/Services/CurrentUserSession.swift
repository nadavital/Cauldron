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
    
    private let userIdKey = "currentUserId"
    private let usernameKey = "currentUsername"
    private let displayNameKey = "currentDisplayName"
    private let logger = Logger(subsystem: "com.cauldron", category: "UserSession")
    
    var userId: UUID? {
        currentUser?.id
    }
    
    private init() {}
    
    /// Initialize user session on app launch
    func initialize(dependencies: DependencyContainer) async {
        logger.info("Initializing user session...")
        
        // Check if we have a stored user ID
        if let userIdString = UserDefaults.standard.string(forKey: userIdKey),
           let userId = UUID(uuidString: userIdString),
           let username = UserDefaults.standard.string(forKey: usernameKey),
           let displayName = UserDefaults.standard.string(forKey: displayNameKey) {
            
            logger.info("Found existing user session: \(username)")
            
            // Recreate user object
            currentUser = User(
                id: userId,
                username: username,
                displayName: displayName
            )
            
            // Try to sync with CloudKit
            do {
                let cloudUser = try await dependencies.cloudKitService.fetchOrCreateCurrentUser(
                    username: username,
                    displayName: displayName
                )
                currentUser = cloudUser
                logger.info("Synced with CloudKit successfully")
            } catch {
                logger.warning("CloudKit sync failed (ok if not enabled): \(error.localizedDescription)")
                // Continue with local user - CloudKit may not be enabled
            }
            
            isInitialized = true
            needsOnboarding = false
        } else {
            // No existing user - needs onboarding
            logger.info("No existing user found - needs onboarding")
            isInitialized = true
            needsOnboarding = true
        }
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
        UserDefaults.standard.set(user.id.uuidString, forKey: userIdKey)
        UserDefaults.standard.set(user.username, forKey: usernameKey)
        UserDefaults.standard.set(user.displayName, forKey: displayNameKey)
        
        currentUser = user
        needsOnboarding = false
        
        logger.info("User session created successfully")
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
        UserDefaults.standard.set(updatedUser.username, forKey: usernameKey)
        UserDefaults.standard.set(updatedUser.displayName, forKey: displayNameKey)
        
        self.currentUser = updatedUser
        
        logger.info("User profile updated successfully")
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
