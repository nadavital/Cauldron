//
//  CollectionsListViewModel.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation
import SwiftUI
import os

private struct RemovedCollectionSnapshot {
    let owned: (collection: Collection, index: Int)?
    let saved: (collection: Collection, index: Int)?
}

@MainActor
@Observable
final class CollectionsListViewModel {
    var ownedCollections: [Collection] = []
    var savedCollections: [Collection] = []
    var isLoading = false
    var searchText = ""
    var showingCreateSheet = false
    var errorMessage: String?
    var showError = false

    let dependencies: DependencyContainer
    @ObservationIgnored private var notificationObservers: [any NSObjectProtocol] = []
    private var recipeImageURLsById: [UUID: URL?] = [:]
    private var recipesById: [UUID: Recipe] = [:]
    private var collectionPreviewRecipesById: [UUID: Recipe] = [:]

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
        let metadataObserver = NotificationCenter.default.addObserver(
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
                if let index = self.savedCollections.firstIndex(where: { $0.id == collectionId }) {
                    self.savedCollections[index] = updatedCollection
                }
            }
        }

        let addedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CollectionAdded"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let addedCollection = notification.userInfo?["collection"] as? Collection else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let currentUserID = CurrentUserSession.shared.userId,
                   addedCollection.userId != currentUserID {
                    return
                }

                guard !self.ownedCollections.contains(where: { $0.id == addedCollection.id }) else {
                    return
                }

                self.ownedCollections.insert(addedCollection, at: 0)
                self.ownedCollections.sort { $0.updatedAt > $1.updatedAt }
            }
        }

        let deletedObserver = NotificationCenter.default.addObserver(
            forName: .collectionDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let collectionId = notification.object as? UUID
                ?? notification.userInfo?["collectionId"] as? UUID
            guard let collectionId else { return }

            Task { @MainActor [weak self] in
                self?.removeCollectionFromDisplay(collectionId: collectionId)
            }
        }

        let recipesChangedObserver = NotificationCenter.default.addObserver(
            forName: .collectionRecipesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let collectionId = notification.userInfo?["collectionId"] as? UUID,
                  let recipeIds = notification.userInfo?["recipeIds"] as? [UUID] else {
                return
            }
            let collection = notification.userInfo?["collection"] as? Collection

            Task { @MainActor [weak self] in
                self?.updateCollectionRecipeMembership(
                    collectionId: collectionId,
                    recipeIds: recipeIds,
                    collection: collection
                )
            }
        }

        let savedReferenceObserver = NotificationCenter.default.addObserver(
            forName: .savedCollectionReferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let changeType = notification.userInfo?["changeType"] as? String
            let collection = notification.userInfo?["collection"] as? Collection
            let sourceCollectionId = notification.userInfo?["sourceCollectionId"] as? UUID

            Task { @MainActor [weak self] in
                guard let self else { return }

                if changeType == "saved", let collection {
                    self.insertSavedCollection(collection)
                } else if changeType == "saved" {
                    await self.loadCollections()
                } else if changeType == "removed", let sourceCollectionId {
                    self.savedCollections.removeAll { $0.sourceCollectionReferenceId == sourceCollectionId }
                }
            }
        }

        notificationObservers = [metadataObserver, addedObserver, deletedObserver, recipesChangedObserver, savedReferenceObserver]
    }

    /// Load all collections
    func loadCollections() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let fetchedCollections = loadCollectionsIncludingSavedReferences()
            async let fetchedRecipes = dependencies.recipeRepository.fetchLibraryRecipes(ownerId: CurrentUserSession.shared.userId)

            let collections = try await fetchedCollections
            let recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await fetchedRecipes,
                currentUserId: CurrentUserSession.shared.userId
            )
            recipesById = RecipeDeduplication.byIdPreferringBest(recipes)
            recipeImageURLsById = recipes.reduce(into: [:]) { partialResult, recipe in
                partialResult[recipe.id] = recipe.imageURL
            }
            await loadPreviewRecipeMetadata(for: collections.saved)
            ownedCollections = collections.owned
            savedCollections = collections.saved
            AppLogger.general.info("✅ Loaded \(self.ownedCollections.count) owned collections and \(self.savedCollections.count) saved collections")
        } catch {
            AppLogger.general.error("❌ Failed to load collections: \(error.localizedDescription)")
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
            showError = true
        }
    }

    private func loadCollectionsIncludingSavedReferences() async throws -> (owned: [Collection], saved: [Collection]) {
        let localCollections = try await dependencies.collectionRepository.fetchAll()

        guard let currentUserId = CurrentUserSession.shared.userId else {
            return Self.splitCollectionsForDisplay(
                localCollections: localCollections,
                savedReferences: [],
                fetchedSourceCollections: [:],
                currentUserId: nil
            )
        }

        let references = try await dependencies.savedReferenceRepository.collectionReferences(for: currentUserId)
        let savedSourceIds = Set(references.map(\.sourceCollectionId))
        let representedSourceIds = Set(localCollections.compactMap { collection -> UUID? in
            let sourceId = collection.sourceCollectionReferenceId
            return collection.userId != currentUserId && savedSourceIds.contains(sourceId) ? sourceId : nil
        })
        let missingSourceIds = references
            .map(\.sourceCollectionId)
            .filter { !representedSourceIds.contains($0) }

        var fetchedSources: [UUID: Collection] = [:]
        if !missingSourceIds.isEmpty {
            fetchedSources = try await dependencies.collectionCloudService.fetchPublicCollections(ids: missingSourceIds)
        }

        return Self.splitCollectionsForDisplay(
            localCollections: localCollections,
            savedReferences: references,
            fetchedSourceCollections: fetchedSources,
            currentUserId: currentUserId
        )
    }

    nonisolated static func splitCollectionsForDisplay(
        localCollections: [Collection],
        savedReferences: [SavedCollectionReference],
        fetchedSourceCollections: [UUID: Collection],
        currentUserId: UUID?
    ) -> (owned: [Collection], saved: [Collection]) {
        guard let currentUserId else {
            return (
                owned: localCollections.sorted { $0.updatedAt > $1.updatedAt },
                saved: []
            )
        }

        let savedSourceIds = Set(savedReferences.map(\.sourceCollectionId))
        let ownedCollections = localCollections
            .filter { $0.userId == currentUserId }
            .sorted { $0.updatedAt > $1.updatedAt }

        var savedCollectionsBySourceId = localCollections.reduce(into: [UUID: Collection]()) { result, collection in
            let sourceId = collection.sourceCollectionReferenceId
            guard collection.userId != currentUserId,
                  savedSourceIds.contains(sourceId),
                  result[sourceId] == nil else {
                return
            }
            result[sourceId] = collection
        }

        for (sourceId, collection) in fetchedSourceCollections where savedCollectionsBySourceId[sourceId] == nil {
            savedCollectionsBySourceId[sourceId] = collection
        }

        let savedCollections = savedReferences.compactMap { savedCollectionsBySourceId[$0.sourceCollectionId] }
        return (owned: ownedCollections, saved: savedCollections)
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

    var filteredSavedCollections: [Collection] {
        if searchText.isEmpty {
            return savedCollections
        }
        return savedCollections.filter { collection in
            collection.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var hasVisibleCollections: Bool {
        !filteredOwnedCollections.isEmpty || !filteredSavedCollections.isEmpty
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
        let removedSnapshot = removeCollectionFromDisplay(collectionId: collection.id)

        do {
            if let currentUserId = CurrentUserSession.shared.userId,
               collection.userId != currentUserId,
               try await dependencies.savedReferenceRepository.deleteCollectionReference(
                   userId: currentUserId,
                   sourceCollectionId: collection.sourceCollectionReferenceId
               ) {
                AppLogger.general.info("Removed saved collection reference: \(collection.name)")
                return
            }

            try await dependencies.collectionRepository.delete(id: collection.id)
            AppLogger.general.info("✅ Deleted collection: \(collection.name)")
        } catch {
            restoreCollectionToDisplay(removedSnapshot)
            AppLogger.general.error("❌ Failed to delete collection: \(error.localizedDescription)")
            errorMessage = "Failed to delete collection: \(error.localizedDescription)"
            showError = true
        }
    }

    @discardableResult
    private func removeCollectionFromDisplay(collectionId: UUID) -> RemovedCollectionSnapshot {
        let ownedIndex = ownedCollections.firstIndex { $0.id == collectionId }
        let savedIndex = savedCollections.firstIndex { $0.id == collectionId }
        let ownedCollection = ownedIndex.map { ownedCollections.remove(at: $0) }
        let savedCollection = savedIndex.map { savedCollections.remove(at: $0) }
        return RemovedCollectionSnapshot(
            owned: ownedCollection.map { (collection: $0, index: ownedIndex ?? ownedCollections.count) },
            saved: savedCollection.map { (collection: $0, index: savedIndex ?? savedCollections.count) }
        )
    }

    private func restoreCollectionToDisplay(_ snapshot: RemovedCollectionSnapshot) {
        if let owned = snapshot.owned,
           !ownedCollections.contains(where: { $0.id == owned.collection.id }) {
            ownedCollections.insert(owned.collection, at: min(owned.index, ownedCollections.count))
        }

        if let saved = snapshot.saved,
           !savedCollections.contains(where: { $0.id == saved.collection.id }) {
            savedCollections.insert(saved.collection, at: min(saved.index, savedCollections.count))
        }
    }

    private func updateCollectionRecipeMembership(
        collectionId: UUID,
        recipeIds: [UUID],
        collection updatedCollection: Collection?
    ) {
        if let index = ownedCollections.firstIndex(where: { $0.id == collectionId }) {
            ownedCollections[index] = updatedCollection ?? CollectionMembershipProjection.collectionWithRecipeIds(
                ownedCollections[index],
                recipeIds
            )
            ownedCollections.sort { $0.updatedAt > $1.updatedAt }
        }

        if let index = savedCollections.firstIndex(where: { $0.id == collectionId }) {
            savedCollections[index] = updatedCollection ?? CollectionMembershipProjection.collectionWithRecipeIds(
                savedCollections[index],
                recipeIds
            )
        }
    }

    private func insertSavedCollection(_ collection: Collection) {
        guard let currentUserId = CurrentUserSession.shared.userId,
              collection.userId != currentUserId else {
            return
        }

        savedCollections.removeAll { $0.sourceCollectionReferenceId == collection.sourceCollectionReferenceId }
        savedCollections.insert(collection, at: 0)
        Task {
            await loadPreviewRecipeMetadata(for: [collection])
        }
    }

    /// Get first 4 recipe image URLs for a collection (for grid display)
    func recipeImages(for collection: Collection) -> [URL?] {
        Array(collection.recipeIds.prefix(12).compactMap { recipeId in
            recipeImageURLsById[recipeId] ?? collectionPreviewRecipesById[recipeId]?.imageURL
        }.prefix(4).map(Optional.some))
    }

    func recipeImageSources(for collection: Collection) -> [CollectionRecipeImageSource] {
        collection.recipeIds.prefix(12).map { recipeId in
            let recipe = recipesById[recipeId] ?? collectionPreviewRecipesById[recipeId]
            let isNonOwnedCollection = collection.userId != CurrentUserSession.shared.userId
            return CollectionRecipeImageSource(
                recipeId: recipeId,
                imageURL: recipe?.imageURL ?? recipeImageURLsById[recipeId] ?? nil,
                ownerId: recipe?.ownerId ?? (isNonOwnedCollection ? collection.userId : nil),
                hasCloudImage: recipe?.cloudImageRecordName != nil || (recipe == nil && isNonOwnedCollection)
            )
        }
    }

    private func loadPreviewRecipeMetadata(for collections: [Collection]) async {
        let knownRecipeIds = Set(recipesById.keys).union(Set(collectionPreviewRecipesById.keys))
        let candidateIds = collections
            .flatMap { $0.recipeIds.prefix(12) }
            .filter { !knownRecipeIds.contains($0) }
        let uniqueIds = Array(Set(candidateIds))
        guard !uniqueIds.isEmpty else { return }

        do {
            let fetchedRecipes = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(ids: uniqueIds)
            for (recipeId, recipe) in fetchedRecipes {
                collectionPreviewRecipesById[recipeId] = recipe
                recipeImageURLsById[recipeId] = recipe.imageURL
            }
        } catch {
            AppLogger.general.warning("Failed to load saved collection preview recipe metadata: \(error.localizedDescription)")
        }
    }
}
