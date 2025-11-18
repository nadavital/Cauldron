//
//  SharingRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftData
import os

/// Repository for managing shared recipes and users
actor SharingRepository {
    private let modelContainer: ModelContainer
    private let logger = Logger(subsystem: "com.cauldron", category: "SharingRepository")
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    // MARK: - Users
    
    /// Fetch all users
    func fetchAllUsers() async throws -> [User] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserModel>(
            sortBy: [SortDescriptor(\.username)]
        )
        let models = try context.fetch(descriptor)
        return models.map { $0.toDomain() }
    }
    
    /// Search users by username or display name
    func searchUsers(_ query: String) async throws -> [User] {
        let context = ModelContext(modelContainer)
        let lowercasedQuery = query.lowercased()
        
        let descriptor = FetchDescriptor<UserModel>(
            sortBy: [SortDescriptor(\.username)]
        )
        let allUsers = try context.fetch(descriptor)
        
        return allUsers
            .filter { user in
                user.username.lowercased().contains(lowercasedQuery) ||
                user.displayName.lowercased().contains(lowercasedQuery)
            }
            .map { $0.toDomain() }
    }
    
    /// Find user by ID
    func fetchUser(id: UUID) async throws -> User? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<UserModel>(
            predicate: #Predicate { $0.id == id }
        )
        let models = try context.fetch(descriptor)
        return models.first?.toDomain()
    }
    
    /// Save or update a user
    func save(_ user: User) async throws {
        let context = ModelContext(modelContainer)
        
        // Check if user already exists
        let descriptor = FetchDescriptor<UserModel>(
            predicate: #Predicate { $0.id == user.id }
        )
        let existing = try context.fetch(descriptor)
        
        if let existingModel = existing.first {
            // Update existing
            existingModel.username = user.username
            existingModel.displayName = user.displayName
            existingModel.profileEmoji = user.profileEmoji
            existingModel.profileColor = user.profileColor
        } else {
            // Insert new
            let model = UserModel.from(user)
            context.insert(model)
        }
        
        try context.save()
        logger.info("Saved user: \(user.username)")
    }
    
    // MARK: - Shared Recipes
    
    /// Fetch all shared recipes
    func fetchAllSharedRecipes() async throws -> [SharedRecipe] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SharedRecipeModel>(
            sortBy: [SortDescriptor(\.sharedAt, order: .reverse)]
        )
        let models = try context.fetch(descriptor)
        
        return try models.compactMap { model in
            try? model.toDomain()
        }
    }
    
    /// Find shared recipe by ID
    func fetchSharedRecipe(id: UUID) async throws -> SharedRecipe? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SharedRecipeModel>(
            predicate: #Predicate { $0.id == id }
        )
        let models = try context.fetch(descriptor)
        return try models.first?.toDomain()
    }
    
    /// Save a shared recipe
    func saveSharedRecipe(_ sharedRecipe: SharedRecipe) async throws {
        let context = ModelContext(modelContainer)
        
        // Check if shared recipe already exists
        let descriptor = FetchDescriptor<SharedRecipeModel>(
            predicate: #Predicate { $0.id == sharedRecipe.id }
        )
        let existing = try context.fetch(descriptor)
        
        if existing.isEmpty {
            let model = try SharedRecipeModel.from(sharedRecipe)
            context.insert(model)
            try context.save()
            logger.info("Saved shared recipe: \(sharedRecipe.recipe.title)")
        }
    }
    

    

}
