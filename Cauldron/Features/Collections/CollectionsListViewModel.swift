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

                // Validate stale references in background
                await validateStaleReferences()
            }
        } catch {
            AppLogger.general.error("❌ Failed to load collections: \(error.localizedDescription)")
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Validate collection references that are older than 24 hours
    private func validateStaleReferences() async {
        let staleReferences = referencedCollections.filter { $0.needsValidation }

        guard !staleReferences.isEmpty else {
            AppLogger.general.info("No stale references to validate")
            return
        }

        AppLogger.general.info("Validating \(staleReferences.count) stale collection references")

        for reference in staleReferences {
            await validateReference(reference)
        }
    }

    /// Validate a single collection reference
    private func validateReference(_ reference: CollectionReference) async {
        do {
            // Try to fetch the original collection
            let sharedCollections = try await dependencies.cloudKitService.fetchSharedCollections(
                friendIds: [reference.originalOwnerId]
            )

            if let currentCollection = sharedCollections.first(where: { $0.id == reference.originalCollectionId }) {
                // Collection still exists - update metadata if changed
                let hasChanged = currentCollection.name != reference.collectionName ||
                                currentCollection.recipeCount != reference.recipeCount ||
                                currentCollection.visibility.rawValue != reference.cachedVisibility

                if hasChanged {
                    AppLogger.general.info("Collection '\(reference.collectionName)' has changed - updating reference")
                    let updatedReference = reference.withUpdatedMetadata(from: currentCollection)
                    try await dependencies.cloudKitService.saveCollectionReference(updatedReference)

                    // Reload to show updated data
                    if let userId = CurrentUserSession.shared.userId {
                        referencedCollections = try await dependencies.cloudKitService.fetchCollectionReferences(forUserId: userId)
                    }
                } else {
                    // Just update validation timestamp
                    let updated = reference.withUpdatedValidation()
                    try await dependencies.cloudKitService.saveCollectionReference(updated)
                }
            } else {
                // Collection no longer exists or is now private
                AppLogger.general.warning("Collection '\(reference.collectionName)' is no longer available")
                // We'll keep the reference but it will show an error when opened
                // User can manually remove it
            }
        } catch {
            AppLogger.general.error("Failed to validate reference '\(reference.collectionName)': \(error.localizedDescription)")
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
        // Fetch all owned recipes
        let allRecipes = try await dependencies.recipeRepository.fetchAll()

        // Filter to only recipes in this collection
        return allRecipes.filter { recipe in
            collection.recipeIds.contains(recipe.id)
        }
    }
}
