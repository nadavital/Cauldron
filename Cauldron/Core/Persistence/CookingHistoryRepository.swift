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
    func fetchRecentlyCookedRecipes(limit: Int = 10) throws -> [(recipeId: UUID, recipeTitle: String, cookedAt: Date)] {
        guard limit > 0 else { return [] }
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<CookingHistoryModel>(
            sortBy: [SortDescriptor(\.cookedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        let models = try context.fetch(descriptor)
        return models.map { (recipeId: $0.recipeId, recipeTitle: $0.recipeTitle, cookedAt: $0.cookedAt) }
    }
    
    /// Get unique recently cooked recipe IDs (no duplicates)
    func fetchUniqueRecentlyCookedRecipeIds(limit: Int = 10) throws -> [UUID] {
        guard limit > 0 else { return [] }
        let context = ModelContext(modelContainer)
        let pageSize = max(limit * 2, 20)
        var seen = Set<UUID>()
        var unique: [UUID] = []
        var offset = 0

        while unique.count < limit {
            var descriptor = FetchDescriptor<CookingHistoryModel>(
                sortBy: [SortDescriptor(\.cookedAt, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let page = try context.fetch(descriptor)
            guard !page.isEmpty else { break }

            for entry in page where seen.insert(entry.recipeId).inserted {
                unique.append(entry.recipeId)
                if unique.count == limit {
                    return unique
                }
            }

            guard page.count == pageSize else { break }
            offset += page.count
        }

        return unique
    }
    
    /// Fetch cooking statistics, optionally scoped to the recipes visible to the caller.
    /// Returns a dictionary mapping recipe ID to (count, lastCookedDate)
    func fetchCookingStats(for recipeIds: [UUID]? = nil) throws -> [UUID: (count: Int, lastCooked: Date)] {
        let context = ModelContext(modelContainer)
        let descriptor: FetchDescriptor<CookingHistoryModel>
        if let recipeIds {
            guard !recipeIds.isEmpty else { return [:] }
            descriptor = FetchDescriptor<CookingHistoryModel>(
                predicate: #Predicate { history in
                    recipeIds.contains(history.recipeId)
                }
            )
        } else {
            descriptor = FetchDescriptor<CookingHistoryModel>()
        }
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
