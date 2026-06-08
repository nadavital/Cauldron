//
//  SharingTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import os

@MainActor
@Observable
final class FriendsTabViewModel {
    static let shared = FriendsTabViewModel()

    var sharedRecipes: [SharedRecipe] = []
    var sharedCollections: [Collection] = []
    var isLoading = false
    var showSuccessAlert = false
    var showErrorAlert = false
    var alertMessage = ""

    // Organized sections for better UX
    var recentlyAdded: [SharedRecipe] = []
    var tagSections: [(tag: String, recipes: [SharedRecipe])] = []

    // Tier information for shared recipe creators
    var sharerTiers: [UUID: UserTier] = [:]

    /// Look up the owner of a friend's shared collection from the friends who
    /// have shared recipes (used to tag collection cards with their creator).
    func owner(for collection: Collection) -> User? {
        sharedRecipes.first(where: { $0.sharedBy.id == collection.userId })?.sharedBy
    }

    @ObservationIgnored
    private(set) var dependencies: DependencyContainer?
    @ObservationIgnored
    private var hasLoadedOnce = false
    @ObservationIgnored
    private var loadedUserId: UUID?

    private init() {
        // Private init for singleton
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func configure(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func resetSessionState() {
        sharedRecipes = []
        sharedCollections = []
        isLoading = false
        showSuccessAlert = false
        showErrorAlert = false
        alertMessage = ""
        recentlyAdded = []
        tagSections = []
        sharerTiers = [:]
        hasLoadedOnce = false
        loadedUserId = nil
    }

    func loadSharedRecipes(forceRefresh: Bool = false) async {
        guard let dependencies = dependencies else {
            AppLogger.general.warning("FriendsTabViewModel not configured with dependencies")
            return
        }

        guard let currentUserId = CurrentUserSession.shared.userId else {
            resetSessionState()
            return
        }

        if loadedUserId != currentUserId {
            resetSessionState()
            loadedUserId = currentUserId
        }

        if RuntimeEnvironment.isSimulatorQAMode {
            await loadSimulatorQAContent(dependencies: dependencies)
            return
        }

        // On first load, try to use cached data for instant display
        if !hasLoadedOnce {
            if let cached = await dependencies.sharingService.getCachedSharedRecipes(for: currentUserId) {
                guard isCurrentLoadValid(for: currentUserId) else { return }
                // Show cached data immediately
                sharedRecipes = cached
                organizeRecipesIntoSections()
                await preloadImagesForSharedRecipes()
                guard isCurrentLoadValid(for: currentUserId) else { return }
                hasLoadedOnce = true

                // Fetch tiers in background
                await fetchSharerTiers(for: currentUserId)
                await loadSharedCollections(for: currentUserId)
                return
            }
            // No cache, show loading indicator
            isLoading = true
        }

        defer {
            if isCurrentLoadValid(for: currentUserId) {
                isLoading = false
                hasLoadedOnce = true
            }
        }

        do {
            let recipes = try await dependencies.sharingService.getSharedRecipes(forceRefresh: forceRefresh)
            guard isCurrentLoadValid(for: currentUserId) else { return }
            sharedRecipes = recipes
            organizeRecipesIntoSections()

            // Fetch tier information for sharers
            await fetchSharerTiers(for: currentUserId)

            // Load friends' shared collections
            await loadSharedCollections(for: currentUserId)

            // Preload images into memory cache to prevent flickering
            await preloadImagesForSharedRecipes()
        } catch {
            AppLogger.general.error("Failed to load shared recipes: \(error.localizedDescription)")
            alertMessage = "Failed to load shared recipes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func isCurrentLoadValid(for userId: UUID) -> Bool {
        !Task.isCancelled && CurrentUserSession.shared.userId == userId && loadedUserId == userId
    }

    private func loadSharedCollections(for expectedUserId: UUID) async {
        guard let dependencies = dependencies else { return }

        guard let currentUser = CurrentUserSession.shared.currentUser else {
            sharedCollections = []
            return
        }
        guard currentUser.id == expectedUserId else { return }

        do {
            let connections = try await dependencies.connectionCloudService.fetchConnections(forUserId: currentUser.id)
            let acceptedConnections = connections.filter { $0.isAccepted }

            let friendIds = Set(acceptedConnections.flatMap { connection -> [UUID] in
                var ids: [UUID] = []
                if connection.fromUserId != currentUser.id {
                    ids.append(connection.fromUserId)
                }
                if connection.toUserId != currentUser.id {
                    ids.append(connection.toUserId)
                }
                return ids
            })

            guard !friendIds.isEmpty else {
                guard isCurrentLoadValid(for: expectedUserId) else { return }
                sharedCollections = []
                return
            }

            let collections = try await dependencies.collectionCloudService.fetchSharedCollections(friendIds: Array(friendIds))
            guard isCurrentLoadValid(for: expectedUserId) else { return }
            var deduped: [UUID: Collection] = [:]
            for collection in collections {
                deduped[collection.id] = collection
            }
            sharedCollections = Array(deduped.values).sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            guard isCurrentLoadValid(for: expectedUserId) else { return }
            AppLogger.general.warning("Failed to load shared collections: \(error.localizedDescription)")
            sharedCollections = []
        }
    }

    private func loadSimulatorQAContent(dependencies: DependencyContainer) async {
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            sharedRecipes = try await dependencies.sharingRepository.fetchAllSharedRecipes()
            sharedCollections = try await dependencies.collectionRepository.fetchAll()
                .filter { $0.userId != CurrentUserSession.shared.currentUser?.id }
                .sorted { $0.updatedAt > $1.updatedAt }
            sharerTiers = Dictionary(
                uniqueKeysWithValues: Set(sharedRecipes.map(\.sharedBy.id)).map { ($0, UserTier.apprentice) }
            )
            organizeRecipesIntoSections()
            await preloadImagesForSharedRecipes()
        } catch {
            AppLogger.general.error("Failed to load simulator QA shared recipes: \(error.localizedDescription)")
            sharedRecipes = []
            sharedCollections = []
        }
    }

    /// Get first 4 visible recipe image URLs for a shared collection card.
    func getRecipeImages(for collection: Collection) async -> [URL?] {
        guard let dependencies else { return [] }
        return await SharedCollectionPreviewLoader.loadPreviewImageURLs(
            for: collection,
            dependencies: dependencies
        )
    }

    /// Organize shared recipes into curated sections
    private func organizeRecipesIntoSections() {
        // Recently Added - recipes shared in the last 7 days, sorted by date
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        recentlyAdded = sharedRecipes
            .filter { $0.sharedAt > sevenDaysAgo }
            .sorted { $0.sharedAt > $1.sharedAt }

        // Tag-based sections - group recipes by their tags
        var tagGroups: [String: [SharedRecipe]] = [:]
        for sharedRecipe in sharedRecipes {
            for tag in sharedRecipe.recipe.tags {
                tagGroups[tag.name, default: []].append(sharedRecipe)
            }
        }

        // Only include tags with at least 3 recipes
        tagSections = tagGroups
            .filter { $0.value.count >= 3 }
            .map { (tag: $0.key, recipes: $0.value.sorted { $0.sharedAt > $1.sharedAt }) }
            .sorted { $0.recipes.count > $1.recipes.count } // Sort by number of recipes
    }

    /// Preload recipe images and profile avatars into memory cache
    /// This prevents flickering when scrolling through shared recipes
    private func preloadImagesForSharedRecipes() async {
        guard let dependencies = dependencies else { return }
        await dependencies.entityImageLoader.preloadSharedRecipeAndProfileImages(sharedRecipes: sharedRecipes)
    }

    func copyToPersonalCollection(_ sharedRecipe: SharedRecipe) async {
        guard let dependencies = dependencies else { return }
        do {
            let copiedRecipe = try await dependencies.recipeSaveService.saveRecipeToLibrary(
                sharedRecipe.recipe,
                originalCreatorId: sharedRecipe.sharedBy.id,
                originalCreatorName: sharedRecipe.sharedBy.displayName
            ).recipe
            AppLogger.general.info("Copied shared recipe to personal collection: \(copiedRecipe.title)")
            // Toast notification is shown in RecipeDetailView
        } catch {
            AppLogger.general.error("Failed to copy recipe: \(error.localizedDescription)")
            alertMessage = "Failed to copy recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Fetch tier information for users who shared recipes
    private func fetchSharerTiers(for expectedUserId: UUID) async {
        guard let dependencies = dependencies else { return }

        // Collect unique sharer user IDs
        let sharerIds = Set(sharedRecipes.map { $0.sharedBy.id })

        guard !sharerIds.isEmpty else { return }

        do {
            let uncachedSharerIds = sharerIds.filter { sharerTiers[$0] == nil }
            guard !uncachedSharerIds.isEmpty else { return }

            let counts = try await dependencies.recipeDiscoveryCache.batchFetchPublicRecipeCounts(
                forOwnerIds: Array(uncachedSharerIds)
            )

            guard isCurrentLoadValid(for: expectedUserId) else { return }
            for sharerId in uncachedSharerIds {
                let count = counts[sharerId] ?? 0
                sharerTiers[sharerId] = UserTier.tier(for: count)
            }
        } catch {
            AppLogger.general.error("Failed to fetch sharer tiers: \(error.localizedDescription)")
        }
    }
}
