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
                model.isPreview == false &&
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
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.isPreview == false
            }
        )
        let models = try context.fetch(descriptor)
        
        // Filter by tag in memory (since tags are in blob)
        let recipes = try models.map { try $0.toDomain() }
        return recipes.filter { recipe in
            recipe.tags.contains { $0.name.localizedCaseInsensitiveContains(tag) }
        }
    }

    /// Fetch owned recipes that are saved copies of the given canonical public recipe IDs.
    func fetchOwnedCopies(
        originalRecipeIds: [UUID],
        ownerId: UUID? = nil,
        followingSourceOnly: Bool = false
    ) async throws -> [Recipe] {
        let originalRecipeIdSet = Set(originalRecipeIds)
        guard !originalRecipeIdSet.isEmpty else { return [] }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.isPreview == false && model.originalRecipeId != nil
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        let models = try context.fetch(descriptor)
        let recipes = try models.map { try $0.toDomain() }
        return recipes.filter { recipe in
            guard let originalRecipeId = recipe.originalRecipeId else {
                return false
            }
            if let ownerId, recipe.ownerId != ownerId {
                return false
            }
            if followingSourceOnly, !recipe.isFollowingSourceUpdates {
                return false
            }
            return originalRecipeIdSet.contains(originalRecipeId)
        }
    }

    /// Resolve related recipe references against local storage, preferring real
    /// library recipes over temporary preview records.
    func resolveLocalRelatedRecipes(
        referenceIds: [UUID],
        includePreviews: Bool,
        preferredOwnerId: UUID? = nil
    ) async throws -> (recipes: [Recipe], missingIds: [UUID]) {
        guard !referenceIds.isEmpty else {
            return ([], [])
        }

        let directMatches = try await fetch(ids: referenceIds)
        let directMatchesById = Dictionary(uniqueKeysWithValues: directMatches.map { ($0.id, $0) })

        let sourceCopyLookupIds = referenceIds.filter { referenceId in
            guard let directMatch = directMatchesById[referenceId] else {
                return true
            }

            if directMatch.isPreview {
                return true
            }

            if let preferredOwnerId, directMatch.ownerId != preferredOwnerId {
                return true
            }

            return false
        }

        let ownedCopies = try await fetchOwnedCopies(
            originalRecipeIds: sourceCopyLookupIds,
            ownerId: preferredOwnerId,
            followingSourceOnly: true
        )
        var ownedCopiesByOriginalId: [UUID: Recipe] = [:]
        for ownedCopy in ownedCopies {
            guard let originalRecipeId = ownedCopy.originalRecipeId else {
                continue
            }

            ownedCopiesByOriginalId[originalRecipeId] = ownedCopiesByOriginalId[originalRecipeId] ?? ownedCopy
        }

        var resolvedRecipes: [Recipe] = []
        var missingIds: [UUID] = []

        for referenceId in referenceIds {
            if let preferredOwnerId,
               let ownedCopy = ownedCopiesByOriginalId[referenceId],
               directMatchesById[referenceId]?.ownerId != preferredOwnerId {
                resolvedRecipes.append(ownedCopy)
            } else if let preferredOwnerId,
                      let directMatch = directMatchesById[referenceId],
                      !directMatch.isPreview,
                      directMatch.ownerId != preferredOwnerId {
                missingIds.append(referenceId)
            } else if let directMatch = directMatchesById[referenceId], !directMatch.isPreview {
                resolvedRecipes.append(directMatch)
            } else if let ownedCopy = ownedCopiesByOriginalId[referenceId] {
                resolvedRecipes.append(ownedCopy)
            } else if includePreviews, let preview = directMatchesById[referenceId] {
                resolvedRecipes.append(preview)
            } else {
                missingIds.append(referenceId)
            }
        }

        return (resolvedRecipes, missingIds)
    }

    /// Remove impossible self-saved copies created when a user saves their own
    /// public recipe. The source recipe remains intact.
    func removeSelfSavedRecipeCopies(currentUserId: UUID) async throws -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.ownerId == currentUserId && model.isPreview == false
            }
        )

        let recipes = try context.fetch(descriptor).map { try $0.toDomain() }
        let ownedOriginalRecipeIds = Set(
            recipes
                .filter { !$0.isFollowingSourceUpdates }
                .map(\.id)
        )

        let duplicateIds = recipes.compactMap { recipe -> UUID? in
            guard recipe.isFollowingSourceUpdates,
                  let originalRecipeId = recipe.originalRecipeId,
                  ownedOriginalRecipeIds.contains(originalRecipeId) else {
                return nil
            }
            return recipe.id
        }

        guard !duplicateIds.isEmpty else { return 0 }

        for duplicateId in duplicateIds {
            try await delete(id: duplicateId)
        }

        logger.info("Removed \(duplicateIds.count) self-saved recipe copies")
        return duplicateIds.count
    }
    
    /// Fetch recent recipes
    func fetchRecent(limit: Int = 10) async throws -> [Recipe] {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.isPreview == false
            },
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
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        // Narrow candidates in the store first, then do the expensive ingredient-count
        // comparison in memory because ingredients live in the model blob.
        var descriptor = FetchDescriptor<RecipeModel>(
            predicate: #Predicate { model in
                model.ownerId == ownerId &&
                model.isPreview == false &&
                model.title.localizedStandardContains(normalizedTitle)
            }
        )
        descriptor.fetchLimit = 25

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
