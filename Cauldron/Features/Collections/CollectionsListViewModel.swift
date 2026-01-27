//
//  CollectionsListViewModel.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
class CollectionsListViewModel: ObservableObject {
    @Published var ownedCollections: [Collection] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var showingCreateSheet = false
    @Published var errorMessage: String?
    @Published var showError = false

    let dependencies: DependencyContainer
    private var cancellables = Set<AnyCancellable>()

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        setupCollectionNotificationObserver()
    }

    /// Setup observer for collection metadata changes to update UI immediately
    private func setupCollectionNotificationObserver() {
        NotificationCenter.default.publisher(for: .collectionMetadataChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let collectionId = notification.userInfo?["collectionId"] as? UUID,
                      let updatedCollection = notification.userInfo?["collection"] as? Collection else {
                    return
                }
                // Update the collection in our local array for immediate UI refresh
                if let index = self.ownedCollections.firstIndex(where: { $0.id == collectionId }) {
                    self.ownedCollections[index] = updatedCollection
                }
            }
            .store(in: &cancellables)
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
