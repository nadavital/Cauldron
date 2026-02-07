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



@MainActor
@Observable final class SearchTabViewModel {
    var allRecipes: [Recipe] = [] // User's own recipes
    var publicRecipes: [Recipe] = [] // All public recipes from CloudKit
    var recipesByTag: [String: [Recipe]] = [:]
    var recipeSearchResults: [SearchRecipeGroup] = []
    var peopleSearchResults: [User] = []
    var friends: [User] = []
    var isLoading = false
    var isLoadingPeople = false
    var connections: [Connection] = [] // Derived from connectionManager
    var connectionError: ConnectionError?
    var popularTags: [String] = []
    var selectedCategories: Set<RecipeCategory> = []
    var ownerTiers: [UUID: UserTier] = [:] // Cached owner tiers for search boost

    let dependencies: DependencyContainer
    private var recipeSearchText: String = ""
    private var peopleSearchText: String = ""
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var recipeSearchTask: Task<Void, Never>?
    @ObservationIgnored private var peopleSearchTask: Task<Void, Never>?

    // Search results caching
    private var cachedSearchResults: [String: [Recipe]] = [:] // Key: query+categories hash
    private var searchResultsTimestamps: [String: Date] = [:]
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Debouncing
    private let peopleSearchSubject = PassthroughSubject<String, Never>()
    private let recipeSearchSubject = PassthroughSubject<(String, Set<RecipeCategory>), Never>()

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

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
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] (query, categories) in
                guard let self = self else { return }
                self.recipeSearchTask?.cancel()
                self.recipeSearchTask = Task {
                    await self.performRecipeSearch(query: query, categories: Array(categories))
                }
            }
            .store(in: &cancellables)
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {
        // Note: Cannot access cancellables or task references here as they're isolated
        // Cleanup happens automatically when the object is deallocated
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load user's own recipes
            allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Load initial public recipes (empty search = recent)
            await performRecipeSearch(query: "", categories: [])

            // Group recipes by tags (using own recipes for category browsing)
            groupRecipesByTags()

            // Load connections (for determining connection status in user search)
            await loadConnections()
            
            // Load recommendations (Friends of Friends)
            await loadRecommendations()

        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
        }
    }

    // loadPublicRecipes removed in favor of server-side search

    func loadConnections() async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)

        // Update local connections array from manager
        connections = dependencies.connectionManager.connections.values.map { $0.connection }

        // Load friends details
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

    /// Accept a connection request
    func acceptConnection(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.acceptConnection(connection)
            AppLogger.general.info("✅ Connection accepted successfully")
        } catch {
            AppLogger.general.error("❌ Failed to accept connection: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }

    /// Reject a connection request
    func rejectConnection(_ connection: Connection) async {
        do {
            try await dependencies.connectionManager.rejectConnection(connection)
            AppLogger.general.info("✅ Connection rejected successfully")
        } catch {
            AppLogger.general.error("❌ Failed to reject connection: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }

    /// Send a connection request
    func sendConnectionRequest(to user: User) async {
        do {
            try await dependencies.connectionManager.sendConnectionRequest(to: user.id, user: user)
            AppLogger.general.info("✅ Connection request sent successfully")
        } catch {
            AppLogger.general.error("❌ Failed to send connection request: \(error.localizedDescription)")
            connectionError = error as? ConnectionError ?? .networkFailure(error)
        }
    }
    
    func updateRecipeSearch(_ query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        recipeSearchText = normalizedQuery
        // Update local results immediately
        filterLocalRecipes()

        // Avoid debounce delay when query is empty so default discovery results appear instantly.
        if normalizedQuery.isEmpty {
            recipeSearchTask?.cancel()
            recipeSearchTask = Task {
                await performRecipeSearch(query: "", categories: Array(selectedCategories))
            }
            return
        }

        // Trigger debounced server search for active query.
        recipeSearchSubject.send((normalizedQuery, selectedCategories))
    }
    
    func toggleCategory(_ category: RecipeCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        // Update local results immediately
        filterLocalRecipes()

        // Category toggles should feel snappy; run immediately.
        recipeSearchTask?.cancel()
        recipeSearchTask = Task {
            await performRecipeSearch(query: recipeSearchText, categories: Array(selectedCategories))
        }
    }
    
    private func filterLocalRecipes() {
        processSearchResults()
    }
    
    private func performRecipeSearch(query: String, categories: [RecipeCategory]) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Generate cache key from query and categories
        let categoryTags = categories.map { $0.tagValue }.sorted()
        let cacheKey = "\(normalizedQuery.lowercased())|\(categoryTags.joined(separator: ","))"

        // Check if we have valid cached results
        if let cachedResults = cachedSearchResults[cacheKey],
           let timestamp = searchResultsTimestamps[cacheKey],
           Date().timeIntervalSince(timestamp) < cacheValidityDuration {
            // Use cached results
            let filteredResults = cachedResults.filter { $0.ownerId != currentUserId }
            if !Task.isCancelled {
                publicRecipes = filteredResults
                await fetchOwnerTiers(for: filteredResults)
                processSearchResults()
            }
            return
        }

        isLoading = true

        do {
            // Perform server-side search
            let results = try await dependencies.searchCloudService.searchPublicRecipes(
                query: normalizedQuery,
                categories: categoryTags.isEmpty ? nil : categoryTags
            )

            // Cache the results
            cachedSearchResults[cacheKey] = results
            searchResultsTimestamps[cacheKey] = Date()

            // Filter out own recipes (just in case)
            let filteredResults = results.filter { $0.ownerId != currentUserId }

            if !Task.isCancelled {
                publicRecipes = filteredResults

                // Fetch owner tiers for search ranking boost
                await fetchOwnerTiers(for: filteredResults)

                // Re-merge with local results and process grouping
                processSearchResults()
                isLoading = false
            }
        } catch {
            if !Task.isCancelled {
                AppLogger.general.error("Failed to search public recipes: \(error.localizedDescription)")
                publicRecipes = []
                processSearchResults()
                isLoading = false
            }
        }
    }
    
    // Process results: Filter local options, merge with public, group copies, rank, and extract friend context
    private func processSearchResults() {
        // Use the centralized grouping service to filter, merge, group, and rank recipes
        self.recipeSearchResults = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: allRecipes,
            publicRecipes: publicRecipes,
            friends: friends,
            currentUserId: currentUserId,
            ownerTiers: ownerTiers,
            filterText: recipeSearchText,
            selectedCategories: selectedCategories
        )
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
            let counts = try await dependencies.recipeCloudService.batchFetchPublicRecipeCounts(
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
        
        for recipe in allRecipes {
            for tag in recipe.tags {
                // Normalize tag name for grouping (Title Case)
                let normalizedName = tag.name.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
                
                if grouped[normalizedName] == nil {
                    grouped[normalizedName] = []
                }
                // Only add if not already in this tag's list
                if !(grouped[normalizedName]?.contains(where: { $0.id == recipe.id }) ?? false) {
                    grouped[normalizedName]?.append(recipe)
                }
                
                tagCounts[normalizedName, default: 0] += 1
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
