//
//  LibraryRelationResolver.swift
//  Cauldron
//

import Foundation

enum RecipeLibraryRelation: Sendable, Equatable {
    case unknown
    case notSaved
    case owned
    case saved(materializedRecipeId: UUID?)

    nonisolated var isKnown: Bool {
        switch self {
        case .unknown:
            return false
        case .notSaved, .owned, .saved:
            return true
        }
    }

    nonisolated var isSavedOrOwned: Bool {
        switch self {
        case .owned, .saved:
            return true
        case .unknown, .notSaved:
            return false
        }
    }
}

enum CollectionLibraryRelation: Sendable, Equatable {
    case unknown
    case notSaved
    case owned
    case saved(referenceId: UUID?)

    nonisolated var isKnown: Bool {
        switch self {
        case .unknown:
            return false
        case .notSaved, .owned, .saved:
            return true
        }
    }

    nonisolated var isSavedOrOwned: Bool {
        switch self {
        case .owned, .saved:
            return true
        case .unknown, .notSaved:
            return false
        }
    }
}

actor LibraryRelationResolver {
    private let recipeRepository: RecipeRepository
    private let savedReferenceRepository: SavedReferenceRepository

    init(
        recipeRepository: RecipeRepository,
        savedReferenceRepository: SavedReferenceRepository
    ) {
        self.recipeRepository = recipeRepository
        self.savedReferenceRepository = savedReferenceRepository
    }

    func recipeRelation(
        for recipe: Recipe,
        currentUserId: UUID?
    ) async throws -> RecipeLibraryRelation {
        guard let currentUserId else {
            return .notSaved
        }

        if recipe.ownerId == currentUserId && !recipe.isPreview {
            return .owned
        }

        let sourceRecipeId = recipe.relatedGraphReferenceID
        if let reference = try await savedReferenceRepository.recipeReference(
            userId: currentUserId,
            sourceRecipeId: sourceRecipeId
        ) {
            return .saved(materializedRecipeId: reference.materializedRecipeId)
        }

        let ownedCopies = try await recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeId],
            ownerId: currentUserId
        )
        if let ownedCopy = ownedCopies.first {
            return .saved(materializedRecipeId: ownedCopy.id)
        }

        return .notSaved
    }

    func collectionRelation(
        for collection: Collection,
        currentUserId: UUID?
    ) async throws -> CollectionLibraryRelation {
        guard let currentUserId else {
            return .notSaved
        }

        if collection.userId == currentUserId {
            return .owned
        }

        let sourceCollectionId = collection.sourceCollectionReferenceId
        if let reference = try await savedReferenceRepository.collectionReference(
            userId: currentUserId,
            sourceCollectionId: sourceCollectionId
        ) {
            return .saved(referenceId: reference.id)
        }

        return .notSaved
    }
}
