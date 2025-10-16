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
    
    /// Get all users available for sharing
    func getAllUsers() async throws -> [User] {
        try await sharingRepository.fetchAllUsers()
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
    /// Creates a SharedRecipeReference in PUBLIC database so recipient can access it
    func shareRecipe(_ recipe: Recipe, with user: User, from currentUser: User) async throws {
        logger.info("📤 Sharing recipe '\(recipe.title)' with user: \(user.username)")

        // Share via CloudKit PUBLIC database
        try await cloudKitService.shareRecipe(recipe, with: user.id, from: currentUser.id)
        logger.info("✅ Shared via CloudKit PUBLIC database")

        // Also cache locally for offline access and backwards compatibility
        let sharedRecipe = SharedRecipe(
            recipe: recipe,
            sharedBy: currentUser,
            sharedAt: Date()
        )
        try await sharingRepository.saveSharedRecipe(sharedRecipe)
        logger.info("✅ Cached locally for offline access")

        logger.info("🎉 Successfully shared recipe '\(recipe.title)' with \(user.username)")
    }
    
    /// Get all recipes shared with the current user
    /// Fetches from CloudKit first, then falls back to local cache
    func getSharedRecipes() async throws -> [SharedRecipe] {
        logger.info("📥 Fetching shared recipes from CloudKit")

        // For now, return local cached recipes (CloudKit integration in progress)
        // TODO: Implement full CloudKit fetching with recipe resolution
        let localRecipes = try await sharingRepository.fetchAllSharedRecipes()
        logger.info("✅ Fetched \(localRecipes.count) shared recipes from local cache")

        // Future implementation will:
        // 1. Get current user ID
        // 2. Fetch SharedRecipeReferences from CloudKit
        // 3. Resolve references to full recipes
        // 4. Merge with local cache
        // 5. Return combined list

        return localRecipes
    }
    
    /// Copy a shared recipe to the user's personal collection
    func copySharedRecipeToPersonal(_ sharedRecipe: SharedRecipe) async throws -> Recipe {
        let personalCopy = sharedRecipe.createPersonalCopy()
        try await recipeRepository.create(personalCopy)
        logger.info("Copied shared recipe '\(personalCopy.title)' to personal collection")
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
    
    // MARK: - Demo Data
    
    /// Create some demo users for testing (this would come from a backend in production)
    func createDemoUsers() async throws {
        let demoUsers = [
            User(username: "chef_julia", displayName: "Julia Child"),
            User(username: "gordon_ramsay", displayName: "Gordon Ramsay"),
            User(username: "jamie_oliver", displayName: "Jamie Oliver"),
            User(username: "ina_garten", displayName: "Ina Garten"),
            User(username: "alton_brown", displayName: "Alton Brown")
        ]
        
        for user in demoUsers {
            try await sharingRepository.save(user)
        }
        logger.info("Created \(demoUsers.count) demo users")
    }
}
