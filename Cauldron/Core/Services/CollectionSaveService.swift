//
//  CollectionSaveService.swift
//  Cauldron
//

import Foundation
import os

struct CollectionSaveResult: Sendable, Equatable {
    let collection: Collection
    let savedReference: SavedCollectionReference?
    let savedRecipeCount: Int
    let reusedExistingCopy: Bool
}

actor CollectionSaveService {
    private let collectionRepository: CollectionRepository
    private let savedReferenceRepository: SavedReferenceRepository
    private let recipeSaveService: RecipeSaveService
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionSaveService")

    init(
        collectionRepository: CollectionRepository,
        savedReferenceRepository: SavedReferenceRepository,
        recipeSaveService: RecipeSaveService
    ) {
        self.collectionRepository = collectionRepository
        self.savedReferenceRepository = savedReferenceRepository
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
        if try await savedReferenceRepository.collectionReference(
            userId: userId,
            sourceCollectionId: sourceCollectionId
        ) != nil {
            return sourceCollection
        }

        let legacySavedCopy = try await collectionRepository.fetchAll().first { collection in
            collection.userId == userId &&
            collection.originalCollectionId == sourceCollectionId
        }
        return legacySavedCopy == nil ? nil : sourceCollection
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
                savedReference: nil,
                savedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        if let existing = try await existingSavedCollection(for: sourceCollection) {
            let referenceResult = try await savedReferenceRepository.saveCollectionReference(
                sourceCollection: sourceCollection,
                userId: userId
            )
            return CollectionSaveResult(
                collection: existing,
                savedReference: referenceResult.reference,
                savedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let referenceResult = try await savedReferenceRepository.saveCollectionReference(
            sourceCollection: sourceCollection,
            userId: userId
        )
        logger.info("Saved collection reference to library: \(sourceCollection.name)")
        return CollectionSaveResult(
            collection: sourceCollection,
            savedReference: referenceResult.reference,
            savedRecipeCount: 0,
            reusedExistingCopy: referenceResult.reusedExistingReference
        )
    }

    private func recipesInCollectionOrder(
        sourceCollection: Collection,
        visibleRecipes: [Recipe]
    ) -> [Recipe] {
        let recipesById = RecipeDeduplication.byIdPreferringBest(visibleRecipes)
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
