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
    private let userCloudService: UserCloudService
    private let connectionCloudService: ConnectionCloudService
    private let recipeCloudService: RecipeCloudService
    private let logger = Logger(subsystem: "com.cauldron", category: "SharingService")

    init(
        sharingRepository: SharingRepository,
        recipeRepository: RecipeRepository,
        userCloudService: UserCloudService,
        connectionCloudService: ConnectionCloudService,
        recipeCloudService: RecipeCloudService
    ) {
        self.sharingRepository = sharingRepository
        self.recipeRepository = recipeRepository
        self.userCloudService = userCloudService
        self.connectionCloudService = connectionCloudService
        self.recipeCloudService = recipeCloudService
    }
    
    // MARK: - User Management

    /// Get all users available for sharing (fetches from CloudKit and caches locally)
    func getAllUsers() async throws -> [User] {
        // Fetch from CloudKit PUBLIC database to get latest users
        do {
            let cloudUsers = try await userCloudService.fetchAllUsers()

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
        let users = try await userCloudService.searchUsers(query: query)
        logger.info("Found \(users.count) users matching '\(query)' in CloudKit")
        return users
    }
    
    /// Create or update a user (for demo purposes)
    func saveUser(_ user: User) async throws {
        try await sharingRepository.save(user)
    }
    
    /// Get specific users by their IDs
    func getUsers(byIds userIds: [UUID]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }
        
        // Try to fetch from CloudKit
        do {
            let users = try await userCloudService.fetchUsers(byUserIds: userIds)
            
            // Cache fetched users
            for user in users {
                try? await sharingRepository.save(user)
            }
            
            return users
        } catch {
            logger.warning("Failed to fetch users from CloudKit, checking local cache: \(error.localizedDescription)")
            
            // Fallback to local cache
            var users: [User] = []
            for id in userIds {
                if let user = try? await sharingRepository.fetchUser(id: id) {
                    users.append(user)
                }
            }
            return users
        }
    }
    
    // MARK: - Recipe Sharing

    /// Get all recipes shared with the current user (from PUBLIC database)
    /// Fetches public recipes from friends
    ///
    /// NOTE: These are recipes available for browsing, but not necessarily saved to the user's collection.
    /// To save a recipe for later, users must explicitly add it to their personal collection via "Add to My Recipes".
    func getSharedRecipes() async throws -> [SharedRecipe] {
        // Fetching shared recipes (don't log routine operations)

        // Get current user to know who we are
        let currentUser = await MainActor.run { CurrentUserSession.shared.currentUser }
        guard let currentUser = currentUser else {
            logger.warning("No current user - cannot fetch shared recipes")
            return []
        }

        // Get connected friends from CloudKit
        let connections = try await connectionCloudService.fetchConnections(forUserId: currentUser.id)
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

        // Found connected friends (don't log routine operations)

        var allSharedRecipes: [SharedRecipe] = []

        // Fetch public recipes from friends
        if !friendIds.isEmpty {
            let friendsPublicRecipes = try await recipeCloudService.querySharedRecipes(
                ownerIds: friendIds,
                visibility: .publicRecipe
            )
            // Found public recipes (don't log routine operations)

            // Filter out recipes that are only referenced by other recipes (to avoid duplicates)
            // A recipe that appears in another recipe's relatedRecipeIds should not be shown separately
            let referencedIds = Set(friendsPublicRecipes.flatMap { $0.relatedRecipeIds })
            let filteredRecipes = friendsPublicRecipes.filter { !referencedIds.contains($0.id) }

            // Batch fetch all owners at once to avoid N+1 queries
            let ownerIds = Set(filteredRecipes.compactMap { $0.ownerId })
            let owners = try await userCloudService.fetchUsers(byUserIds: Array(ownerIds))
            let ownersMap = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, $0) })

            // Convert to SharedRecipe objects using the pre-fetched owners
            for recipe in filteredRecipes {
                // Skip if already added (shouldn't happen but be safe)
                if allSharedRecipes.contains(where: { $0.recipe.id == recipe.id }) {
                    continue
                }

                if let ownerId = recipe.ownerId,
                   let owner = ownersMap[ownerId] {
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

        // Return shared recipes (don't log routine operations)
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
    

    
    /// Get a specific shared recipe by ID
    func getSharedRecipe(id: UUID) async throws -> SharedRecipe? {
        try await sharingRepository.fetchSharedRecipe(id: id)
    }
}
