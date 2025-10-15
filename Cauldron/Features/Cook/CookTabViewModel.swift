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

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Eagerly load data synchronously on init if possible
        Task {
            await loadDataSilently()
        }
    }

    /// Load data without triggering loading state (for initial load)
    private func loadDataSilently() async {
        do {
            // Load all recipes
            allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Load cookable recipes (based on pantry)
            cookableRecipes = try await dependencies.recommender.filterCookableNow(from: allRecipes)

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }
        } catch {
            AppLogger.general.error("Failed to silently load cook tab data: \(error.localizedDescription)")
        }
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
            // Load all recipes (from cache if already loaded during app init)
            allRecipes = try await dependencies.recipeRepository.fetchAll()

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
