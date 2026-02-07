//
//  SharingTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import os

@MainActor
@Observable
final class FriendsTabViewModel {
    static let shared = FriendsTabViewModel()

    var sharedRecipes: [SharedRecipe] = []
    var isLoading = false
    var showSuccessAlert = false
    var showErrorAlert = false
    var alertMessage = ""

    // Organized sections for better UX
    var recentlyAdded: [SharedRecipe] = []
    var tagSections: [(tag: String, recipes: [SharedRecipe])] = []

    // Tier information for shared recipe creators
    var sharerTiers: [UUID: UserTier] = [:]

    @ObservationIgnored
    private(set) var dependencies: DependencyContainer?
    @ObservationIgnored
    private var hasLoadedOnce = false

    private init() {
        // Private init for singleton
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func configure(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func loadSharedRecipes(forceRefresh: Bool = false) async {
        guard let dependencies = dependencies else {
            AppLogger.general.warning("FriendsTabViewModel not configured with dependencies")
            return
        }

        // On first load, try to use cached data for instant display
        if !hasLoadedOnce {
            if let cached = await dependencies.sharingService.getCachedSharedRecipes() {
                // Show cached data immediately
                sharedRecipes = cached
                organizeRecipesIntoSections()
                await preloadImagesForSharedRecipes()
                hasLoadedOnce = true

                // Fetch tiers in background
                await fetchSharerTiers()
                return
            }
            // No cache, show loading indicator
            isLoading = true
        }

        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            sharedRecipes = try await dependencies.sharingService.getSharedRecipes(forceRefresh: forceRefresh)

            // Fetch tier information for sharers
            await fetchSharerTiers()

            // Preload images into memory cache to prevent flickering
            await preloadImagesForSharedRecipes()

            // Organize recipes into sections for better UX
            organizeRecipesIntoSections()
        } catch {
            AppLogger.general.error("Failed to load shared recipes: \(error.localizedDescription)")
            alertMessage = "Failed to load shared recipes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Organize shared recipes into curated sections
    private func organizeRecipesIntoSections() {
        // Recently Added - recipes shared in the last 7 days, sorted by date
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        recentlyAdded = sharedRecipes
            .filter { $0.sharedAt > sevenDaysAgo }
            .sorted { $0.sharedAt > $1.sharedAt }

        // Tag-based sections - group recipes by their tags
        var tagGroups: [String: [SharedRecipe]] = [:]
        for sharedRecipe in sharedRecipes {
            for tag in sharedRecipe.recipe.tags {
                tagGroups[tag.name, default: []].append(sharedRecipe)
            }
        }

        // Only include tags with at least 3 recipes
        tagSections = tagGroups
            .filter { $0.value.count >= 3 }
            .map { (tag: $0.key, recipes: $0.value.sorted { $0.sharedAt > $1.sharedAt }) }
            .sorted { $0.recipes.count > $1.recipes.count } // Sort by number of recipes
    }

    /// Preload recipe images and profile avatars into memory cache
    /// This prevents flickering when scrolling through shared recipes
    private func preloadImagesForSharedRecipes() async {
        guard let dependencies = dependencies else { return }
        await dependencies.entityImageLoader.preloadSharedRecipeAndProfileImages(sharedRecipes: sharedRecipes)
    }

    func copyToPersonalCollection(_ sharedRecipe: SharedRecipe) async {
        guard let dependencies = dependencies else { return }
        do {
            let copiedRecipe = try await dependencies.sharingService.copySharedRecipeToPersonal(sharedRecipe)
            AppLogger.general.info("Copied shared recipe to personal collection: \(copiedRecipe.title)")
            // Toast notification is shown in RecipeDetailView
        } catch {
            AppLogger.general.error("Failed to copy recipe: \(error.localizedDescription)")
            alertMessage = "Failed to copy recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Fetch tier information for users who shared recipes
    private func fetchSharerTiers() async {
        guard let dependencies = dependencies else { return }

        // Collect unique sharer user IDs
        let sharerIds = Set(sharedRecipes.map { $0.sharedBy.id })

        guard !sharerIds.isEmpty else { return }

        do {
            for sharerId in sharerIds {
                // Skip if already cached
                guard sharerTiers[sharerId] == nil else { continue }

                // Fetch public recipe count for tier calculation
                let sharerRecipes = try await dependencies.recipeCloudService.querySharedRecipes(
                    ownerIds: [sharerId],
                    visibility: .publicRecipe
                )

                let tier = UserTier.tier(for: sharerRecipes.count)
                sharerTiers[sharerId] = tier
            }
        } catch {
            AppLogger.general.error("Failed to fetch sharer tiers: \(error.localizedDescription)")
        }
    }
}
