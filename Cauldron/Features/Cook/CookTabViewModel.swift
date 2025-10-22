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

    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        self.dependencies = dependencies

        // CRITICAL: This is the key to preventing empty state flash!
        // If we have preloaded data from ContentView, use it immediately to populate arrays
        // BEFORE the view body renders. This ensures the view never sees empty arrays.
        if let preloadedData = preloadedData {
            // CRITICAL: Set allRecipes IMMEDIATELY (not in a Task)
            // This happens synchronously during init, so when CookTabView's body renders
            // for the first time, allRecipes is already populated and won't show empty state
            self.allRecipes = preloadedData.allRecipes
            self.hasLoadedInitially = true

            // Calculate derived data asynchronously (cookable & recently cooked)
            // These aren't critical for preventing empty state since they're optional sections
            Task { @MainActor in
                // Load cookable recipes (based on pantry)
                self.cookableRecipes = try await dependencies.recommender.filterCookableNow(from: preloadedData.allRecipes)

                // Load recently cooked (simple filter, very fast)
                self.recentlyCookedRecipes = preloadedData.allRecipes.filter {
                    preloadedData.recentlyCookedIds.contains($0.id)
                }

                AppLogger.general.info("Cook tab initialized with preloaded data: \(preloadedData.allRecipes.count) recipes")
            }
        } else {
            // Fallback: Load data if not preloaded (e.g., in previews or when returning from onboarding)
            // This will show empty state briefly, but that's acceptable for these edge cases
            Task { @MainActor in
                await loadDataSilently()
            }
        }
    }

    /// Get the reference ID for a recipe (if it's a reference)
    func getReferenceId(for recipeId: UUID) -> UUID? {
        recipeToReferenceMap[recipeId]
    }

    /// Load data without showing loading state changes (for initial load)
    private func loadDataSilently() async {
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
