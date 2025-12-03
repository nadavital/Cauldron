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
