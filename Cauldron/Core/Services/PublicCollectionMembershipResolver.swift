//
//  PublicCollectionMembershipResolver.swift
//  Cauldron
//

import Foundation
import os

struct PublicCollectionMembershipRepairPlan: Sendable, Equatable {
    let privateOwnedRecipeCount: Int
    let referencedRecipeCount: Int

    var requiresRepair: Bool {
        privateOwnedRecipeCount > 0 || referencedRecipeCount > 0
    }

    var confirmationMessage: String {
        var actions: [String] = []

        if privateOwnedRecipeCount > 0 {
            let recipeText = privateOwnedRecipeCount == 1 ? "recipe" : "recipes"
            actions.append("make \(privateOwnedRecipeCount) private \(recipeText) public")
        }

        if referencedRecipeCount > 0 {
            let recipeText = referencedRecipeCount == 1 ? "referenced recipe" : "referenced recipes"
            actions.append("save \(referencedRecipeCount) \(recipeText) as your own public copies")
        }

        guard !actions.isEmpty else {
            return "This public collection can be saved without changing recipe visibility."
        }

        return "This public collection needs to \(actions.joined(separator: " and ")) so everyone sees the same recipes."
    }
}

struct PublicCollectionMembershipResolution: Sendable, Equatable {
    let recipeIds: [UUID]
    let publishedRecipeCount: Int
    let copiedRecipeCount: Int

    let changedRecipeIds: Bool
}

enum PublicCollectionMembershipResolverError: LocalizedError {
    case notCollectionOwner

    var errorDescription: String? {
        switch self {
        case .notCollectionOwner:
            return "You can only repair sharing for your own collections."
        }
    }
}

actor PublicCollectionMembershipResolver {
    private let recipeRepository: RecipeRepository
    private let recipeSaveService: RecipeSaveService
    private let logger = Logger(subsystem: "com.cauldron", category: "PublicCollectionMembershipResolver")

    init(
        recipeRepository: RecipeRepository,
        recipeSaveService: RecipeSaveService
    ) {
        self.recipeRepository = recipeRepository
        self.recipeSaveService = recipeSaveService
    }

    func repairPlan(
        recipeIds: [UUID],
        ownerId: UUID,
        visibility: RecipeVisibility
    ) async throws -> PublicCollectionMembershipRepairPlan {
        guard visibility == .publicRecipe, !recipeIds.isEmpty else {
            return PublicCollectionMembershipRepairPlan(privateOwnedRecipeCount: 0, referencedRecipeCount: 0)
        }

        try await assertCurrentUserOwnsCollection(ownerId: ownerId)

        let recipesById = try await localRecipesById(recipeIds)
        var privateOwnedRecipeCount = 0
        var referencedRecipeCount = 0

        for recipeId in recipeIds {
            guard let recipe = recipesById[recipeId] else {
                continue
            }

            if !recipe.meetsMinimumVisibility(for: visibility) {
                if recipe.ownerId != ownerId {
                    referencedRecipeCount += 1
                } else {
                    privateOwnedRecipeCount += 1
                }
            }
        }

        return PublicCollectionMembershipRepairPlan(
            privateOwnedRecipeCount: privateOwnedRecipeCount,
            referencedRecipeCount: referencedRecipeCount
        )
    }

    func resolveRecipeIdsForOwnedPublicCollection(
        recipeIds: [UUID],
        ownerId: UUID,
        visibility: RecipeVisibility
    ) async throws -> PublicCollectionMembershipResolution {
        guard visibility == .publicRecipe, !recipeIds.isEmpty else {
            return PublicCollectionMembershipResolution(
                recipeIds: recipeIds,
                publishedRecipeCount: 0,
                copiedRecipeCount: 0,
                changedRecipeIds: false
            )
        }

        try await assertCurrentUserOwnsCollection(ownerId: ownerId)

        let recipesById = try await localRecipesById(recipeIds)
        var resolvedRecipeIds: [UUID] = []
        var seenRecipeIds = Set<UUID>()
        let copiedRecipeCount = 0
        var publishedRecipeCount = 0

        for recipeId in recipeIds {
            guard let recipe = recipesById[recipeId] else {
                appendUnique(recipeId, to: &resolvedRecipeIds, seenRecipeIds: &seenRecipeIds)
                continue
            }

            if !recipe.meetsMinimumVisibility(for: visibility), recipe.ownerId == ownerId {
                try await recipeRepository.updateVisibility(id: recipe.id, visibility: .publicRecipe)
                publishedRecipeCount += 1
            }
            appendUnique(recipe.id, to: &resolvedRecipeIds, seenRecipeIds: &seenRecipeIds)
        }

        let changedRecipeIds = resolvedRecipeIds != recipeIds
        logger.info("Resolved public collection membership: \(publishedRecipeCount) published, \(copiedRecipeCount) copied, changed IDs: \(changedRecipeIds)")
        return PublicCollectionMembershipResolution(
            recipeIds: resolvedRecipeIds,
            publishedRecipeCount: publishedRecipeCount,
            copiedRecipeCount: copiedRecipeCount,
            changedRecipeIds: changedRecipeIds
        )
    }

    private func assertCurrentUserOwnsCollection(ownerId: UUID) async throws {
        let currentUserId = await MainActor.run { CurrentUserSession.shared.userId }
        guard currentUserId == ownerId else {
            throw PublicCollectionMembershipResolverError.notCollectionOwner
        }
    }

    private func localRecipesById(_ recipeIds: [UUID]) async throws -> [UUID: Recipe] {
        let recipes = try await recipeRepository.fetch(ids: Array(Set(recipeIds)))
        return RecipeDeduplication.byIdPreferringBest(recipes)
    }

    private func appendUnique(
        _ recipeId: UUID,
        to recipeIds: inout [UUID],
        seenRecipeIds: inout Set<UUID>
    ) {
        guard seenRecipeIds.insert(recipeId).inserted else {
            return
        }
        recipeIds.append(recipeId)
    }
}
