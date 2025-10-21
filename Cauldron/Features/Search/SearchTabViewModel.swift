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
    @Published var allRecipes: [Recipe] = []
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
    }
    
    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load all recipes
            allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Group recipes by tags
            groupRecipesByTags()

            // Load connections (for determining connection status in user search)
            await loadConnections()

            // Load users for people search
            await loadUsers()

        } catch {
            AppLogger.general.error("Failed to load search tab data: \(error.localizedDescription)")
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
            let allUsers = try await dependencies.sharingService.getAllUsers()

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
    
    func updateRecipeSearch(_ query: String) {
        recipeSearchText = query
        
        if query.isEmpty {
            recipeSearchResults = []
        } else {
            let lowercased = query.lowercased()
            recipeSearchResults = allRecipes.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
                recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
    }
    
    func updatePeopleSearch(_ query: String) {
        peopleSearchText = query

        Task {
            isLoadingPeople = true
            defer { isLoadingPeople = false }

            do {
                let allUsers = try await dependencies.sharingService.getAllUsers()

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
