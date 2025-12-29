//
//  UserProfileViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

/// View model for user profile view - handles connection management and user info
@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var connectionState: ConnectionState = .loading
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isProcessing = false
    @Published var userRecipes: [SharedRecipe] = []
    @Published var isLoadingRecipes = false
    @Published var userCollections: [Collection] = []
    @Published var isLoadingCollections = false
    @Published var connections: [ManagedConnection] = []
    @Published var isLoadingConnections = false
    @Published var usersMap: [UUID: User] = [:]
    @Published var searchText = ""

    let user: User
    let dependencies: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    enum ConnectionState: Equatable {
        case notConnected
        case pendingSent
        case pendingReceived
        case connected
        case loading
    }

    var currentUserId: UUID {
        CurrentUserSession.shared.userId ?? UUID()
    }

    var isCurrentUser: Bool {
        user.id == currentUserId
    }

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        self.dependencies = dependencies

        // Subscribe to connection manager updates for real-time state changes
        dependencies.connectionManager.$connections
            .sink { [weak self] connections in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.updateConnectionState()
                    // Update connections list if viewing current user
                    if self.isCurrentUser {
                        self.connections = connections.values.filter { $0.connection.isAccepted }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func loadConnectionStatus() async {
        await updateConnectionState()
    }

    func loadConnections() async {
        // Only load connections for current user
        guard isCurrentUser else { return }

        isLoadingConnections = true
        defer { isLoadingConnections = false }

        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)
        connections = dependencies.connectionManager.connections.values.filter { $0.connection.isAccepted }

        // Load user details for all connections
        for managedConnection in connections {
            if let otherUserId = managedConnection.connection.otherUserId(currentUserId: currentUserId) {
                do {
                    let user = try await dependencies.cloudKitService.fetchUser(byUserId: otherUserId)
                    usersMap[otherUserId] = user
                } catch {
                    AppLogger.general.error("Failed to load user \(otherUserId): \(error.localizedDescription)")
                }
            }
        }
    }

    private func updateConnectionState() async {
        // Don't show connection state for current user
        if isCurrentUser {
            connectionState = .notConnected
            return
        }

        connectionState = .loading

        // Get connection status from ConnectionManager
        if let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) {
            let connection = managedConnection.connection

            if connection.isAccepted {
                connectionState = .connected
            } else if connection.fromUserId == currentUserId {
                connectionState = .pendingSent
            } else {
                connectionState = .pendingReceived
            }
        } else {
            connectionState = .notConnected
        }
    }

    func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.sendConnectionRequest(to: user.id, user: user)
            AppLogger.general.info("✅ Connection request sent to \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to send connection request: \(error.localizedDescription)")
            errorMessage = "Failed to send request: \(error.localizedDescription)"
            showError = true
        }
    }

    func acceptConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to accept")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.acceptConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection accepted from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to accept connection: \(error.localizedDescription)")
            errorMessage = "Failed to accept: \(error.localizedDescription)"
            showError = true
        }
    }

    func rejectConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to reject")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.rejectConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection rejected from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to reject connection: \(error.localizedDescription)")
            errorMessage = "Failed to reject: \(error.localizedDescription)"
            showError = true
        }
    }

    func removeConnection() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to remove")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.deleteConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection removed with \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to remove connection: \(error.localizedDescription)")
            errorMessage = "Failed to remove connection: \(error.localizedDescription)"
            showError = true
        }
    }

    func cancelConnectionRequest() async {
        guard let managedConnection = dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("No connection found to cancel")
            return
        }

        // Verify it's a pending request sent by current user
        guard managedConnection.connection.fromUserId == currentUserId &&
              managedConnection.connection.status == .pending else {
            AppLogger.general.error("Connection is not a pending sent request")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await dependencies.connectionManager.deleteConnection(managedConnection.connection)
            AppLogger.general.info("✅ Connection request canceled to \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to cancel connection request: \(error.localizedDescription)")
            errorMessage = "Failed to cancel request: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Recipe Fetching

    func loadUserRecipes(forceRefresh: Bool = false) async {
        // Check cache first (unless force refresh)
        if !forceRefresh,
           let cachedRecipes = dependencies.profileCacheManager.getCachedRecipes(
               for: user.id,
               connectionState: connectionState
           ) {
            userRecipes = cachedRecipes
            return
        }

        // Only show loading state when actually fetching
        isLoadingRecipes = true

        do {
            userRecipes = try await fetchUserRecipes()

            // Cache the results
            dependencies.profileCacheManager.cacheRecipes(
                userRecipes,
                for: user.id,
                connectionState: connectionState
            )

            AppLogger.general.info("✅ Loaded \(self.userRecipes.count) recipes for user \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to load user recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }

        isLoadingRecipes = false
    }

    private func fetchUserRecipes() async throws -> [SharedRecipe] {
        // Get current user to check connection status
        guard let currentUserId = CurrentUserSession.shared.userId else {
            return []
        }

        var recipes: [Recipe]

        // If viewing your own profile, fetch from local storage (same as Cook tab)
        if isCurrentUser {
            recipes = try await dependencies.recipeRepository.fetchAll()
            AppLogger.general.info("Found \(recipes.count) owned recipes from local storage")
        } else {
            // If viewing someone else's profile, fetch their public recipes from CloudKit
            recipes = try await dependencies.cloudKitService.querySharedRecipes(
                ownerIds: [user.id],
                visibility: .publicRecipe
            )
            AppLogger.general.info("Found \(recipes.count) public recipes from \(self.user.username)")
        }

        // Filter out recipes that are only referenced by other recipes (to avoid duplicates)
        // A recipe that appears in another recipe's relatedRecipeIds should not be shown separately
        let referencedIds = Set(recipes.flatMap { $0.relatedRecipeIds })
        let filteredRecipes = recipes.filter { !referencedIds.contains($0.id) }
        AppLogger.general.info("Filtered from \(recipes.count) to \(filteredRecipes.count) recipes (removed \(referencedIds.count) referenced recipes)")

        // Convert to SharedRecipe
        let sharedRecipes = filteredRecipes.map { recipe in
            SharedRecipe(
                id: recipe.id,
                recipe: recipe,
                sharedBy: user,
                sharedAt: recipe.updatedAt
            )
        }

        // Sort by updated date (most recent first)
        return sharedRecipes.sorted { $0.sharedAt > $1.sharedAt }
    }

    var filteredRecipes: [SharedRecipe] {
        guard !searchText.isEmpty else { return userRecipes }

        let lowercased = searchText.lowercased()
        return userRecipes.filter { sharedRecipe in
            sharedRecipe.recipe.title.lowercased().contains(lowercased) ||
            sharedRecipe.recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) }) ||
            sharedRecipe.recipe.ingredients.contains(where: { $0.name.lowercased().contains(lowercased) })
        }
    }

    // MARK: - Collection Fetching

    func loadUserCollections(forceRefresh: Bool = false) async {
        // Check cache first (unless force refresh)
        if !forceRefresh,
           let cachedCollections = dependencies.profileCacheManager.getCachedCollections(
               for: user.id,
               connectionState: connectionState
           ) {
            userCollections = cachedCollections
            return
        }

        isLoadingCollections = true

        do {
            userCollections = try await fetchUserCollections()

            // Cache the results
            dependencies.profileCacheManager.cacheCollections(
                userCollections,
                for: user.id,
                connectionState: connectionState
            )

            AppLogger.general.info("✅ Loaded \(self.userCollections.count) collections for user \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to load user collections: \(error.localizedDescription)")
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
            showError = true
        }

        isLoadingCollections = false
    }

    private func fetchUserCollections() async throws -> [Collection] {
        var allCollections: [Collection] = []

        // Only show public collections on profiles (simplified from private/friends/public to private/public)

        // If viewing own profile, load local collections (excluding private)
        if isCurrentUser {
            let localCollections = try await dependencies.collectionRepository.fetchAll()
            AppLogger.general.info("Found \(localCollections.count) total local collections")

            // Filter to only public (profile shows what others would see)
            let visibleCollections = localCollections.filter {
                $0.visibility == .publicRecipe
            }
            AppLogger.general.info("Filtered to \(visibleCollections.count) public collections")
            allCollections.append(contentsOf: visibleCollections)
        }

        // Fetch collections from CloudKit
        if CurrentUserSession.shared.isCloudSyncAvailable {
            do {
                // Fetch public collections
                let publicCollections = try await dependencies.cloudKitService.queryCollections(
                    ownerIds: [user.id],
                    visibility: .publicRecipe
                )
                AppLogger.general.info("Found \(publicCollections.count) public collections from CloudKit for \(self.user.username)")

                // Add CloudKit collections that aren't already in local storage
                for cloudCollection in publicCollections {
                    if !allCollections.contains(where: { $0.id == cloudCollection.id }) {
                        allCollections.append(cloudCollection)
                    }
                }
            } catch {
                AppLogger.general.warning("Failed to load collections from CloudKit: \(error.localizedDescription)")
                // If we're viewing our own profile and already have local collections, continue
                if !isCurrentUser {
                    throw error
                }
            }
        }

        // Sort by updated date (most recent first)
        return allCollections.sorted { $0.updatedAt > $1.updatedAt }
    }

    var displayedConnections: [ManagedConnection] {
        return Array(connections.prefix(6))
    }

    // MARK: - Refresh

    /// Refreshes all profile data (used for pull-to-refresh)
    func refreshProfile() async {
        await loadConnectionStatus()
        await loadUserRecipes(forceRefresh: true)
        await loadUserCollections(forceRefresh: true)
        if isCurrentUser {
            await loadConnections()
        }
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func getRecipeImages(for collection: Collection) async -> [URL?] {
        do {
            // Load recipes for this collection
            let allRecipes = try await dependencies.recipeRepository.fetchAll()
            let collectionRecipes = allRecipes.filter { recipe in
                collection.recipeIds.contains(recipe.id)
            }

            // Take first 4 recipes and get their image URLs
            return Array(collectionRecipes.prefix(4).map { $0.imageURL })
        } catch {
            AppLogger.general.error("Failed to fetch recipe images for collection: \(error.localizedDescription)")
            return []
        }
    }
}
