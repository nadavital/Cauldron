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
class SearchTabViewModel: ObservableObject {
    @Published var allRecipes: [Recipe] = [] // User's own recipes
    @Published var publicRecipes: [Recipe] = [] // All public recipes from CloudKit
    @Published var recipesByTag: [String: [Recipe]] = [:]
    @Published var recipeSearchResults: [Recipe] = []
    @Published var peopleSearchResults: [User] = []
    @Published var friends: [User] = []
    @Published var isLoading = false
    @Published var isLoadingPeople = false
    @Published var connections: [Connection] = [] // Derived from connectionManager
    @Published var connectionError: ConnectionError?
    @Published var popularTags: [String] = []
    @Published var selectedCategories: Set<RecipeCategory> = []

    let dependencies: DependencyContainer
    private var recipeSearchText: String = ""
    private var peopleSearchText: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    // Caching
    private var cachedPublicRecipes: [Recipe] = []
    private var publicRecipesCacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Debouncing
    private let peopleSearchSubject = PassthroughSubject<String, Never>()
    private let recipeSearchSubject = PassthroughSubject<(String, Set<RecipeCategory>), Never>()

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Subscribe to connection manager updates
        dependencies.connectionManager.$connections
            .receive(on: DispatchQueue.main)
            .sink { [weak self] managedConnections in
                guard let self = self else { return }
                // Convert ManagedConnection to Connection for backward compatibility
                self.connections = managedConnections.values.map { $0.connection }
                
                // Load friends details when connections change
                Task {
                    await self.loadFriends()
                }
            }
            .store(in: &cancellables)

        // Set up debounced people search
        peopleSearchSubject
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                self.searchTask?.cancel()
                self.searchTask = Task {
                    await self.performPeopleSearch(query)
                }
            }
            .store(in: &cancellables)
            
        // Set up debounced recipe search
        recipeSearchSubject
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates { $0 == $1 }
            .sink { [weak self] (query, categories) in
                guard let self = self else { return }
                self.searchTask?.cancel()
                self.searchTask = Task {
                    await self.performRecipeSearch(query: query, categories: Array(categories))
                }
            }
            .store(in: &cancellables)
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

        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
        }
    }

    // loadPublicRecipes removed in favor of server-side search

    func loadConnections() async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)
        AppLogger.general.info("Loaded connections via ConnectionManager")
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
        recipeSearchText = query
        // Update local results immediately
        filterLocalRecipes()
        // Trigger server search
        recipeSearchSubject.send((query, selectedCategories))
    }
    
    func toggleCategory(_ category: RecipeCategory) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        // Update local results immediately
        filterLocalRecipes()
        // Trigger server search
        recipeSearchSubject.send((recipeSearchText, selectedCategories))
    }
    
    private func filterLocalRecipes() {
        // Filter ONLY local recipes
        var results = allRecipes
        
        // 1. Filter by Search Text
        if !recipeSearchText.isEmpty {
            let lowercased = recipeSearchText.lowercased()
            results = results.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
                recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
        
        // 2. Filter by Selected Categories
        if !selectedCategories.isEmpty {
            results = results.filter { recipe in
                selectedCategories.allSatisfy { category in
                    recipe.tags.contains(where: { $0.name.caseInsensitiveCompare(category.tagValue) == .orderedSame })
                }
            }
        }
        
        // Combine with current public results
        // Note: publicRecipes are already filtered by the server
        recipeSearchResults = results + publicRecipes
    }
    
    private func performRecipeSearch(query: String, categories: [RecipeCategory]) async {
        isLoading = true
        
        do {
            // Convert categories to string tags
            let categoryTags = categories.map { $0.tagValue }
            
            // Perform server-side search
            let results = try await dependencies.cloudKitService.searchPublicRecipes(
                query: query,
                categories: categoryTags.isEmpty ? nil : categoryTags
            )
            
            // Filter out own recipes (just in case)
            let filteredResults = results.filter { $0.ownerId != currentUserId }
            
            if !Task.isCancelled {
                publicRecipes = filteredResults
                // Re-merge with local results
                filterLocalRecipes()
                isLoading = false
            }
        } catch {
            if !Task.isCancelled {
                AppLogger.general.error("Failed to search public recipes: \(error.localizedDescription)")
                publicRecipes = [] // Clear on error? Or keep previous? Let's clear to show error state if we had one.
                filterLocalRecipes()
                isLoading = false
            }
        }
    }
    
    func updatePeopleSearch(_ query: String) {
        peopleSearchText = query
        if query.isEmpty {
            peopleSearchResults = []
        } else {
            // Send to debounced subject instead of fetching immediately
            peopleSearchSubject.send(query)
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
