//
//  CookingHistoryRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import SwiftData

/// Repository for managing cooking history
actor CookingHistoryRepository {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// Record that a recipe was cooked
    @MainActor
    func recordCooked(recipeId: UUID, recipeTitle: String) throws {
        let context = modelContainer.mainContext
        let history = CookingHistoryModel(recipeId: recipeId, recipeTitle: recipeTitle)
        context.insert(history)
        try context.save()
    }
    
    /// Fetch recently cooked recipes
    @MainActor
    func fetchRecentlyCookedRecipes(limit: Int = 10) throws -> [(recipeId: UUID, recipeTitle: String, cookedAt: Date)] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<CookingHistoryModel>(
            sortBy: [SortDescriptor(\.cookedAt, order: .reverse)]
        )
        
        let models = try context.fetch(descriptor)
        return models.prefix(limit).map { (recipeId: $0.recipeId, recipeTitle: $0.recipeTitle, cookedAt: $0.cookedAt) }
    }
    
    /// Get unique recently cooked recipe IDs (no duplicates)
    @MainActor
    func fetchUniqueRecentlyCookedRecipeIds(limit: Int = 10) throws -> [UUID] {
        let all = try fetchRecentlyCookedRecipes(limit: limit * 2) // Fetch more to account for duplicates
        var seen = Set<UUID>()
        var unique: [UUID] = []
        
        for entry in all {
            if !seen.contains(entry.recipeId) {
                seen.insert(entry.recipeId)
                unique.append(entry.recipeId)
                if unique.count >= limit {
                    break
                }
            }
        }
        
        return unique
    }
    
    /// Fetch cooking statistics for all recipes
    /// Returns a dictionary mapping recipe ID to (count, lastCookedDate)
    @MainActor
    func fetchCookingStats() throws -> [UUID: (count: Int, lastCooked: Date)] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<CookingHistoryModel>()
        let history = try context.fetch(descriptor)
        
        var stats: [UUID: (count: Int, lastCooked: Date)] = [:]
        
        for entry in history {
            if let existing = stats[entry.recipeId] {
                stats[entry.recipeId] = (
                    count: existing.count + 1,
                    lastCooked: max(existing.lastCooked, entry.cookedAt)
                )
            } else {
                stats[entry.recipeId] = (count: 1, lastCooked: entry.cookedAt)
            }
        }
        
        return stats
    }
}
