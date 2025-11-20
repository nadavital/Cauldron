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
    @Published var recentlyCookedRecipes: [Recipe] = []
    @Published var favoriteRecipes: [Recipe] = []
    @Published var collections: [Collection] = []
    @Published var isLoading = false

    let dependencies: DependencyContainer
    private var hasLoadedInitially = false


    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        self.dependencies = dependencies

        // CRITICAL: This is the key to preventing empty state flash!
        // If we have preloaded data from ContentView, use it immediately to populate arrays
        // BEFORE the view body renders. This ensures the view never sees empty arrays.
        if let preloadedData = preloadedData {
            // CRITICAL: Set allRecipes and collections IMMEDIATELY (not in a Task)
            // This happens synchronously during init, so when CookTabView's body renders
            // for the first time, allRecipes and collections are already populated and won't show empty state
            self.allRecipes = preloadedData.allRecipes
            self.collections = preloadedData.collections.sorted { $0.updatedAt > $1.updatedAt }
            self.hasLoadedInitially = true

            // Calculate derived data asynchronously (recently cooked and favorites)
            // This isn't critical for preventing empty state since it's an optional section
            Task { @MainActor in
                // Load recently cooked (simple filter, very fast)
                self.recentlyCookedRecipes = preloadedData.allRecipes.filter {
                    preloadedData.recentlyCookedIds.contains($0.id)
                }

                // Load favorites (simple filter, very fast)
                self.favoriteRecipes = preloadedData.allRecipes.filter { $0.isFavorite }

                // Cook tab initialized with preloaded data (don't log routine operations)
            }
        } else {
            // Fallback: Load data if not preloaded (e.g., in previews or when returning from onboarding)
            // This will show empty state briefly, but that's acceptable for these edge cases
            Task { @MainActor in
                await loadDataSilently()
            }
        }
    }

    /// Load data without showing loading state changes (for initial load)
    private func loadDataSilently() async {
        do {
            // Load all recipes (owned + referenced)
            allRecipes = try await fetchAllRecipesIncludingReferences()

            // Load collections
            collections = try await dependencies.collectionRepository.fetchAll()
            collections.sort { $0.updatedAt > $1.updatedAt }

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }

            // Load favorites
            favoriteRecipes = allRecipes.filter { $0.isFavorite }

            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to silently load cook tab data: \(error.localizedDescription)")
        }
    }

    /// Fetch all recipes (owned recipes only - references have been deprecated)
    private func fetchAllRecipesIncludingReferences() async throws -> [Recipe] {
        // Load owned recipes from local storage
        let recipes = try await dependencies.recipeRepository.fetchAll()

        AppLogger.general.info("Total recipes: \(recipes.count)")

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

            // Load collections
            collections = try await dependencies.collectionRepository.fetchAll()
            collections.sort { $0.updatedAt > $1.updatedAt }

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }

            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to load cook tab data: \(error.localizedDescription)")
        }
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func getRecipeImages(for collection: Collection) async -> [URL?] {
        // Filter to only recipes in this collection
        let collectionRecipes = allRecipes.filter { recipe in
            collection.recipeIds.contains(recipe.id)
        }

        // Take first 4 recipes and get their image URLs
        return Array(collectionRecipes.prefix(4).map { $0.imageURL })
    }
}
