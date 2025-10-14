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
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        // Trigger sync if user is authenticated and CloudKit available
        if let userId = CurrentUserSession.shared.userId,
           CurrentUserSession.shared.isCloudSyncAvailable {
            do {
                try await dependencies.recipeSyncService.performFullSync(for: userId)
                AppLogger.general.info("Recipe sync completed via pull-to-refresh")
            } catch {
                AppLogger.general.warning("Recipe sync failed (continuing): \(error.localizedDescription)")
                // Don't block loading if sync fails
            }
        }

        do {
            // Load all recipes
            allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Load cookable recipes (based on pantry)
            cookableRecipes = try await dependencies.recommender.filterCookableNow(from: allRecipes)

            // Load recently cooked
            let recentIds = try await dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10)
            recentlyCookedRecipes = allRecipes.filter { recentIds.contains($0.id) }

        } catch {
            AppLogger.general.error("Failed to load cook tab data: \(error.localizedDescription)")
        }
    }
}
