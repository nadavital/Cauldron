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
        return try await collectionRepository.fetchAll().first { collection in
            collection.userId == userId &&
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

        if let existing = try await existingSavedCollection(for: sourceCollection) {
            return CollectionSaveResult(
                collection: existing,
                savedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let orderedVisibleRecipes = recipesInCollectionOrder(
            sourceCollection: sourceCollection,
            visibleRecipes: visibleRecipes
        )
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

        let now = Date()
        let savedCollection = Collection(
            name: sourceCollection.name,
            description: sourceCollection.description,
            userId: userId,
            recipeIds: savedRecipeIds,
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
            savedRecipeCount: savedRecipeCount,
            reusedExistingCopy: false
        )
    }

    private func recipesInCollectionOrder(
        sourceCollection: Collection,
        visibleRecipes: [Recipe]
    ) -> [Recipe] {
        let recipesById = Dictionary(uniqueKeysWithValues: visibleRecipes.map { ($0.id, $0) })
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

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "You must be signed in to save a collection."
        }
    }
}
