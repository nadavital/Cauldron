//
//  CookTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
class CookTabViewModel: ObservableObject {
    @Published var allRecipes: [Recipe] = []
    @Published var cookableRecipes: [Recipe] = []
    @Published var recentlyCookedRecipes: [Recipe] = []
    @Published var isLoading = false

    let dependencies: DependencyContainer
    private var hasLoadedInitially = false

    // Map from recipe ID to reference ID (for referenced recipes only)
    private var recipeToReferenceMap: [UUID: UUID] = [:]

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Eagerly load data synchronously on init if possible
        Task {
            await loadDataSilently()
        }
    }

    /// Get the reference ID for a recipe (if it's a reference)
    func getReferenceId(for recipeId: UUID) -> UUID? {
        recipeToReferenceMap[recipeId]
    }

    /// Load data without triggering loading state (for initial load)
    private func loadDataSilently() async {
        do {
            // Load all recipes (owned + referenced)
            allRecipes = try await fetchAllRecipesIncludingReferences()

            // Load cookable recipes (based on pantry)
            cookableRecipes = try await dependencies.recommender.filterCookableNow(from: allRecipes)

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }
        } catch {
            AppLogger.general.error("Failed to silently load cook tab data: \(error.localizedDescription)")
        }
    }

    /// Fetch all recipes including both owned recipes and referenced shared recipes
    private func fetchAllRecipesIncludingReferences() async throws -> [Recipe] {
        // Load owned recipes from local storage
        var recipes = try await dependencies.recipeRepository.fetchAll()

        // Clear the reference map
        recipeToReferenceMap.removeAll()

        // Load recipe references if user is logged in and CloudKit is available
        if CurrentUserSession.shared.isCloudSyncAvailable,
           let userId = CurrentUserSession.shared.userId {
            do {
                // Fetch recipe references from CloudKit
                let references = try await dependencies.cloudKitService.fetchRecipeReferences(forUserId: userId)
                AppLogger.general.info("Fetched \(references.count) recipe references from CloudKit")

                // Fetch full recipes for each reference
                for reference in references {
                    do {
                        let recipe = try await dependencies.cloudKitService.fetchPublicRecipe(
                            recipeId: reference.originalRecipeId,
                            ownerId: reference.originalOwnerId
                        )

                        // Only add if not already in owned recipes (avoid duplicates)
                        if !recipes.contains(where: { $0.id == recipe.id }) {
                            recipes.append(recipe)
                            // Track the mapping from recipe ID to reference ID
                            recipeToReferenceMap[recipe.id] = reference.id
                        }
                    } catch {
                        AppLogger.general.warning("Failed to fetch referenced recipe \(reference.recipeTitle): \(error.localizedDescription)")
                        // Continue with other references even if one fails
                    }
                }

                AppLogger.general.info("Total recipes including references: \(recipes.count)")
            } catch {
                AppLogger.general.warning("Failed to fetch recipe references (continuing with owned recipes only): \(error.localizedDescription)")
                // Don't fail completely - just show owned recipes
            }
        }

        return recipes
    }

    func loadData(forceSync: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        // Only sync if explicitly requested (pull-to-refresh)
        if forceSync && CurrentUserSession.shared.isCloudSyncAvailable,
           let userId = CurrentUserSession.shared.userId {
            do {
                try await dependencies.recipeSyncService.performFullSync(for: userId)
                AppLogger.general.info("Recipe sync completed via pull-to-refresh")
            } catch {
                AppLogger.general.warning("Recipe sync failed (continuing): \(error.localizedDescription)")
                // Don't block loading if sync fails
            }
        }

        do {
            // Load all recipes (owned + referenced)
            allRecipes = try await fetchAllRecipesIncludingReferences()

            // Load cookable recipes (based on pantry)
            cookableRecipes = try await dependencies.recommender.filterCookableNow(from: allRecipes)

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }

            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to load cook tab data: \(error.localizedDescription)")
        }
    }
}
