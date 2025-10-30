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
    @Published var referencedCollections: [CollectionReference] = []
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var showingCreateSheet = false
    @Published var errorMessage: String?
    @Published var showError = false

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    /// Load all collections (owned + referenced)
    func loadCollections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load owned collections
            ownedCollections = try await dependencies.collectionRepository.fetchAll()
            AppLogger.general.info("✅ Loaded \(self.ownedCollections.count) owned collections")

            // Load referenced collections if user is logged in
            if let userId = CurrentUserSession.shared.userId {
                referencedCollections = try await dependencies.cloudKitService.fetchCollectionReferences(forUserId: userId)
                AppLogger.general.info("✅ Loaded \(self.referencedCollections.count) referenced collections")
            }
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

    /// Filtered referenced collections based on search text
    var filteredReferencedCollections: [CollectionReference] {
        if searchText.isEmpty {
            return referencedCollections
        }
        return referencedCollections.filter { reference in
            reference.collectionName.localizedCaseInsensitiveContains(searchText)
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

    /// Delete a collection reference
    func deleteCollectionReference(_ reference: CollectionReference) async {
        do {
            try await dependencies.cloudKitService.deleteCollectionReference(reference.id)
            await loadCollections()
            AppLogger.general.info("✅ Removed collection reference: \(reference.collectionName)")
        } catch {
            AppLogger.general.error("❌ Failed to remove collection reference: \(error.localizedDescription)")
            errorMessage = "Failed to remove collection reference: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Get recipes for a collection
    func getRecipes(for collection: Collection) async throws -> [Recipe] {
        // Fetch all recipes (owned + referenced)
        var allRecipes = try await dependencies.recipeRepository.fetchAll()

        // Add referenced recipes if available
        if let userId = CurrentUserSession.shared.userId {
            let references = try await dependencies.cloudKitService.fetchRecipeReferences(forUserId: userId)

            for reference in references {
                // Fetch the actual recipe from public database
                if let sharedRecipe = try? await fetchSharedRecipe(recipeId: reference.originalRecipeId, ownerId: reference.originalOwnerId) {
                    allRecipes.append(sharedRecipe)
                }
            }
        }

        // Filter to only recipes in this collection
        return allRecipes.filter { recipe in
            collection.recipeIds.contains(recipe.id)
        }
    }

    /// Fetch a shared recipe from public database
    private func fetchSharedRecipe(recipeId: UUID, ownerId: UUID) async throws -> Recipe? {
        // Query public database for the shared recipe
        let sharedRecipes = try await dependencies.cloudKitService.querySharedRecipes(
            ownerIds: [ownerId],
            visibility: .publicRecipe
        )

        return sharedRecipes.first { $0.id == recipeId }
    }
}
