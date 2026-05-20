//
//  CollectionSaveService.swift
//  Cauldron
//

import Foundation
import os

struct CollectionSaveResult: Sendable, Equatable {
    let collection: Collection
    let savedRecipeCount: Int
    let reusedExistingCopy: Bool
}

actor CollectionSaveService {
    private let collectionRepository: CollectionRepository
    private let recipeSaveService: RecipeSaveService
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionSaveService")

    init(
        collectionRepository: CollectionRepository,
        recipeSaveService: RecipeSaveService
    ) {
        self.collectionRepository = collectionRepository
        self.recipeSaveService = recipeSaveService
    }

    func existingSavedCollection(for sourceCollection: Collection) async throws -> Collection? {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw CollectionSaveServiceError.notAuthenticated
        }

        if sourceCollection.userId == userId {
            return sourceCollection
        }

        let sourceCollectionId = sourceCollection.sourceCollectionReferenceId
        return try await collectionRepository.fetchUserCollections(ownerId: userId).first { collection in
            collection.originalCollectionId == sourceCollectionId
        }
    }

    func saveCollectionToLibrary(
        _ sourceCollection: Collection,
        visibleRecipes: [Recipe],
        sourceOwnerName: String? = nil
    ) async throws -> CollectionSaveResult {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw CollectionSaveServiceError.notAuthenticated
        }

        if sourceCollection.userId == userId {
            return CollectionSaveResult(
                collection: sourceCollection,
                savedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let orderedVisibleRecipes = recipesInCollectionOrder(
            sourceCollection: sourceCollection,
            visibleRecipes: visibleRecipes
        )

        if let existing = try await existingSavedCollection(for: sourceCollection) {
            let reconciliation = try await reconciledExistingCollection(
                existing,
                from: sourceCollection,
                visibleRecipes: orderedVisibleRecipes,
                sourceOwnerName: sourceOwnerName,
                userId: userId
            )
            if let reconciliation {
                return reconciliation
            }

            return CollectionSaveResult(
                collection: existing,
                savedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let savedRecipes = try await saveRecipesForCollection(
            orderedVisibleRecipes,
            sourceOwnerName: sourceOwnerName
        )

        let now = Date()
        let savedCollection = Collection(
            name: sourceCollection.name,
            description: sourceCollection.description,
            userId: userId,
            recipeIds: savedRecipes.recipeIds,
            visibility: sourceCollection.visibility,
            emoji: sourceCollection.emoji,
            symbolName: sourceCollection.symbolName,
            color: sourceCollection.color,
            coverImageType: sourceCollection.coverImageType == .customImage ? .recipeGrid : sourceCollection.coverImageType,
            originalCollectionId: sourceCollection.sourceCollectionReferenceId,
            originalCollectionOwnerId: sourceCollection.originalCollectionOwnerId ?? sourceCollection.userId,
            originalCollectionName: sourceCollection.originalCollectionName ?? sourceCollection.name,
            savedAt: now,
            sourceCollectionUpdatedAt: sourceCollection.updatedAt,
            followsSourceUpdates: true,
            createdAt: now,
            updatedAt: now
        )

        try await collectionRepository.create(savedCollection)
        logger.info("Saved collection to library: \(savedCollection.name)")
        return CollectionSaveResult(
            collection: savedCollection,
            savedRecipeCount: savedRecipes.savedRecipeCount,
            reusedExistingCopy: false
        )
    }

    private func reconciledExistingCollection(
        _ existing: Collection,
        from sourceCollection: Collection,
        visibleRecipes orderedVisibleRecipes: [Recipe],
        sourceOwnerName: String?,
        userId: UUID
    ) async throws -> CollectionSaveResult? {
        guard existing.followsSourceUpdates else { return nil }

        let sourceUpdatedAt = sourceCollection.updatedAt
        if let sourceCollectionUpdatedAt = existing.sourceCollectionUpdatedAt,
           sourceUpdatedAt <= sourceCollectionUpdatedAt {
            return nil
        }

        let visibleRecipeIds = Set(orderedVisibleRecipes.map(\.id))
        let sourceRecipeIds = Set(sourceCollection.recipeIds)
        guard sourceRecipeIds.isSubset(of: visibleRecipeIds) else {
            let availableSourceRecipeCount = sourceRecipeIds.intersection(visibleRecipeIds).count
            logger.warning("Skipping saved collection reconciliation because only \(availableSourceRecipeCount) of \(sourceCollection.recipeIds.count) source recipes are visible")
            throw CollectionSaveServiceError.sourceRecipesUnavailable(
                visibleCount: availableSourceRecipeCount,
                totalCount: sourceCollection.recipeIds.count
            )
        }

        let savedRecipes = try await saveRecipesForCollection(
            orderedVisibleRecipes,
            sourceOwnerName: sourceOwnerName
        )
        let updatedCollection = Collection(
            id: existing.id,
            name: sourceCollection.name,
            description: sourceCollection.description,
            userId: userId,
            recipeIds: savedRecipes.recipeIds,
            visibility: sourceCollection.visibility,
            emoji: sourceCollection.emoji,
            symbolName: sourceCollection.symbolName,
            color: sourceCollection.color,
            coverImageType: sourceCollection.coverImageType == .customImage ? .recipeGrid : sourceCollection.coverImageType,
            cloudRecordName: existing.cloudRecordName,
            originalCollectionId: existing.originalCollectionId ?? sourceCollection.sourceCollectionReferenceId,
            originalCollectionOwnerId: existing.originalCollectionOwnerId ?? sourceCollection.originalCollectionOwnerId ?? sourceCollection.userId,
            originalCollectionName: existing.originalCollectionName ?? sourceCollection.originalCollectionName ?? sourceCollection.name,
            savedAt: existing.savedAt,
            sourceCollectionUpdatedAt: sourceUpdatedAt,
            followsSourceUpdates: true,
            createdAt: existing.createdAt,
            updatedAt: Date()
        )

        try await collectionRepository.update(updatedCollection)
        logger.info("Reconciled saved collection from source updates: \(updatedCollection.name)")
        return CollectionSaveResult(
            collection: updatedCollection,
            savedRecipeCount: savedRecipes.savedRecipeCount,
            reusedExistingCopy: true
        )
    }

    private func saveRecipesForCollection(
        _ orderedVisibleRecipes: [Recipe],
        sourceOwnerName: String?
    ) async throws -> (recipeIds: [UUID], savedRecipeCount: Int) {
        var savedRecipeIds: [UUID] = []
        var savedRecipeCount = 0

        for recipe in orderedVisibleRecipes {
            let result = try await recipeSaveService.saveRecipeToLibrary(
                recipe,
                originalCreatorId: recipe.originalCreatorId ?? recipe.ownerId,
                originalCreatorName: recipe.originalCreatorName ?? sourceOwnerName
            )
            savedRecipeIds.append(result.recipe.id)
            if !result.reusedExistingCopy {
                savedRecipeCount += 1
            }
        }

        return (savedRecipeIds, savedRecipeCount)
    }

    private func recipesInCollectionOrder(
        sourceCollection: Collection,
        visibleRecipes: [Recipe]
    ) -> [Recipe] {
        let recipesById = Dictionary(visibleRecipes.map { ($0.id, $0) }, uniquingKeysWith: { current, candidate in
            candidate.updatedAt > current.updatedAt ? candidate : current
        })
        var seenRecipeIds = Set<UUID>()
        var orderedRecipes: [Recipe] = []

        for recipeId in sourceCollection.recipeIds {
            guard let recipe = recipesById[recipeId] else { continue }
            orderedRecipes.append(recipe)
            seenRecipeIds.insert(recipe.id)
        }

        orderedRecipes.append(contentsOf: visibleRecipes.filter { !seenRecipeIds.contains($0.id) })
        return orderedRecipes
    }
}

enum CollectionSaveServiceError: LocalizedError {
    case notAuthenticated
    case sourceRecipesUnavailable(visibleCount: Int, totalCount: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "You must be signed in to save a collection."
        case .sourceRecipesUnavailable(let visibleCount, let totalCount):
            "This collection could not be updated because only \(visibleCount) of \(totalCount) source recipes are available."
        }
    }
}
