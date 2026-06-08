//
//  SearchTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os



/// Cooking-time filter for recipe search.
enum RecipeTimeFilter: String, CaseIterable, Identifiable {
    case any, under15, under30, under60, over60

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return "Any time"
        case .under15: return "Under 15 min"
        case .under30: return "Under 30 min"
        case .under60: return "Under 60 min"
        case .over60: return "60 min+"
        }
    }

    /// Whether a recipe with the given total minutes passes this filter.
    /// Recipes without a known time only pass `.any`.
    func matches(minutes: Int?) -> Bool {
        guard self != .any else { return true }
        guard let minutes else { return false }
        switch self {
        case .any: return true
        case .under15: return minutes < 15
        case .under30: return minutes < 30
        case .under60: return minutes < 60
        case .over60: return minutes >= 60
        }
    }
}

/// Sort order for recipe search results.
enum RecipeSortOrder: String, CaseIterable, Identifiable {
    case relevance, quickest, alphabetical, newest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .quickest: return "Quickest"
        case .alphabetical: return "A–Z"
        case .newest: return "Newest"
        }
    }
}

@MainActor
@Observable final class SearchTabViewModel {
    var allRecipes: [Recipe] = [] // User's own recipes
    var publicRecipes: [Recipe] = [] // All public recipes from CloudKit
    var recipesByTag: [String: [Recipe]] = [:]
    var recipeSearchResults: [SearchRecipeGroup] = []
    var peopleSearchResults: [User] = []
    var friends: [User] = [] // Used for friend-saver social proof in recipe search ranking
    var isLoading = false
    var isLoadingPeople = false
    var connections: [Connection] = [] // Derived from connectionManager
    var connectionError: ConnectionError?
    var popularTags: [String] = []
    var selectedCategories: Set<RecipeCategory> = []
    var ownerTiers: [UUID: UserTier] = [:] // Cached owner tiers for search boost
    var timeFilter: RecipeTimeFilter = .any
    var sortOrder: RecipeSortOrder = .relevance

    /// Search results after applying the time filter and chosen sort order.
    /// Category/text filtering already happens upstream in the grouping service.
    var displayedRecipeResults: [SearchRecipeGroup] {
        let filtered = timeFilter == .any
            ? recipeSearchResults
            : recipeSearchResults.filter { timeFilter.matches(minutes: $0.primaryRecipe.totalMinutes) }

        switch sortOrder {
        case .relevance:
            return filtered
        case .quickest:
            return filtered.sorted {
                ($0.primaryRecipe.totalMinutes ?? .max) < ($1.primaryRecipe.totalMinutes ?? .max)
            }
        case .alphabetical:
            return filtered.sorted {
                $0.primaryRecipe.title.localizedCaseInsensitiveCompare($1.primaryRecipe.title) == .orderedAscending
            }
        case .newest:
            return filtered.sorted { $0.primaryRecipe.createdAt > $1.primaryRecipe.createdAt }
        }
    }

    /// Whether any non-default filter/sort is active (for showing a clear control).
    var hasActiveRefinements: Bool {
        timeFilter != .any || sortOrder != .relevance
    }

    func clearRefinements() {
        timeFilter = .any
        sortOrder = .relevance
    }

    let dependencies: DependencyContainer
    private var recipeSearchText: String = ""
    private var peopleSearchText: String = ""
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var recipeSearchTask: Task<Void, Never>?
    @ObservationIgnored private var peopleSearchTask: Task<Void, Never>?
    @ObservationIgnored private var recipeSearchResultsTask: Task<Void, Never>?
    @ObservationIgnored private var recipeLibraryRefreshTask: Task<Void, Never>?
    @ObservationIgnored private let connectionCoordinator: ConnectionInteractionCoordinator
    @ObservationIgnored private var hasLoadedOnce = false
    @ObservationIgnored private var recipeSearchGeneration = 0

    // Public discovery caching
    private var publicRecipeSearchCache: [String: [Recipe]] = [:]
    private var publicRecipeSearchFetchedAt: [String: Date] = [:]
    private let publicRecipeSearchCacheValidityDuration: TimeInterval = 300 // 5 minutes
    private let minimumPublicRecipeSearchQueryLength = 2

    // Debouncing
    private let peopleSearchSubject = PassthroughSubject<String, Never>()
    private let recipeSearchSubject = PassthroughSubject<(String, Set<RecipeCategory>, Int), Never>()

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        self.connectionCoordinator = ConnectionInteractionCoordinator(
            connectionManager: dependencies.connectionManager,
            currentUserProvider: { dependencies.connectionManager.currentUserId }
        )

        // Set up debounced people search
        peopleSearchSubject
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                self.peopleSearchTask?.cancel()
                self.peopleSearchTask = Task {
                    await self.performPeopleSearch(query)
                }
            }
            .store(in: &cancellables)

        // Set up debounced recipe search
        recipeSearchSubject
            .debounce(for: .milliseconds(280), scheduler: DispatchQueue.main)
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .sink { [weak self] (query, categories, generation) in
                guard let self = self else { return }
                // Drop stale emissions that no longer match the latest UI state.
                guard self.isCurrentRecipeSearch(
                    generation: generation,
                    query: query,
                    selectedCategories: categories
                ) else {
                    return
                }
                self.recipeSearchTask?.cancel()
                self.recipeSearchTask = Task {
                    await self.performRecipeSearch(
                        query: query,
                        categories: Array(categories),
                        generation: generation
                    )
                }
            }
            .store(in: &cancellables)
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {
        // Note: Cannot access cancellables or task references here as they're isolated
        // Cleanup happens automatically when the object is deallocated
    }
    
    func loadData(forceRefreshPublicRecipes: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load user's own recipes
            allRecipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await dependencies.recipeRepository.fetchLibraryRecipes(ownerId: CurrentUserSession.shared.userId),
                currentUserId: CurrentUserSession.shared.userId,
                hidingRelatedRecipeReferences: true
            )

            // Group recipes by tags (using own recipes for category browsing)
            groupRecipesByTags()

            // Load connections (for determining connection status in user search)
            await loadConnections()
            
            // Load recommendations (Friends of Friends)
            await loadRecommendations()

            // Load initial public recipes (empty search = recent)
            await performRecipeSearch(
                query: recipeSearchText,
                categories: Array(selectedCategories),
                forceRefreshPublicRecipes: forceRefreshPublicRecipes,
                generation: recipeSearchGeneration
            )

            hasLoadedOnce = true

        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
        }
    }

    func loadDataIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await loadData()
    }

    // loadPublicRecipes removed in favor of server-side search

    func loadConnections() async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)

        // Update local connections array from manager
        connections = dependencies.connectionManager.connections.values.map { $0.connection }

        // Load friends details (used for friend-saver social proof in search ranking)
        await loadFriends()
    }

    func loadFriends() async {
        let friendIds = connections
            .filter { $0.isAccepted }
            .compactMap { $0.otherUserId(currentUserId: currentUserId) }

        guard !friendIds.isEmpty else {
            friends = []
            return
        }

        do {
            friends = try await dependencies.sharingService.getUsers(byIds: friendIds)
        } catch {
            AppLogger.general.error("Failed to load friends: \(error.localizedDescription)")
        }
    }

    var recommendedUsers: [User] = []
    
    func loadRecommendations() async {
        // 1. Get current friends' IDs
        let friendIds = connections
            .filter { $0.isAccepted }
            .compactMap { $0.otherUserId(currentUserId: currentUserId) }
            
        guard !friendIds.isEmpty else {
            recommendedUsers = []
            return
        }
        
        do {
            // 2. Fetch connections of friends (Friends of Friends)
            let fofConnections = try await dependencies.connectionCloudService.fetchConnections(forUserIds: friendIds)
            
            // 3. Extract unique User IDs, excluding self and existing friends
            var recommendedIds = Set<UUID>()
            for connection in fofConnections {
                // Determine the "other" person in the FOF connection
                // (e.g. Friend A is connected to Stranger B)
                let potentialId: UUID
                if friendIds.contains(connection.fromUserId) {
                    potentialId = connection.toUserId
                } else {
                    potentialId = connection.fromUserId
                }
                
                // Filter out self and direct friends
                if potentialId != currentUserId && !friendIds.contains(potentialId) {
                    recommendedIds.insert(potentialId)
                }
            }
            
            // 4. Fetch User profiles for recommendations
            if !recommendedIds.isEmpty {
                let users = try await dependencies.sharingService.getUsers(byIds: Array(recommendedIds))
                recommendedUsers = users
            } else {
                recommendedUsers = []
            }
        } catch {
            AppLogger.general.error("Failed to load recommendations: \(error.localizedDescription)")
        }
    }

    // MARK: - Connection Actions

    func relationshipState(for user: User) -> ConnectionRelationshipState {
        connectionCoordinator.relationshipState(with: user.id)
    }

    /// Accept a connection request
    func acceptConnectionRequest(from user: User) async {
        do {
            try await connectionCoordinator.acceptRequest(from: user.id)
            AppLogger.general.info("✅ Connection accepted successfully")
        } catch {
            AppLogger.general.error("❌ Failed to accept connection: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }

    /// Reject a connection request
    func rejectConnectionRequest(from user: User) async {
        do {
            try await connectionCoordinator.rejectRequest(from: user.id)
            AppLogger.general.info("✅ Connection rejected successfully")
        } catch {
            AppLogger.general.error("❌ Failed to reject connection: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }

    /// Send a connection request
    func sendConnectionRequest(to user: User) async {
        do {
            try await connectionCoordinator.sendRequest(to: user)
            AppLogger.general.info("✅ Connection request sent successfully")
        } catch {
            AppLogger.general.error("❌ Failed to send connection request: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }

    func retryConnectionOperation(for user: User) async {
        await connectionCoordinator.retryFailedOperation(with: user.id)
    }
    
    func updateRecipeSearch(_ query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        recipeSearchText = normalizedQuery
        let generation = advanceRecipeSearchGeneration()
        // Update local results immediately
        filterLocalRecipes(generation: generation)

        // Avoid debounce delay when query is empty so default discovery results appear instantly.
        if normalizedQuery.isEmpty {
            recipeSearchTask?.cancel()
            recipeSearchTask = Task {
                await performRecipeSearch(
                    query: "",
                    categories: Array(selectedCategories),
                    generation: generation
                )
            }
            return
        }

        guard normalizedQuery.count >= minimumPublicRecipeSearchQueryLength else {
            recipeSearchTask?.cancel()
            isLoading = false
            publicRecipes = []
            scheduleRecipeSearchResultsRebuild(
                filterText: normalizedQuery,
                selectedCategories: selectedCategories,
                generation: generation
            )
            return
        }

        // Trigger debounced server search for active query.
        recipeSearchSubject.send((normalizedQuery, selectedCategories, generation))
    }
    
    func toggleCategory(_ category: RecipeCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        let generation = advanceRecipeSearchGeneration()
        // Update local results immediately
        filterLocalRecipes(generation: generation)

        // Category toggles should feel snappy; run immediately.
        recipeSearchTask?.cancel()
        recipeSearchTask = Task {
            await performRecipeSearch(
                query: recipeSearchText,
                categories: Array(selectedCategories),
                generation: generation
            )
        }
    }
    
    private func filterLocalRecipes(generation: Int) {
        scheduleRecipeSearchResultsRebuild(
            filterText: recipeSearchText,
            selectedCategories: selectedCategories,
            generation: generation
        )
    }
    
    private func performRecipeSearch(
        query: String,
        categories: [RecipeCategory],
        forceRefreshPublicRecipes: Bool = false,
        generation: Int
    ) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedCategories = Set(categories)

        guard normalizedQuery.isEmpty || normalizedQuery.count >= minimumPublicRecipeSearchQueryLength else {
            publicRecipes = []
            scheduleRecipeSearchResultsRebuild(
                filterText: normalizedQuery,
                selectedCategories: selectedCategories,
                generation: generation
            )
            return
        }

        guard isCurrentRecipeSearch(
            generation: generation,
            query: normalizedQuery,
            selectedCategories: selectedCategories
        ) else {
            return
        }

        isLoading = true

        do {
            let results = try await loadPublicRecipeSearchResults(
                query: normalizedQuery,
                categories: categories,
                forceRefresh: forceRefreshPublicRecipes
            )

            // Filter out own recipes (just in case)
            let filteredResults = results.filter { $0.ownerId != currentUserId }

            if !Task.isCancelled,
               isCurrentRecipeSearch(generation: generation, query: normalizedQuery, selectedCategories: selectedCategories) {
                publicRecipes = filteredResults

                // Fetch owner tiers for search ranking boost
                await fetchOwnerTiers(for: filteredResults)

                guard !Task.isCancelled,
                      isCurrentRecipeSearch(generation: generation, query: normalizedQuery, selectedCategories: selectedCategories) else {
                    return
                }

                // Re-merge with local results and process grouping
                scheduleRecipeSearchResultsRebuild(
                    filterText: normalizedQuery,
                    selectedCategories: selectedCategories,
                    generation: generation
                )
                isLoading = false
            }
        } catch {
            if !Task.isCancelled,
               isCurrentRecipeSearch(generation: generation, query: normalizedQuery, selectedCategories: selectedCategories) {
                AppLogger.general.error("Failed to search public recipes: \(error.localizedDescription)")
                publicRecipes = []
                scheduleRecipeSearchResultsRebuild(
                    filterText: normalizedQuery,
                    selectedCategories: selectedCategories,
                    generation: generation
                )
                isLoading = false
            }
        }
    }

    func scheduleRecipeLibraryRefresh() {
        recipeLibraryRefreshTask?.cancel()
        recipeLibraryRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshRecipeLibrary()
            } catch {
                return
            }
        }
    }

    private func refreshRecipeLibrary() async {
        do {
            allRecipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await dependencies.recipeRepository.fetchLibraryRecipes(ownerId: CurrentUserSession.shared.userId),
                currentUserId: CurrentUserSession.shared.userId,
                hidingRelatedRecipeReferences: true
            )
            groupRecipesByTags()
            scheduleRecipeSearchResultsRebuild(
                filterText: recipeSearchText,
                selectedCategories: selectedCategories,
                generation: recipeSearchGeneration
            )
        } catch {
            AppLogger.general.error("Failed to refresh local search recipes: \(error.localizedDescription)")
        }
    }

    private func advanceRecipeSearchGeneration() -> Int {
        recipeSearchGeneration += 1
        return recipeSearchGeneration
    }

    private func isCurrentRecipeSearch(
        generation: Int,
        query: String,
        selectedCategories: Set<RecipeCategory>
    ) -> Bool {
        generation == recipeSearchGeneration &&
        query == recipeSearchText &&
        selectedCategories == self.selectedCategories
    }
    
    private func loadPublicRecipeSearchResults(
        query: String,
        categories: [RecipeCategory],
        forceRefresh: Bool = false
    ) async throws -> [Recipe] {
        let cacheKey = publicRecipeSearchCacheKey(query: query, categories: categories)

        if !forceRefresh,
           let fetchedAt = publicRecipeSearchFetchedAt[cacheKey],
           Date().timeIntervalSince(fetchedAt) < publicRecipeSearchCacheValidityDuration,
           let cachedResults = publicRecipeSearchCache[cacheKey] {
            return cachedResults
        }

        let results = try await dependencies.recipeDiscoveryCache.searchDiscoverablePublicRecipes(
            query: query,
            categories: categories,
            forceRefresh: forceRefresh
        )
        publicRecipeSearchCache[cacheKey] = results
        publicRecipeSearchFetchedAt[cacheKey] = Date()
        return results
    }

    private func publicRecipeSearchCacheKey(query: String, categories: [RecipeCategory]) -> String {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let categoryKey = categories
            .map(\.tagValue)
            .map { $0.lowercased() }
            .sorted()
            .joined(separator: "|")
        return "\(normalizedQuery)::\(categoryKey)"
    }

    // Process results: Filter local options, merge with public, group copies, rank, and extract friend context.
    private func scheduleRecipeSearchResultsRebuild(
        filterText: String,
        selectedCategories: Set<RecipeCategory>,
        generation: Int
    ) {
        let localRecipesSnapshot = allRecipes
        let publicRecipesSnapshot = publicRecipes
        let friendsSnapshot = friends
        let currentUserIdSnapshot = currentUserId
        let ownerTiersSnapshot = ownerTiers

        recipeSearchResultsTask?.cancel()
        recipeSearchResultsTask = Task(priority: .userInitiated) {
            let groupingTask = Task.detached(priority: .userInitiated) {
                RecipeGroupingService.groupAndRankRecipes(
                    localRecipes: localRecipesSnapshot,
                    publicRecipes: publicRecipesSnapshot,
                    friends: friendsSnapshot,
                    currentUserId: currentUserIdSnapshot,
                    ownerTiers: ownerTiersSnapshot,
                    filterText: filterText,
                    selectedCategories: selectedCategories
                )
            }
            let groups = await withTaskCancellationHandler {
                await groupingTask.value
            } onCancel: {
                groupingTask.cancel()
            }

            guard !Task.isCancelled,
                  self.isCurrentRecipeSearch(
                    generation: generation,
                    query: filterText,
                    selectedCategories: selectedCategories
                  ) else {
                return
            }
            self.recipeSearchResults = groups
        }
    }

    /// Fetch owner tiers for recipes based on their public recipe counts
    /// This enables the tier-based search boost ranking
    private func fetchOwnerTiers(for recipes: [Recipe]) async {
        // Collect unique owner IDs that we don't already have cached
        let ownerIds = Set(recipes.compactMap { $0.ownerId })
            .filter { $0 != currentUserId && ownerTiers[$0] == nil }

        guard !ownerIds.isEmpty else { return }

        do {
            // Batch fetch recipe counts for all owners at once (avoids N+1 queries)
            let counts = try await dependencies.recipeDiscoveryCache.batchFetchPublicRecipeCounts(
                forOwnerIds: Array(ownerIds)
            )

            // Convert counts to tiers
            for (ownerId, count) in counts {
                ownerTiers[ownerId] = UserTier.tier(for: count)
            }
        } catch {
            AppLogger.general.error("Failed to fetch owner tiers: \(error.localizedDescription)")
            // Continue with default tiers (apprentice)
        }
    }
    
    func updatePeopleSearch(_ query: String) {
        peopleSearchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if peopleSearchText.isEmpty {
            peopleSearchTask?.cancel()
            peopleSearchResults = []
        } else {
            // Send to debounced subject instead of fetching immediately
            peopleSearchSubject.send(peopleSearchText)
        }
    }

    /// Perform the actual people search (called after debounce)
    private func performPeopleSearch(_ query: String) async {
        // Don't search if query is empty
        guard !query.isEmpty else {
            peopleSearchResults = []
            return
        }
        
        isLoadingPeople = true

        do {
            // Use server-side search instead of fetching all users
            let results = try await dependencies.sharingService.searchUsers(query)
            
            // Only update if not cancelled
            if !Task.isCancelled {
                peopleSearchResults = results
                isLoadingPeople = false
            }
        } catch {
            if !Task.isCancelled {
                AppLogger.general.error("Failed to search users: \(error.localizedDescription)")
                peopleSearchResults = []
                isLoadingPeople = false
            }
        }
    }
    
    private func groupRecipesByTags() {
        var grouped: [String: [Recipe]] = [:]
        var tagCounts: [String: Int] = [:]
        var seenRecipeIdsByTag: [String: Set<UUID>] = [:]
        
        for recipe in allRecipes {
            for tag in recipe.tags {
                // Normalize tag name for grouping (Title Case)
                let normalizedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines).capitalized

                if seenRecipeIdsByTag[normalizedName, default: []].insert(recipe.id).inserted {
                    grouped[normalizedName, default: []].append(recipe)
                    tagCounts[normalizedName, default: 0] += 1
                }
            }
        }
        
        // Store all recipes per tag
        recipesByTag = grouped
        
        // Calculate popular tags (Common tags + most used user tags)
        let userTopTags = tagCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
        
        // Combine common tags with user's top tags, removing duplicates
        var tags = Tag.commonTags
        for tag in userTopTags {
            if !tags.contains(tag) {
                tags.append(tag)
            }
        }
        
        popularTags = tags
    }
}
