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
    @Published var connections: [ManagedConnection] = []
    @Published var isLoadingConnections = false
    @Published var usersMap: [UUID: User] = [:]

    let user: User
    let dependencies: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    // Recipe caching
    private var lastRecipeLoadTime: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    private var lastConnectionState: ConnectionState?

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
        // Check cache validity
        if !forceRefresh, let lastLoadTime = lastRecipeLoadTime,
           Date().timeIntervalSince(lastLoadTime) < cacheValidityDuration,
           lastConnectionState == connectionState {
            AppLogger.general.info("Using cached recipes for \(self.user.username)")
            return
        }

        // Invalidate cache if connection state changed
        if lastConnectionState != connectionState {
            AppLogger.general.info("Connection state changed, invalidating recipe cache")
            lastConnectionState = connectionState
        }

        isLoadingRecipes = true
        defer { isLoadingRecipes = false }

        do {
            userRecipes = try await fetchUserRecipes()
            lastRecipeLoadTime = Date()
            lastConnectionState = connectionState
            AppLogger.general.info("✅ Loaded \(self.userRecipes.count) recipes for user \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to load user recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }
    }

    private func fetchUserRecipes() async throws -> [SharedRecipe] {
        var allRecipes: [SharedRecipe] = []

        // Get current user to check connection status
        guard let currentUserId = CurrentUserSession.shared.userId else {
            return []
        }

        // Determine if we're connected to this user
        let isConnected = connectionState == .connected

        // Fetch public recipes from this user
        let publicRecipes = try await dependencies.cloudKitService.querySharedRecipes(
            ownerIds: [user.id],
            visibility: .publicRecipe
        )
        AppLogger.general.info("Found \(publicRecipes.count) public recipes from \(self.user.username)")

        // Convert to SharedRecipe
        for recipe in publicRecipes {
            let sharedRecipe = SharedRecipe(
                id: UUID(),
                recipe: recipe,
                sharedBy: user,
                sharedAt: recipe.updatedAt
            )
            allRecipes.append(sharedRecipe)
        }

        // If connected, also fetch friends-only recipes
        if isConnected {
            let friendsRecipes = try await dependencies.cloudKitService.querySharedRecipes(
                ownerIds: [user.id],
                visibility: .friendsOnly
            )
            AppLogger.general.info("Found \(friendsRecipes.count) friends-only recipes from \(self.user.username)")

            for recipe in friendsRecipes {
                let sharedRecipe = SharedRecipe(
                    id: UUID(),
                    recipe: recipe,
                    sharedBy: user,
                    sharedAt: recipe.updatedAt
                )
                allRecipes.append(sharedRecipe)
            }
        }

        // Sort by updated date (most recent first)
        return allRecipes.sorted { $0.sharedAt > $1.sharedAt }
    }

    var filteredRecipes: [SharedRecipe] {
        return userRecipes
    }

    var displayedConnections: [ManagedConnection] {
        return Array(connections.prefix(6))
    }
}
