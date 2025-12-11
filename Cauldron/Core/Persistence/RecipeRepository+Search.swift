//
//  RecipeRepository+Search.swift
//  Cauldron
//
//  Created by Nadav Avital on 12/10/25.
//

import Foundation
import SwiftData
import os
import CloudKit
import UIKit

extension RecipeRepository {
    
    // MARK: - Search
    
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
    
    /// Check if a similar recipe already exists
    /// Uses title and ingredient count as heuristics to detect duplicates
    func hasSimilarRecipe(title: String, ownerId: UUID, ingredientCount: Int) async throws -> Bool {
        let context = ModelContext(modelContainer)

        // Fetch all recipes owned by this user
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.ownerId == ownerId
            }
        )

        let models = try context.fetch(descriptor)
        let recipes = try models.map { try $0.toDomain() }

        // Check if any recipe has the same title and similar ingredient count
        let hasSimilar = recipes.contains { recipe in
            recipe.title.lowercased() == title.lowercased() &&
            recipe.ingredients.count == ingredientCount
        }

        logger.info("Checking for similar recipe - title: '\(title)', ingredientCount: \(ingredientCount), hasSimilar: \(hasSimilar)")
        return hasSimilar
    }
}
