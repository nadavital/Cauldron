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
    @Published var isLoading = false
    @Published var isLoadingPeople = false
    @Published var connections: [Connection] = [] // Derived from connectionManager
    @Published var connectionError: ConnectionError?

    let dependencies: DependencyContainer
    private var recipeSearchText: String = ""
    private var peopleSearchText: String = ""
    private var cancellables = Set<AnyCancellable>()

    // Caching
    private var cachedUsers: [User] = []
    private var usersCacheTimestamp: Date?
    private var cachedPublicRecipes: [Recipe] = []
    private var publicRecipesCacheTimestamp: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes

    // Debouncing
    private let peopleSearchSubject = PassthroughSubject<String, Never>()

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies

        // Subscribe to connection manager updates
        dependencies.connectionManager.$connections
            .map { managedConnections in
                // Convert ManagedConnection to Connection for backward compatibility
                managedConnections.values.map { $0.connection }
            }
            .assign(to: &$connections)

        // Set up debounced people search
        peopleSearchSubject
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                Task {
                    await self.performPeopleSearch(query)
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

            // Load all public recipes from CloudKit
            await loadPublicRecipes()

            // Group recipes by tags (using own recipes for category browsing)
            groupRecipesByTags()

            // Load connections (for determining connection status in user search)
            await loadConnections()

            // Load users for people search
            await loadUsers()

        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
        }
    }

    func loadPublicRecipes() async {
        // Check if cache is valid
        if let timestamp = publicRecipesCacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration,
           !cachedPublicRecipes.isEmpty {
            AppLogger.general.info("Using cached public recipes (\(self.cachedPublicRecipes.count) recipes)")
            publicRecipes = cachedPublicRecipes
            return
        }

        do {
            // Fetch all public recipes from CloudKit
            AppLogger.general.info("Fetching fresh public recipes from CloudKit")
            let recipes = try await dependencies.cloudKitService.querySharedRecipes(
                ownerIds: nil,
                visibility: .publicRecipe
            )

            // Filter out own recipes
            let filteredRecipes = recipes.filter { $0.ownerId != currentUserId }
            publicRecipes = filteredRecipes

            // Update cache
            cachedPublicRecipes = filteredRecipes
            publicRecipesCacheTimestamp = Date()

            AppLogger.general.info("Loaded \(self.publicRecipes.count) public recipes for search")
        } catch {
            AppLogger.general.error("Failed to load public recipes: \(error.localizedDescription)")
            publicRecipes = []
        }
    }

    func loadConnections() async {
        // Use ConnectionManager - it handles caching and sync automatically
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)
        AppLogger.general.info("Loaded connections via ConnectionManager")
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
    
    func loadUsers() async {
        isLoadingPeople = true
        defer { isLoadingPeople = false }

        do {
            let allUsers = try await fetchUsersWithCache()

            // Preserve search filtering after reload
            if peopleSearchText.isEmpty {
                peopleSearchResults = allUsers
            } else {
                let lowercased = peopleSearchText.lowercased()
                peopleSearchResults = allUsers.filter { user in
                    user.username.lowercased().contains(lowercased) ||
                    user.displayName.lowercased().contains(lowercased)
                }
            }
        } catch {
            AppLogger.general.error("Failed to load users: \(error.localizedDescription)")
            peopleSearchResults = []
        }
    }

    /// Fetch users with caching to avoid unnecessary CloudKit queries
    private func fetchUsersWithCache() async throws -> [User] {
        // Check if cache is valid
        if let timestamp = usersCacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValidityDuration,
           !cachedUsers.isEmpty {
            AppLogger.general.info("Using cached users (\(self.cachedUsers.count) users)")
            return cachedUsers
        }

        // Cache expired or empty, fetch fresh data
        AppLogger.general.info("Fetching fresh user data from CloudKit")
        let users = try await dependencies.sharingService.getAllUsers()

        // Update cache
        cachedUsers = users
        usersCacheTimestamp = Date()

        return users
    }
    
    func updateRecipeSearch(_ query: String) {
        recipeSearchText = query

        if query.isEmpty {
            recipeSearchResults = []
        } else {
            let lowercased = query.lowercased()

            // Search both personal recipes AND public recipes
            let combinedRecipes = allRecipes + publicRecipes

            recipeSearchResults = combinedRecipes.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
                recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
    }
    
    func updatePeopleSearch(_ query: String) {
        peopleSearchText = query
        // Send to debounced subject instead of fetching immediately
        peopleSearchSubject.send(query)
    }

    /// Perform the actual people search with caching (called after debounce)
    private func performPeopleSearch(_ query: String) async {
        isLoadingPeople = true
        defer { isLoadingPeople = false }

        do {
            let allUsers = try await fetchUsersWithCache()

            if query.isEmpty {
                peopleSearchResults = allUsers
            } else {
                // Filter locally for better UX (allows substring matching)
                let lowercased = query.lowercased()
                peopleSearchResults = allUsers.filter { user in
                    user.username.lowercased().contains(lowercased) ||
                    user.displayName.lowercased().contains(lowercased)
                }
            }
        } catch {
            AppLogger.general.error("Failed to search users: \(error.localizedDescription)")
            peopleSearchResults = []
        }
    }
    
    private func groupRecipesByTags() {
        var grouped: [String: [Recipe]] = [:]
        
        for recipe in allRecipes {
            for tag in recipe.tags {
                if grouped[tag.name] == nil {
                    grouped[tag.name] = []
                }
                // Only add if not already in this tag's list
                if !(grouped[tag.name]?.contains(where: { $0.id == recipe.id }) ?? false) {
                    grouped[tag.name]?.append(recipe)
                }
            }
        }
        
        // Store all recipes per tag
        recipesByTag = grouped
    }
}
