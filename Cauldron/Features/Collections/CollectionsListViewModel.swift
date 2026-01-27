//
//  CollectionsListViewModel.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftUI
import os

@MainActor
@Observable
final class CollectionsListViewModel {
    var ownedCollections: [Collection] = []
    var isLoading = false
    var searchText = ""
    var showingCreateSheet = false
    var errorMessage: String?
    var showError = false

    let dependencies: DependencyContainer
    @ObservationIgnored private var notificationObserver: (any NSObjectProtocol)?

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        setupCollectionNotificationObserver()
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {
        // Note: Cannot access notificationObserver here as it's isolated
        // NotificationCenter observer cleanup happens automatically
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
                if let index = self.ownedCollections.firstIndex(where: { $0.id == collectionId }) {
                    self.ownedCollections[index] = updatedCollection
                }
            }
        }
    }

    /// Load all collections
    func loadCollections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            ownedCollections = try await dependencies.collectionRepository.fetchAll()
            AppLogger.general.info("✅ Loaded \(self.ownedCollections.count) collections")
        } catch {
            AppLogger.general.error("❌ Failed to load collections: \(error.localizedDescription)")
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Filtered collections based on search text
    var filteredOwnedCollections: [Collection] {
        if searchText.isEmpty {
            return ownedCollections
        }
        return ownedCollections.filter { collection in
            collection.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Create a new collection
    func createCollection(name: String, emoji: String?, color: String?, visibility: RecipeVisibility) async {
        guard let userId = CurrentUserSession.shared.userId else {
            errorMessage = "You must be signed in to create collections"
            showError = true
            return
        }

        do {
            let newCollection = Collection.new(name: name, userId: userId)
                .updated(
                    visibility: visibility,
                    emoji: emoji,
                    color: color
                )

            try await dependencies.collectionRepository.create(newCollection)
            await loadCollections()
            AppLogger.general.info("✅ Created collection: \(name)")
        } catch {
            AppLogger.general.error("❌ Failed to create collection: \(error.localizedDescription)")
            errorMessage = "Failed to create collection: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Delete a collection
    func deleteCollection(_ collection: Collection) async {
        do {
            try await dependencies.collectionRepository.delete(id: collection.id)
            await loadCollections()
            AppLogger.general.info("✅ Deleted collection: \(collection.name)")
        } catch {
            AppLogger.general.error("❌ Failed to delete collection: \(error.localizedDescription)")
            errorMessage = "Failed to delete collection: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Get recipes for a collection
    func getRecipes(for collection: Collection) async throws -> [Recipe] {
        // Fetch all owned recipes
        let allRecipes = try await dependencies.recipeRepository.fetchAll()

        // Filter to only recipes in this collection
        return allRecipes.filter { recipe in
            collection.recipeIds.contains(recipe.id)
        }
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func getRecipeImages(for collection: Collection) async -> [URL?] {
        do {
            let recipes = try await getRecipes(for: collection)
            // Take first 4 recipes and get their image URLs
            return Array(recipes.prefix(4).map { $0.imageURL })
        } catch {
            AppLogger.general.error("Failed to fetch recipe images for collection: \(error.localizedDescription)")
            return []
        }
    }
}
