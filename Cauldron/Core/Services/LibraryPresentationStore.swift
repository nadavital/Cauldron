//
//  LibraryPresentationStore.swift
//  Cauldron
//

import Foundation

struct RecipePresentationSnapshot: Sendable {
    let recipe: Recipe
    let sharedBy: User?
    let sharedAt: Date?
    let relation: RecipeLibraryRelation
    let updatedAt: Date
}

struct CollectionPresentationSnapshot: Sendable {
    let collection: Collection
    let owner: User?
    let recipes: [Recipe]
    let recipeImages: [URL?]
    let recipeImageSources: [CollectionRecipeImageSource]
    let relation: CollectionLibraryRelation
    let savedCollection: Collection?
    let updatedAt: Date
}

final class LibraryPresentationStore: @unchecked Sendable {
    private var recipeSnapshots: [UUID: RecipePresentationSnapshot] = [:]
    private var recipeRelations: [UUID: RecipeLibraryRelation] = [:]
    private var collectionSnapshots: [UUID: CollectionPresentationSnapshot] = [:]
    private var collectionRelations: [UUID: CollectionLibraryRelation] = [:]
    private let lock = NSLock()

    func recipeSnapshot(for recipe: Recipe) -> RecipePresentationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return recipeSnapshots[recipe.id]
    }

    func seedRecipe(
        _ recipe: Recipe,
        sharedBy: User? = nil,
        sharedAt: Date? = nil,
        relation: RecipeLibraryRelation? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let resolvedRelation = relation
            ?? recipeRelationLocked(for: recipe)
            ?? RecipeLibraryRelation.unknown
        let snapshot = RecipePresentationSnapshot(
            recipe: recipe,
            sharedBy: sharedBy,
            sharedAt: sharedAt,
            relation: resolvedRelation,
            updatedAt: Date()
        )
        recipeSnapshots[recipe.id] = snapshot
        for key in recipeKeys(for: recipe, relation: resolvedRelation) {
            recipeRelations[key] = resolvedRelation
        }
    }

    func recipeRelation(for recipe: Recipe) -> RecipeLibraryRelation? {
        lock.lock()
        defer { lock.unlock() }
        return recipeRelationLocked(for: recipe)
    }

    func updateRecipeRelation(_ relation: RecipeLibraryRelation, for recipe: Recipe) {
        lock.lock()
        defer { lock.unlock() }

        let relationKeys = recipeKeys(for: recipe, relation: relation)
        for key in relationKeys {
            recipeRelations[key] = relation
        }
        for key in relationKeys {
            guard let snapshot = recipeSnapshots[key] else { continue }
            let updated = RecipePresentationSnapshot(
                recipe: snapshot.recipe,
                sharedBy: snapshot.sharedBy,
                sharedAt: snapshot.sharedAt,
                relation: relation,
                updatedAt: Date()
            )
            recipeSnapshots[key] = updated
        }
    }

    func collectionSnapshot(for collection: Collection) -> CollectionPresentationSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return collectionSnapshots[collection.id]
    }

    func seedCollection(
        _ collection: Collection,
        owner: User? = nil,
        recipes: [Recipe] = [],
        recipeImages: [URL?] = [],
        recipeImageSources: [CollectionRecipeImageSource] = [],
        relation: CollectionLibraryRelation? = nil,
        savedCollection: Collection? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let resolvedRelation = relation
            ?? collectionRelationLocked(for: collection)
            ?? CollectionLibraryRelation.unknown
        let resolvedSavedCollection = savedCollection
            ?? (resolvedRelation.isSavedOrOwned ? collection : nil)
        let snapshot = CollectionPresentationSnapshot(
            collection: collection,
            owner: owner,
            recipes: recipes,
            recipeImages: recipeImages,
            recipeImageSources: recipeImageSources,
            relation: resolvedRelation,
            savedCollection: resolvedSavedCollection,
            updatedAt: Date()
        )
        collectionSnapshots[collection.id] = snapshot
        for key in collectionKeys(for: collection, relation: resolvedRelation) {
            collectionRelations[key] = resolvedRelation
        }
    }

    func collectionRelation(for collection: Collection) -> CollectionLibraryRelation? {
        lock.lock()
        defer { lock.unlock() }
        return collectionRelationLocked(for: collection)
    }

    func updateCollectionRelation(
        _ relation: CollectionLibraryRelation,
        for collection: Collection,
        savedCollection: Collection? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }

        let relationKeys = collectionKeys(for: collection, relation: relation)
        for key in relationKeys {
            collectionRelations[key] = relation
        }
        for key in relationKeys {
            guard let snapshot = collectionSnapshots[key] else { continue }
            let updated = CollectionPresentationSnapshot(
                collection: snapshot.collection,
                owner: snapshot.owner,
                recipes: snapshot.recipes,
                recipeImages: snapshot.recipeImages,
                recipeImageSources: snapshot.recipeImageSources,
                relation: relation,
                savedCollection: savedCollection ?? (relation.isSavedOrOwned ? snapshot.collection : nil),
                updatedAt: Date()
            )
            collectionSnapshots[key] = updated
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        recipeSnapshots.removeAll()
        recipeRelations.removeAll()
        collectionSnapshots.removeAll()
        collectionRelations.removeAll()
    }

    private nonisolated func recipeKeys(for recipe: Recipe) -> [UUID] {
        orderedKeys(recipe.id, recipe.relatedGraphReferenceID)
    }

    private func recipeRelationLocked(for recipe: Recipe) -> RecipeLibraryRelation? {
        if let exactRelation = recipeRelations[recipe.id] {
            return exactRelation
        }

        guard recipe.relatedGraphReferenceID != recipe.id,
              let aliasedRelation = recipeRelations[recipe.relatedGraphReferenceID],
              case .saved = aliasedRelation else {
            return nil
        }
        return aliasedRelation
    }

    private nonisolated func recipeKeys(for recipe: Recipe, relation: RecipeLibraryRelation) -> [UUID] {
        switch relation {
        case .saved:
            return recipeKeys(for: recipe)
        case .unknown, .notSaved, .owned:
            return [recipe.id]
        }
    }

    private nonisolated func collectionKeys(for collection: Collection) -> [UUID] {
        orderedKeys(collection.id, collection.sourceCollectionReferenceId)
    }

    private func collectionRelationLocked(for collection: Collection) -> CollectionLibraryRelation? {
        if let exactRelation = collectionRelations[collection.id] {
            return exactRelation
        }

        guard collection.sourceCollectionReferenceId != collection.id,
              let aliasedRelation = collectionRelations[collection.sourceCollectionReferenceId],
              case .saved = aliasedRelation else {
            return nil
        }
        return aliasedRelation
    }

    private nonisolated func collectionKeys(for collection: Collection, relation: CollectionLibraryRelation) -> [UUID] {
        switch relation {
        case .saved:
            return collectionKeys(for: collection)
        case .unknown, .notSaved, .owned:
            return [collection.id]
        }
    }

    private nonisolated func orderedKeys(_ primary: UUID, _ secondary: UUID) -> [UUID] {
        primary == secondary ? [primary] : [primary, secondary]
    }
}
