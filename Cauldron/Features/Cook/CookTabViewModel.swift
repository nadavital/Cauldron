//
//  CookTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import SwiftUI
import os

private struct CookTabDerivedSections {
    let quickRecipes: [Recipe]
    let onRotationRecipes: [Recipe]
    let forgottenFavorites: [Recipe]
    let tagRows: [(tag: String, recipes: [Recipe])]

    nonisolated static func build(
        allRecipes: [Recipe],
        stats: [UUID: (count: Int, lastCooked: Date)],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CookTabDerivedSections {
        let hour = calendar.component(.hour, from: now)
        let isWeekend = calendar.isDateInWeekend(now)
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        var promotedTags: [String] = []
        if hour >= 5 && hour < 11 {
            promotedTags.append(contentsOf: ["Breakfast", "Brunch"])
        } else if hour >= 11 && hour < 14 {
            promotedTags.append(contentsOf: ["Lunch", "Sandwich", "Salad"])
        } else if hour >= 14 && hour < 17 {
            promotedTags.append(contentsOf: ["Snack", "Treat"])
        } else if hour >= 17 && hour < 21 {
            promotedTags.append(contentsOf: ["Dinner", "Main Course", "Side Dish"])
        } else {
            promotedTags.append(contentsOf: ["Dessert", "Drink", "Cocktail", "Late Night"])
        }

        if isWeekend {
            if hour >= 11 {
                promotedTags.append(contentsOf: ["Appetizer", "Dip", "Finger Food"])
            }
            if hour >= 11 && hour < 14 && !promotedTags.contains("Brunch") {
                promotedTags.append("Brunch")
            }
        }

        let quickRecipes = allRecipes
            .filter { recipe in
                guard let minutes = recipe.totalMinutes else { return false }
                return minutes <= 30 && minutes > 0
            }
            .shuffled()
            .prefix(10)
            .map { $0 }

        let rotationCandidates = allRecipes.filter { recipe in
            guard let stat = stats[recipe.id] else { return false }
            return stat.lastCooked >= thirtyDaysAgo
        }

        let onRotationRecipes = rotationCandidates.sorted {
            let count1 = stats[$0.id]?.count ?? 0
            let count2 = stats[$1.id]?.count ?? 0
            return count1 > count2
        }
        .prefix(10)
        .map { $0 }

        let forgottenFavorites = allRecipes.filter { recipe in
            guard recipe.isFavorite else { return false }

            if let stat = stats[recipe.id] {
                return stat.lastCooked < thirtyDaysAgo
            }
            return true
        }
        .shuffled()
        .prefix(10)
        .map { $0 }

        var tagGroups: [String: [Recipe]] = [:]
        for recipe in allRecipes {
            for tag in recipe.tags {
                tagGroups[tag.name, default: []].append(recipe)
            }
        }

        var finalTagRows: [(tag: String, recipes: [Recipe])] = []

        for tag in promotedTags {
            if let recipes = tagGroups.first(where: { $0.key.localizedCaseInsensitiveCompare(tag) == .orderedSame })?.value,
               !recipes.isEmpty {
                let sortedRecipes = recipes.sorted {
                    let count1 = stats[$0.id]?.count ?? 0
                    let count2 = stats[$1.id]?.count ?? 0
                    return count1 > count2
                }

                if !finalTagRows.contains(where: { $0.tag == tag }) {
                    finalTagRows.append((tag: tag, recipes: sortedRecipes.prefix(10).map { $0 }))
                }
            }
        }

        let standardTags = tagGroups
            .filter { group in
                let isPromoted = finalTagRows.contains { $0.tag.localizedCaseInsensitiveCompare(group.key) == .orderedSame }
                return !isPromoted && group.value.count >= 3
            }
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)
            .map { group -> (tag: String, recipes: [Recipe]) in
                let sortedRecipes = group.value.sorted {
                    let count1 = stats[$0.id]?.count ?? 0
                    let count2 = stats[$1.id]?.count ?? 0
                    return count1 > count2
                }
                return (tag: group.key, recipes: sortedRecipes.prefix(10).map { $0 })
            }

        finalTagRows.append(contentsOf: standardTags)

        return CookTabDerivedSections(
            quickRecipes: quickRecipes,
            onRotationRecipes: onRotationRecipes,
            forgottenFavorites: forgottenFavorites,
            tagRows: finalTagRows
        )
    }
}

@MainActor
@Observable final class CookTabViewModel {
    var allRecipes: [Recipe] = []
    var recentlyAddedRecipes: [Recipe] = []
    var recentlyCookedRecipes: [Recipe] = []
    var favoriteRecipes: [Recipe] = []
    var timeOfDayRecipes: [Recipe] = []
    var quickRecipes: [Recipe] = []
    var onRotationRecipes: [Recipe] = []
    var forgottenFavorites: [Recipe] = []
    var tagRows: [(tag: String, recipes: [Recipe])] = []
    var collections: [Collection] = []
    var friendsRecipes: [SharedRecipe] = []
    var popularRecipes: [Recipe] = []
    var popularRecipeTiers: [UUID: UserTier] = [:]  // Cached owner tiers for sorting
    var popularRecipeOwners: [UUID: User] = [:]  // Cached owner User objects for display
    var friendsRecipeTiers: [UUID: UserTier] = [:]  // Cached tiers for friends' recipes
    var isLoading = false

    let dependencies: DependencyContainer
    private var hasLoadedInitially = false
    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var smartRecommendationsTask: Task<Void, Never>?
    private var recipeImageURLsById: [UUID: URL?] = [:]

    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        self.dependencies = dependencies
        setupCollectionNotificationObserver()

        // CRITICAL: This is the key to preventing empty state flash!
        // If we have preloaded data from ContentView, use it immediately to populate arrays
        // BEFORE the view body renders. This ensures the view never sees empty arrays.
        if let preloadedData = preloadedData {
            // CRITICAL: Set allRecipes and collections IMMEDIATELY (not in a Task)
            // This happens synchronously during init, so when CookTabView's body renders
            // for the first time, allRecipes and collections are already populated and won't show empty state
            self.allRecipes = preloadedData.allRecipes
            self.recentlyAddedRecipes = preloadedData.allRecipes.sorted { $0.createdAt > $1.createdAt }
            self.collections = preloadedData.collections.sorted { $0.updatedAt > $1.updatedAt }
            self.recipeImageURLsById = preloadedData.allRecipes.reduce(into: [:]) { partialResult, recipe in
                partialResult[recipe.id] = recipe.imageURL
            }
            self.hasLoadedInitially = true

            // Calculate derived data asynchronously (recently cooked and favorites)
            // This isn't critical for preventing empty state since it's an optional section
            Task { @MainActor in
                let recentIdSet = Set(preloadedData.recentlyCookedIds)

                // Load recently cooked (simple filter, very fast)
                self.recentlyCookedRecipes = preloadedData.allRecipes.filter {
                    recentIdSet.contains($0.id)
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

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {
        // Note: Cannot access notificationObserver here as it's isolated
        // NotificationCenter observer cleanup happens automatically
    }

    /// Load data without showing loading state changes (for initial load)
    private func loadDataSilently() async {
        do {
            try await reloadLocalLibrary(loadCollections: true)
            await loadSocialRecipes()
            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to silently load cook tab data: \(error.localizedDescription)")
        }
    }

    /// Setup observer for collection metadata changes to update UI immediately
    private func setupCollectionNotificationObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .collectionMetadataChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let collectionId = notification.userInfo?["collectionId"] as? UUID,
                  let updatedCollection = notification.userInfo?["collection"] as? Collection else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Update the collection in our local array for immediate UI refresh
                if let index = self.collections.firstIndex(where: { $0.id == collectionId }) {
                    self.collections[index] = updatedCollection
                    // Re-sort by updatedAt
                    self.collections.sort { $0.updatedAt > $1.updatedAt }
                }
            }
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
            try await reloadLocalLibrary(loadCollections: true)
            await loadSocialRecipes(forceRefresh: forceSync)
            hasLoadedInitially = true
        } catch {
            AppLogger.general.error("Failed to load cook tab data: \(error.localizedDescription)")
        }
    }

    func refreshLocalLibrary() async {
        do {
            try await reloadLocalLibrary(loadCollections: true)
        } catch {
            AppLogger.general.error("Failed to refresh cook library: \(error.localizedDescription)")
        }
    }

    func refreshCollections() async {
        do {
            collections = try await dependencies.collectionRepository.fetchAll()
            collections.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            AppLogger.general.error("Failed to refresh collections: \(error.localizedDescription)")
        }
    }

    /// Load friends' recipes and popular recipes for the social sections
    private func loadSocialRecipes(forceRefresh: Bool = false) async {
        // Load friends' recipes
        do {
            let sharedRecipes = try await dependencies.sharingService.getSharedRecipes(forceRefresh: forceRefresh)
            // Sort by most recent and limit to 15
            friendsRecipes = sharedRecipes.sorted { $0.sharedAt > $1.sharedAt }
                .prefix(15)
                .map { $0 }

            // Fetch tiers for friends who shared recipes
            await fetchFriendsRecipeTiers(for: friendsRecipes, forceRefresh: forceRefresh)
        } catch {
            AppLogger.general.warning("Failed to load friends' recipes: \(error.localizedDescription)")
        }

        // Load popular public recipes
        do {
            let popular = try await dependencies.recipeDiscoveryCache.fetchPopularPublicRecipes(
                limit: 20,
                forceRefresh: forceRefresh
            )

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
            await fetchOwnerTiersAndUsers(for: filteredRecipes, forceRefresh: forceRefresh)

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
    private func fetchOwnerTiersAndUsers(for recipes: [Recipe], forceRefresh: Bool = false) async {
        // Collect unique owner IDs
        let ownerIds = Set(recipes.compactMap { $0.ownerId })

        guard !ownerIds.isEmpty else { return }

        do {
            let ownerIdsNeedingUsers = forceRefresh ? ownerIds : ownerIds.filter { popularRecipeOwners[$0] == nil }
            let ownerIdsNeedingTiers = forceRefresh ? ownerIds : ownerIds.filter { popularRecipeTiers[$0] == nil }

            if !ownerIdsNeedingUsers.isEmpty {
                let fetchedUsers = try await dependencies.recipeDiscoveryCache.fetchUsers(
                    byUserIds: Array(ownerIdsNeedingUsers),
                    forceRefresh: forceRefresh
                )

                for user in fetchedUsers {
                    popularRecipeOwners[user.id] = user
                }
            }

            if !ownerIdsNeedingTiers.isEmpty {
                let counts = try await dependencies.recipeDiscoveryCache.batchFetchPublicRecipeCounts(
                    forOwnerIds: Array(ownerIdsNeedingTiers),
                    forceRefresh: forceRefresh
                )

                for (ownerId, count) in counts {
                    popularRecipeTiers[ownerId] = UserTier.tier(for: count)
                }
            }
        } catch {
            AppLogger.general.error("Failed to fetch owner tiers/users: \(error.localizedDescription)")
            // Continue with default tiers (apprentice)
        }
    }

    /// Fetch tiers for friends who shared recipes
    private func fetchFriendsRecipeTiers(for sharedRecipes: [SharedRecipe], forceRefresh: Bool = false) async {
        // Collect unique sharer user IDs
        let sharerIds = Set(sharedRecipes.map { $0.sharedBy.id })

        guard !sharerIds.isEmpty else { return }

        do {
            let uncachedSharerIds = forceRefresh ? sharerIds : sharerIds.filter { friendsRecipeTiers[$0] == nil }
            guard !uncachedSharerIds.isEmpty else { return }

            let counts = try await dependencies.recipeDiscoveryCache.batchFetchPublicRecipeCounts(
                forOwnerIds: Array(uncachedSharerIds),
                forceRefresh: forceRefresh
            )

            for (sharerId, count) in counts {
                friendsRecipeTiers[sharerId] = UserTier.tier(for: count)
            }
        } catch {
            AppLogger.general.error("Failed to fetch friends' tiers: \(error.localizedDescription)")
        }
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func getRecipeImages(for collection: Collection) -> [URL?] {
        Array(collection.recipeIds.prefix(4).map { recipeImageURLsById[$0] ?? nil })
    }

    func getRecipeImageSources(for collection: Collection) -> [CollectionRecipeImageSource] {
        collection.recipeIds.prefix(4).map { recipeId in
            let recipe = allRecipes.first { $0.id == recipeId }
            return CollectionRecipeImageSource(
                recipeId: recipeId,
                imageURL: recipe?.imageURL ?? recipeImageURLsById[recipeId] ?? nil,
                ownerId: recipe?.ownerId,
                hasCloudImage: recipe?.cloudImageRecordName != nil
            )
        }
    }

    private func rebuildRecipeImageLookup() {
        recipeImageURLsById = allRecipes.reduce(into: [:]) { partialResult, recipe in
            partialResult[recipe.id] = recipe.imageURL
        }
    }

    private func reloadLocalLibrary(loadCollections: Bool) async throws {
        async let fetchedRecipes = fetchAllRecipesIncludingReferences()

        let recipes = try await fetchedRecipes
        let recentIdSet = Set(try dependencies.cookingHistoryRepository.fetchUniqueRecentlyCookedRecipeIds(limit: 10))

        allRecipes = recipes
        recentlyAddedRecipes = recipes.sorted { $0.createdAt > $1.createdAt }
        rebuildRecipeImageLookup()
        recentlyCookedRecipes = recipes.filter { recentIdSet.contains($0.id) }
        favoriteRecipes = recipes.filter { $0.isFavorite }
        updateSmartRecommendations()

        if loadCollections {
            collections = try await dependencies.collectionRepository.fetchAll()
            collections.sort { $0.updatedAt > $1.updatedAt }
        }
    }
    
    private func updateSmartRecommendations() {
        let allRecipes = self.allRecipes
        smartRecommendationsTask?.cancel()
        smartRecommendationsTask = Task { @MainActor in
            do {
                let stats = try dependencies.cookingHistoryRepository.fetchCookingStats()
                let derivedSections = await Task.detached(priority: .utility) {
                    CookTabDerivedSections.build(allRecipes: allRecipes, stats: stats)
                }.value

                guard !Task.isCancelled else { return }
                quickRecipes = derivedSections.quickRecipes
                onRotationRecipes = derivedSections.onRotationRecipes
                forgottenFavorites = derivedSections.forgottenFavorites
                tagRows = derivedSections.tagRows
            } catch {
                AppLogger.general.error("Failed to fetch cooking stats: \(error.localizedDescription)")
            }
        }
    }
}
