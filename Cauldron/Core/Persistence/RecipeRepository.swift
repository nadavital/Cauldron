//
//  RecipeRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// Thread-safe repository for Recipe operations
actor RecipeRepository {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// Create a new recipe
    func create(_ recipe: Recipe) async throws {
        let context = ModelContext(modelContainer)
        let model = try RecipeModel.from(recipe)
        context.insert(model)
        try context.save()
    }
    
    /// Fetch a recipe by ID
    func fetch(id: UUID) async throws -> Recipe? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            return nil
        }
        return try model.toDomain()
    }
    
    /// Fetch all recipes
    func fetchAll() async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Search recipes by title
    func search(title: String) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let lowercaseTitle = title.lowercased()
        
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.title.localizedStandardContains(lowercaseTitle)
            },
            sortBy: [SortDescriptor(\.title)]
        )
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Search recipes by tag
    func search(tag: String) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>()
        let models = try context.fetch(descriptor)
        
        // Filter by tag in memory (since tags are in blob)
        let recipes = try models.map { try $0.toDomain() }
        return recipes.filter { recipe in
            recipe.tags.contains { $0.name.localizedCaseInsensitiveContains(tag) }
        }
    }
    
    /// Update a recipe
    func update(_ recipe: Recipe) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == recipe.id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        // Update fields
        let encoder = JSONEncoder()
        model.title = recipe.title
        model.ingredientsBlob = try encoder.encode(recipe.ingredients)
        model.stepsBlob = try encoder.encode(recipe.steps)
        model.tagsBlob = try encoder.encode(recipe.tags)
        model.yields = recipe.yields
        model.totalMinutes = recipe.totalMinutes
        model.nutritionBlob = try recipe.nutrition.map { try encoder.encode($0) }
        model.sourceURL = recipe.sourceURL?.absoluteString
        model.sourceTitle = recipe.sourceTitle
        model.notes = recipe.notes
        model.imageURL = recipe.imageURL?.absoluteString
        model.updatedAt = Date()
        
        try context.save()
    }
    
    /// Delete a recipe
    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        context.delete(model)
        try context.save()
    }
    
    /// Fetch recent recipes
    func fetchRecent(limit: Int = 10) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<RecipeModel>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        let models = try context.fetch(descriptor)
        return try models.map { try $0.toDomain() }
    }
    
    /// Toggle favorite status for a recipe
    func toggleFavorite(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        model.isFavorite.toggle()
        model.updatedAt = Date()
        try context.save()
    }
}

enum RepositoryError: Error, LocalizedError {
    case notFound
    case invalidData
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .invalidData:
            return "Invalid data format"
        case .saveFailed:
            return "Failed to save changes"
        }
    }
}
