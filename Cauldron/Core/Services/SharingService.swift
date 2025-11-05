//
//  SharingService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import os

/// Service for handling recipe sharing logic
actor SharingService {
    private let sharingRepository: SharingRepository
    private let recipeRepository: RecipeRepository
    private let cloudKitService: CloudKitService
    private let logger = Logger(subsystem: "com.cauldron", category: "SharingService")

    init(sharingRepository: SharingRepository, recipeRepository: RecipeRepository, cloudKitService: CloudKitService) {
        self.sharingRepository = sharingRepository
        self.recipeRepository = recipeRepository
        self.cloudKitService = cloudKitService
    }
    
    // MARK: - User Management

    /// Get all users available for sharing (fetches from CloudKit and caches locally)
    func getAllUsers() async throws -> [User] {
        // Fetch from CloudKit PUBLIC database to get latest users
        do {
            let cloudUsers = try await cloudKitService.fetchAllUsers()

            // Cache users locally for offline access
            for user in cloudUsers {
                try? await sharingRepository.save(user)
            }

            logger.info("Fetched \(cloudUsers.count) users from CloudKit")
            return cloudUsers
        } catch {
            // If CloudKit fails, fallback to local cache
            logger.warning("Failed to fetch users from CloudKit, using local cache: \(error.localizedDescription)")
            return try await sharingRepository.fetchAllUsers()
        }
    }
    
    /// Search for users by username or display name via CloudKit
    func searchUsers(_ query: String) async throws -> [User] {
        guard !query.isEmpty else {
            return []
        }

        // Search CloudKit PUBLIC database for users
        let users = try await cloudKitService.searchUsers(query: query)
        logger.info("Found \(users.count) users matching '\(query)' in CloudKit")
        return users
    }
    
    /// Create or update a user (for demo purposes)
    func saveUser(_ user: User) async throws {
        try await sharingRepository.save(user)
    }
    
    // MARK: - Recipe Sharing

    /// Share a recipe with another user via CloudKit
    /// TODO: Implement new PUBLIC database sharing with visibility-based access
    func shareRecipe(_ recipe: Recipe, with user: User, from currentUser: User) async throws {
        logger.info("📤 Sharing recipe '\(recipe.title)' with user: \(user.username)")

        // TODO: Implement new sharing logic:
        // 1. Copy recipe to PUBLIC database if visibility != .private
        // 2. No need for direct sharing - friends see via visibility queries

        logger.warning("⚠️ Recipe sharing not yet implemented with new architecture")
        throw NSError(domain: "SharingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sharing not yet implemented"])
    }
    
    /// Get all recipes shared with the current user (from PUBLIC database)
    /// Fetches friends' recipes (visibility = friendsOnly) and public recipes (visibility = public)
    ///
    /// NOTE: These are recipes available for browsing, but not necessarily saved to the user's collection.
    /// To save a recipe for later, users must explicitly create a RecipeReference (via "Add to My Recipes")
    /// or copy it to their personal collection (via "Save a Copy").
    func getSharedRecipes() async throws -> [SharedRecipe] {
        logger.info("📥 Fetching shared recipes from PUBLIC database")

        // Get current user to know who we are
        let currentUser = await MainActor.run { CurrentUserSession.shared.currentUser }
        guard let currentUser = currentUser else {
            logger.warning("No current user - cannot fetch shared recipes")
            return []
        }

        // Get connected friends from CloudKit
        let connections = try await cloudKitService.fetchConnections(forUserId: currentUser.id)
        let acceptedConnections = connections.filter { $0.isAccepted }

        // Get friend user IDs (both from and to, excluding self)
        let friendIds = acceptedConnections.flatMap { connection -> [UUID] in
            var ids: [UUID] = []
            if connection.fromUserId != currentUser.id {
                ids.append(connection.fromUserId)
            }
            if connection.toUserId != currentUser.id {
                ids.append(connection.toUserId)
            }
            return ids
        }

        logger.info("Found \(friendIds.count) connected friends")

        var allSharedRecipes: [SharedRecipe] = []

        // Fetch friends-only recipes from friends
        if !friendIds.isEmpty {
            let friendsRecipes = try await cloudKitService.querySharedRecipes(
                ownerIds: friendIds,
                visibility: .friendsOnly
            )
            logger.info("Found \(friendsRecipes.count) friends-only recipes")

            // Convert to SharedRecipe objects
            for recipe in friendsRecipes {
                // Fetch owner user info by userId
                if let ownerId = recipe.ownerId,
                   let owner = try? await cloudKitService.fetchUser(byUserId: ownerId) {
                    let sharedRecipe = SharedRecipe(
                        id: UUID(),
                        recipe: recipe,
                        sharedBy: owner,
                        sharedAt: recipe.createdAt
                    )
                    allSharedRecipes.append(sharedRecipe)
                }
            }
        }

        // Also fetch public recipes from friends (so friends see each other's public recipes too)
        if !friendIds.isEmpty {
            let friendsPublicRecipes = try await cloudKitService.querySharedRecipes(
                ownerIds: friendIds,
                visibility: .publicRecipe
            )
            logger.info("Found \(friendsPublicRecipes.count) public recipes from friends")

            // Convert to SharedRecipe objects
            for recipe in friendsPublicRecipes {
                // Skip if already added (shouldn't happen but be safe)
                if allSharedRecipes.contains(where: { $0.recipe.id == recipe.id }) {
                    continue
                }

                if let ownerId = recipe.ownerId,
                   let owner = try? await cloudKitService.fetchUser(byUserId: ownerId) {
                    let sharedRecipe = SharedRecipe(
                        id: UUID(),
                        recipe: recipe,
                        sharedBy: owner,
                        sharedAt: recipe.createdAt
                    )
                    allSharedRecipes.append(sharedRecipe)
                }
            }
        }

        logger.info("✅ Found \(allSharedRecipes.count) total shared recipes from friends")
        return allSharedRecipes
    }
    
    /// Copy a shared recipe to the user's personal collection
    func copySharedRecipeToPersonal(_ sharedRecipe: SharedRecipe) async throws -> Recipe {
        // Get current user ID
        let userId = await MainActor.run {
            CurrentUserSession.shared.userId
        }

        guard let userId = userId else {
            logger.error("Cannot copy recipe - no current user")
            throw NSError(domain: "SharingService", code: 2, userInfo: [NSLocalizedDescriptionKey: "No current user found"])
        }

        // Create a copy using withOwner(), preserving attribution to the shared recipe creator
        let personalCopy = sharedRecipe.recipe.withOwner(
            userId,
            originalCreatorId: sharedRecipe.sharedBy.id,
            originalCreatorName: sharedRecipe.sharedBy.displayName
        )
        try await recipeRepository.create(personalCopy)
        logger.info("Copied shared recipe '\(personalCopy.title)' to personal collection with ownerId: \(userId)")
        return personalCopy
    }
    
    /// Remove a shared recipe from the list
    func removeSharedRecipe(_ sharedRecipe: SharedRecipe) async throws {
        try await sharingRepository.deleteSharedRecipe(id: sharedRecipe.id)
        logger.info("Removed shared recipe '\(sharedRecipe.recipe.title)'")
    }
    
    /// Get a specific shared recipe by ID
    func getSharedRecipe(id: UUID) async throws -> SharedRecipe? {
        try await sharingRepository.fetchSharedRecipe(id: id)
    }
}
