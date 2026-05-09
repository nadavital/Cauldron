//
//  UserProfileViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import os

/// View model for user profile view - handles connection management and user info
@MainActor
@Observable final class UserProfileViewModel {
    var connectionState: ConnectionRelationshipState = .syncing
    var isLoadingConnectionState = false
    var showError = false
    var errorMessage = ""
    var isProcessing = false
    var userRecipes: [SharedRecipe] = [] {
        didSet {
            rebuildFilteredRecipes()
        }
    }
    var isLoadingRecipes = false
    var userCollections: [Collection] = []
    var isLoadingCollections = false
    var connections: [ManagedConnection] = []
    var isLoadingConnections = false
    var usersMap: [UUID: User] = [:]
    var searchText = "" {
        didSet {
            rebuildFilteredRecipes()
        }
    }
    var userTier: UserTier = .apprentice
    var userRecipeCount: Int = 0
    private(set) var filteredRecipes: [SharedRecipe] = []

    let user: User
    let dependencies: DependencyContainer
    private let connectionCoordinator: ConnectionInteractionCoordinator
    private var recipeImageURLsById: [UUID: URL?] = [:]
    private var collectionImageRecipesById: [UUID: Recipe] = [:]

    var currentUserId: UUID {
        dependencies.connectionManager.currentUserId
    }

    var isCurrentUser: Bool {
        user.id == currentUserId
    }

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        self.dependencies = dependencies
        self.connectionCoordinator = ConnectionInteractionCoordinator(
            connectionManager: dependencies.connectionManager,
            currentUserProvider: { dependencies.connectionManager.currentUserId }
        )
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadConnectionStatus() async {
        await updateConnectionState()
    }

    func loadProfileData(forceRefresh: Bool = false) async {
        await loadConnectionStatus()

        async let recipes: Void = loadUserRecipes(forceRefresh: forceRefresh)
        async let collections: Void = loadUserCollections(forceRefresh: forceRefresh)

        if isCurrentUser {
            async let connections: Void = loadConnections()
            _ = await (recipes, collections, connections)
        } else {
            _ = await (recipes, collections)
        }
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
                    let user = try await dependencies.userCloudService.fetchUser(byUserId: otherUserId)
                    usersMap[otherUserId] = user
                } catch {
                    AppLogger.general.error("Failed to load user \(otherUserId): \(error.localizedDescription)")
                }
            }
        }
    }

    private func updateConnectionState() async {
        isLoadingConnectionState = true
        defer { isLoadingConnectionState = false }

        if isCurrentUser {
            connectionState = .currentUser
            return
        }

        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)
        connectionState = connectionCoordinator.relationshipState(with: user.id)
    }

    func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionCoordinator.sendRequest(to: user)
            await updateConnectionState()
            AppLogger.general.info("✅ Connection request sent to \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to send connection request: \(error.localizedDescription)")
            errorMessage = "Failed to send request: \(error.localizedDescription)"
            showError = true
        }
    }

    func acceptConnection() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionCoordinator.acceptRequest(from: user.id)
            await updateConnectionState()
            AppLogger.general.info("✅ Connection accepted from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to accept connection: \(error.localizedDescription)")
            errorMessage = "Failed to accept: \(error.localizedDescription)"
            showError = true
        }
    }

    func rejectConnection() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionCoordinator.rejectRequest(from: user.id)
            await updateConnectionState()
            AppLogger.general.info("✅ Connection rejected from \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to reject connection: \(error.localizedDescription)")
            errorMessage = "Failed to reject: \(error.localizedDescription)"
            showError = true
        }
    }

    func removeConnection() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionCoordinator.removeConnection(with: user.id)
            await updateConnectionState()
            AppLogger.general.info("✅ Connection removed with \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to remove connection: \(error.localizedDescription)")
            errorMessage = "Failed to remove connection: \(error.localizedDescription)"
            showError = true
        }
    }

    func cancelConnectionRequest() async {
        guard connectionState == .pendingOutgoing else {
            AppLogger.general.error("Connection is not a pending sent request")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            try await connectionCoordinator.removeConnection(with: user.id)
            await updateConnectionState()
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
            recipeImageURLsById = cachedRecipes.reduce(into: [:]) { partialResult, sharedRecipe in
                partialResult[sharedRecipe.recipe.id] = sharedRecipe.recipe.imageURL
            }
            collectionImageRecipesById = cachedRecipes.reduce(into: [:]) { partialResult, sharedRecipe in
                partialResult[sharedRecipe.recipe.id] = sharedRecipe.recipe
            }
            updateTierFromRecipes()
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

            // Update tier based on recipe count
            updateTierFromRecipes()

            AppLogger.general.info("✅ Loaded \(self.userRecipes.count) recipes for user \(self.user.username)")
        } catch {
            AppLogger.general.error("❌ Failed to load user recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }

        isLoadingRecipes = false
    }

    /// Update the user's tier based on their recipe count
    private func updateTierFromRecipes() {
        userRecipeCount = userRecipes.count
        userTier = UserTier.tier(for: userRecipeCount)
    }

    private func fetchUserRecipes() async throws -> [SharedRecipe] {
        // Get current user to check connection status
        guard CurrentUserSession.shared.userId != nil else {
            return []
        }

        var recipes: [Recipe]

        // If viewing your own profile, fetch from local storage (same as Cook tab)
        if isCurrentUser {
            recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await dependencies.recipeRepository.fetchAll(),
                currentUserId: CurrentUserSession.shared.userId
            )
            AppLogger.general.info("Found \(recipes.count) owned recipes from local storage")
        } else {
            // If viewing someone else's profile, fetch their public recipes from CloudKit
            recipes = try await dependencies.recipeDiscoveryCache.querySharedRecipes(
                ownerIds: [user.id],
                visibility: .publicRecipe,
                includeDerivedCopies: true
            )
            AppLogger.general.info("Found \(recipes.count) public recipes from \(self.user.username)")
        }

        // Filter out recipes that are only referenced by other recipes (to avoid duplicates)
        // A recipe that appears in another recipe's relatedRecipeIds should not be shown separately
        collectionImageRecipesById = recipes.reduce(into: [:]) { partialResult, recipe in
            partialResult[recipe.id] = recipe
        }
        recipeImageURLsById = recipes.reduce(into: [:]) { partialResult, recipe in
            partialResult[recipe.id] = recipe.imageURL
        }

        let filteredRecipes = RecipeGroupingService.hideRelatedRecipeReferences(recipes)
        AppLogger.general.info("Filtered from \(recipes.count) to \(filteredRecipes.count) visible profile recipes")

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
        var seenCollectionIds = Set<UUID>()

        // Only show public collections on profiles (simplified from private/friends/public to private/public)

        // If viewing own profile, load local collections (excluding private)
        if isCurrentUser {
            let localCollections = try await dependencies.collectionRepository.fetchAll(visibility: .publicRecipe)
            AppLogger.general.info("Found \(localCollections.count) total local collections")
            allCollections.append(contentsOf: localCollections)
            seenCollectionIds.formUnion(localCollections.map(\.id))
        }

        // Fetch collections from CloudKit
        if CurrentUserSession.shared.isCloudSyncAvailable {
            do {
                // Fetch public collections
                let publicCollections = try await dependencies.collectionCloudService.queryCollections(
                    ownerIds: [user.id],
                    visibility: .publicRecipe
                )
                AppLogger.general.info("Found \(publicCollections.count) public collections from CloudKit for \(self.user.username)")

                // Add CloudKit collections that aren't already in local storage
                for cloudCollection in publicCollections {
                    if seenCollectionIds.insert(cloudCollection.id).inserted {
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
        await loadProfileData(forceRefresh: true)
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func getRecipeImages(for collection: Collection) -> [URL?] {
        Array(collection.recipeIds.compactMap { recipeImageURLsById[$0] ?? nil }.prefix(4).map(Optional.some))
    }

    func getRecipeImageSources(for collection: Collection) -> [CollectionRecipeImageSource] {
        collection.recipeIds.prefix(4).map { recipeId in
            let recipe = collectionImageRecipesById[recipeId]
            return CollectionRecipeImageSource(
                recipeId: recipeId,
                imageURL: recipe?.imageURL ?? recipeImageURLsById[recipeId] ?? nil,
                ownerId: recipe?.ownerId,
                hasCloudImage: recipe?.cloudImageRecordName != nil
            )
        }
    }

    private func rebuildFilteredRecipes() {
        let normalizedQuery = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            filteredRecipes = userRecipes
            return
        }

        filteredRecipes = userRecipes.filter { sharedRecipe in
            sharedRecipe.recipe.title.lowercased().contains(normalizedQuery) ||
            sharedRecipe.recipe.tags.contains(where: { $0.name.lowercased().contains(normalizedQuery) }) ||
            sharedRecipe.recipe.ingredients.contains(where: { $0.name.lowercased().contains(normalizedQuery) })
        }
    }
}
