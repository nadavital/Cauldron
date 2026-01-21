//
//  SharingTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
class FriendsTabViewModel: ObservableObject {
    static let shared = FriendsTabViewModel()

    @Published var sharedRecipes: [SharedRecipe] = []
    @Published var sharedCollections: [Collection] = []
    @Published var isLoading = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""

    // Organized sections for better UX
    @Published var recentlyAdded: [SharedRecipe] = []
    @Published var tagSections: [(tag: String, recipes: [SharedRecipe])] = []

    // Tier information for shared recipe creators
    @Published var sharerTiers: [UUID: UserTier] = [:]

    private(set) var dependencies: DependencyContainer?
    private var hasLoadedOnce = false

    private init() {
        // Private init for singleton
    }

    func configure(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func loadSharedRecipes() async {
        guard let dependencies = dependencies else {
            AppLogger.general.warning("FriendsTabViewModel not configured with dependencies")
            return
        }

        // Only show loading indicator on first load
        // After that, show cached data while refreshing in background
        if !hasLoadedOnce {
            isLoading = true
        }
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            sharedRecipes = try await dependencies.sharingService.getSharedRecipes()
            // Loaded shared recipes (don't log routine operations)

            // Load shared collections from friends
            await loadSharedCollections()

            // Fetch tier information for sharers
            await fetchSharerTiers()

            // CRITICAL: Preload images into memory cache to prevent flickering
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

        // OPTIMIZATION: Check if all images are already in cache
        // If so, skip the entire preload process
        var needsPreload = false
        for sharedRecipe in sharedRecipes {
            let recipeKey = ImageCache.recipeImageKey(recipeId: sharedRecipe.recipe.id)
            let profileKey = ImageCache.profileImageKey(userId: sharedRecipe.sharedBy.id)

            if ImageCache.shared.get(recipeKey) == nil || ImageCache.shared.get(profileKey) == nil {
                needsPreload = true
                break
            }
        }

        // If all images are already cached, skip preloading entirely
        guard needsPreload else {
            // Images already cached, skip preload (don't log routine operations)
            return
        }

        // Preloading images (don't log routine operations)

        await withTaskGroup(of: (String, UIImage?).self) { group in
            for sharedRecipe in sharedRecipes {
                // Preload recipe image
                let recipeId = sharedRecipe.recipe.id
                group.addTask { @MainActor in
                    let cacheKey = ImageCache.recipeImageKey(recipeId: recipeId)

                    // Skip if already in cache
                    if ImageCache.shared.get(cacheKey) != nil {
                        return (cacheKey, nil)
                    }

                    // Try to load from local file
                    if let imageURL = sharedRecipe.recipe.imageURL,
                       let imageData = try? Data(contentsOf: imageURL),
                       let image = UIImage(data: imageData) {
                        return (cacheKey, image)
                    }

                    return (cacheKey, nil)
                }

                // Preload profile avatar
                let userId = sharedRecipe.sharedBy.id
                group.addTask { @MainActor in
                    let cacheKey = ImageCache.profileImageKey(userId: userId)

                    // Skip if already in cache
                    if ImageCache.shared.get(cacheKey) != nil {
                        return (cacheKey, nil)
                    }

                    // Try to load from local file
                    if let imageURL = sharedRecipe.sharedBy.profileImageURL,
                       let imageData = try? Data(contentsOf: imageURL),
                       let image = UIImage(data: imageData) {
                        return (cacheKey, image)
                    }

                    return (cacheKey, nil)
                }
            }

            // Collect results and store in cache
            for await (cacheKey, image) in group {
                if let image = image {
                    ImageCache.shared.set(cacheKey, image: image)
                }
            }
        }

        // Finished preloading images (don't log routine operations)
    }

    /// Load shared collections from friends
    private func loadSharedCollections() async {
        guard let dependencies = dependencies else { return }

        do {
            guard let currentUserId = CurrentUserSession.shared.userId else {
                sharedCollections = []
                return
            }

            // Get list of friend user IDs
            let connections = try await dependencies.connectionRepository.fetchAcceptedConnections(forUserId: currentUserId)

            let friendIds = connections.compactMap { connection in
                connection.otherUserId(currentUserId: currentUserId)
            }

            guard !friendIds.isEmpty else {
                sharedCollections = []
                return
            }

            // Fetch shared collections from friends
            sharedCollections = try await dependencies.cloudKitService.fetchSharedCollections(friendIds: friendIds)
            // Loaded shared collections (don't log routine operations)
        } catch {
            AppLogger.general.warning("Failed to load shared collections: \(error.localizedDescription)")
            sharedCollections = []
            // Non-critical failure - don't show error alert
        }
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
                let sharerRecipes = try await dependencies.cloudKitService.querySharedRecipes(
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
