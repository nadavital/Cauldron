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
    @Published var timeOfDayRecipes: [Recipe] = []
    @Published var quickRecipes: [Recipe] = []
    @Published var onRotationRecipes: [Recipe] = []
    @Published var forgottenFavorites: [Recipe] = []
    @Published var tagRows: [(tag: String, recipes: [Recipe])] = []
    @Published var collections: [Collection] = []
    @Published var friendsRecipes: [SharedRecipe] = []
    @Published var popularRecipes: [Recipe] = []
    @Published var popularRecipeTiers: [UUID: UserTier] = [:]  // Cached owner tiers for sorting
    @Published var popularRecipeOwners: [UUID: User] = [:]  // Cached owner User objects for display
    @Published var friendsRecipeTiers: [UUID: UserTier] = [:]  // Cached tiers for friends' recipes
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
                
                // Load smart recommendations
                self.updateSmartRecommendations()

                // Load friends' recipes and popular recipes in background
                await self.loadSocialRecipes()

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
            
            // Load smart recommendations
            updateSmartRecommendations()

            // Load friends' recipes and popular recipes in background
            await loadSocialRecipes()

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
            
            // Load favorites
            favoriteRecipes = allRecipes.filter { $0.isFavorite }
            
            // Load smart recommendations
            updateSmartRecommendations()

            // Load friends' recipes and popular recipes in background
            await loadSocialRecipes()

            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to load cook tab data: \(error.localizedDescription)")
        }
    }

    /// Load friends' recipes and popular recipes for the social sections
    private func loadSocialRecipes() async {
        // Load friends' recipes
        do {
            let sharedRecipes = try await dependencies.sharingService.getSharedRecipes()
            // Sort by most recent and limit to 15
            friendsRecipes = sharedRecipes.sorted { $0.sharedAt > $1.sharedAt }
                .prefix(15)
                .map { $0 }

            // Fetch tiers for friends who shared recipes
            await fetchFriendsRecipeTiers(for: friendsRecipes)
        } catch {
            AppLogger.general.warning("Failed to load friends' recipes: \(error.localizedDescription)")
        }

        // Load popular public recipes
        do {
            let popular = try await dependencies.cloudKitService.fetchPopularPublicRecipes(limit: 20)

            // Get current user ID to exclude own recipes
            let currentUserId = CurrentUserSession.shared.userId

            // Filter out own recipes
            var filteredRecipes = popular.filter { recipe in
                if let ownerId = recipe.ownerId, let currentUserId = currentUserId {
                    return ownerId != currentUserId
                }
                return true
            }

            // Fetch owner tiers and user objects for display
            await fetchOwnerTiersAndUsers(for: filteredRecipes)

            // Sort by tier boost (higher tier users' recipes appear first)
            filteredRecipes = filteredRecipes.sorted { recipe1, recipe2 in
                let tier1 = recipe1.ownerId.flatMap { popularRecipeTiers[$0] } ?? .apprentice
                let tier2 = recipe2.ownerId.flatMap { popularRecipeTiers[$0] } ?? .apprentice

                // Higher boost first, then by updatedAt for recipes with same tier
                if tier1.searchBoost != tier2.searchBoost {
                    return tier1.searchBoost > tier2.searchBoost
                }
                return recipe1.updatedAt > recipe2.updatedAt
            }

            popularRecipes = Array(filteredRecipes.prefix(15))
        } catch {
            AppLogger.general.warning("Failed to load popular recipes: \(error.localizedDescription)")
        }
    }

    /// Fetch owner tiers and User objects for popular recipes
    private func fetchOwnerTiersAndUsers(for recipes: [Recipe]) async {
        // Collect unique owner IDs
        let ownerIds = Set(recipes.compactMap { $0.ownerId })

        guard !ownerIds.isEmpty else { return }

        do {
            // Fetch user profiles and recipe counts for each owner
            for ownerId in ownerIds {
                // Skip if we already have this owner's data cached
                guard popularRecipeTiers[ownerId] == nil || popularRecipeOwners[ownerId] == nil else { continue }

                // Fetch user profile
                if popularRecipeOwners[ownerId] == nil {
                    if let user = try await dependencies.cloudKitService.fetchUser(byUserId: ownerId) {
                        popularRecipeOwners[ownerId] = user
                    }
                }

                // Fetch recipe count for tier calculation
                if popularRecipeTiers[ownerId] == nil {
                    let ownerRecipes = try await dependencies.cloudKitService.querySharedRecipes(
                        ownerIds: [ownerId],
                        visibility: .publicRecipe
                    )

                    let tier = UserTier.tier(for: ownerRecipes.count)
                    popularRecipeTiers[ownerId] = tier
                }
            }
        } catch {
            AppLogger.general.error("Failed to fetch owner tiers/users: \(error.localizedDescription)")
            // Continue with default tiers (apprentice)
        }
    }

    /// Fetch tiers for friends who shared recipes
    private func fetchFriendsRecipeTiers(for sharedRecipes: [SharedRecipe]) async {
        // Collect unique sharer user IDs
        let sharerIds = Set(sharedRecipes.map { $0.sharedBy.id })

        guard !sharerIds.isEmpty else { return }

        do {
            for sharerId in sharerIds {
                // Skip if already cached
                guard friendsRecipeTiers[sharerId] == nil else { continue }

                // Fetch public recipe count for tier calculation
                let sharerRecipes = try await dependencies.cloudKitService.querySharedRecipes(
                    ownerIds: [sharerId],
                    visibility: .publicRecipe
                )

                let tier = UserTier.tier(for: sharerRecipes.count)
                friendsRecipeTiers[sharerId] = tier
            }
        } catch {
            AppLogger.general.error("Failed to fetch friends' tiers: \(error.localizedDescription)")
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
    
    private func updateSmartRecommendations() {
        // 1. Determine Promoted Tags based on Time of Day & Weekend
        let date = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let isWeekend = calendar.isDateInWeekend(date)
        
        var promotedTags: [String] = []
        
        // Time of Day Logic
        if hour >= 5 && hour < 11 {
            // Morning
            promotedTags.append(contentsOf: ["Breakfast", "Brunch"])
        } else if hour >= 11 && hour < 14 {
            // Lunch
            promotedTags.append(contentsOf: ["Lunch", "Sandwich", "Salad"])
        } else if hour >= 14 && hour < 17 {
            // Afternoon
            promotedTags.append(contentsOf: ["Snack", "Treat"])
        } else if hour >= 17 && hour < 21 {
            // Evening
            promotedTags.append(contentsOf: ["Dinner", "Main Course", "Side Dish"])
        } else {
            // Night (21+) or Early Morning (<5)
            promotedTags.append(contentsOf: ["Dessert", "Drink", "Cocktail", "Late Night"])
        }
        
        // Weekend Logic (Add to existing list)
        if isWeekend {
            // Add weekend-specific vibes
            if hour >= 11 {
                promotedTags.append(contentsOf: ["Appetizer", "Dip", "Finger Food"])
            }
            // Maybe "Brunch" is more relevant on weekends even later?
            if hour >= 11 && hour < 14 {
                 if !promotedTags.contains("Brunch") { promotedTags.append("Brunch") }
            }
        }
        
        // 2. Quick & Easy (<= 30 mins)
        quickRecipes = allRecipes.filter { recipe in
            guard let minutes = recipe.totalMinutes else { return false }
            return minutes <= 30 && minutes > 0
        }
        .shuffled()
        .prefix(10)
        .map { $0 }
        
        // 3. On Rotation & Forgotten Favorites
        Task {
            do {
                let stats = try await dependencies.cookingHistoryRepository.fetchCookingStats()
                let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                
                // On Rotation: Most cooked in last 30 days
                // Since we only track last cooked, we'll use total count as a proxy for "on rotation" 
                // but prioritize those cooked recently
                let rotationCandidates = allRecipes.filter { recipe in
                    guard let stat = stats[recipe.id] else { return false }
                    return stat.lastCooked >= thirtyDaysAgo
                }
                
                onRotationRecipes = rotationCandidates.sorted {
                    let count1 = stats[$0.id]?.count ?? 0
                    let count2 = stats[$1.id]?.count ?? 0
                    return count1 > count2
                }
                .prefix(10)
                .map { $0 }
                
                // Forgotten Favorites: Favorites NOT cooked in last 30 days
                forgottenFavorites = allRecipes.filter { recipe in
                    guard recipe.isFavorite else { return false }
                    
                    if let stat = stats[recipe.id] {
                        return stat.lastCooked < thirtyDaysAgo
                    } else {
                        // Never cooked but is favorite
                        return true
                    }
                }
                .shuffled()
                .prefix(10)
                .map { $0 }
                
                // 4. Dynamic Tag Rows
                var tagGroups: [String: [Recipe]] = [:]
                
                for recipe in allRecipes {
                    for tag in recipe.tags {
                        if tagGroups[tag.name] == nil {
                            tagGroups[tag.name] = []
                        }
                        tagGroups[tag.name]?.append(recipe)
                    }
                }
                
                var finalTagRows: [(tag: String, recipes: [Recipe])] = []
                
                // Add Promoted Rows (Bypass 3+ rule)
                for tag in promotedTags {
                    // Case-insensitive lookup
                    if let recipes = tagGroups.first(where: { $0.key.localizedCaseInsensitiveCompare(tag) == .orderedSame })?.value,
                       !recipes.isEmpty {
                        
                        // Sort by popularity (most cooked first)
                        let sortedRecipes = recipes.sorted {
                            let count1 = stats[$0.id]?.count ?? 0
                            let count2 = stats[$1.id]?.count ?? 0
                            return count1 > count2
                        }
                        
                        // Use the capitalized tag name from our list for display consistency
                        // Check if we already added this tag (to avoid duplicates if logic overlaps)
                        if !finalTagRows.contains(where: { $0.tag == tag }) {
                             finalTagRows.append((tag: tag, recipes: sortedRecipes.prefix(10).map { $0 }))
                        }
                    }
                }
                
                // Add Standard Rows (Apply 3+ rule)
                let standardTags = tagGroups
                    .filter { group in
                        // Exclude if already promoted (check against finalTagRows to be safe)
                        let isPromoted = finalTagRows.contains { $0.tag.localizedCaseInsensitiveCompare(group.key) == .orderedSame }
                        return !isPromoted && group.value.count >= 3
                    }
                    .sorted { $0.value.count > $1.value.count } // Sort by most popular tags (most recipes)
                    .prefix(5) // Limit to top 5 tags to avoid clutter
                    .map { group -> (tag: String, recipes: [Recipe]) in
                        // Sort recipes within the tag by popularity
                        let sortedRecipes = group.value.sorted {
                            let count1 = stats[$0.id]?.count ?? 0
                            let count2 = stats[$1.id]?.count ?? 0
                            return count1 > count2
                        }
                        return (tag: group.key, recipes: sortedRecipes.prefix(10).map { $0 })
                    }
                
                finalTagRows.append(contentsOf: standardTags)
                
                tagRows = finalTagRows
                
            } catch {
                AppLogger.general.error("Failed to fetch cooking stats: \(error.localizedDescription)")
            }
        }
    }
}
