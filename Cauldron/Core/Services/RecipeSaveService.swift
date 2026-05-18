//
//  RecipeSaveService.swift
//  Cauldron
//

import Foundation
import UIKit
import os

struct RecipeSaveResult: Sendable, Equatable {
    let recipe: Recipe
    let savedReference: SavedRecipeReference?
    let savedRelatedRecipeCount: Int
    let reusedExistingCopy: Bool
}

actor RecipeSaveService {
    private let recipeRepository: RecipeRepository
    private let savedReferenceRepository: SavedReferenceRepository
    private let recipeCloudService: RecipeCloudService
    private let recipeDiscoveryCache: RecipeDiscoveryCache
    private let imageManager: RecipeImageManager
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeSaveService")

    init(
        recipeRepository: RecipeRepository,
        savedReferenceRepository: SavedReferenceRepository,
        recipeCloudService: RecipeCloudService,
        recipeDiscoveryCache: RecipeDiscoveryCache,
        imageManager: RecipeImageManager
    ) {
        self.recipeRepository = recipeRepository
        self.savedReferenceRepository = savedReferenceRepository
        self.recipeCloudService = recipeCloudService
        self.recipeDiscoveryCache = recipeDiscoveryCache
        self.imageManager = imageManager
    }

    func missingRelatedRecipesForSave(_ recipe: Recipe) async throws -> [Recipe] {
        let canonicalRelatedRecipeIDs = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: recipe)
        guard !canonicalRelatedRecipeIDs.isEmpty else {
            return []
        }

        let localResolution = try await recipeRepository.resolveLocalRelatedRecipes(
            referenceIds: canonicalRelatedRecipeIDs,
            includePreviews: false
        )
        let missingIds = Set(localResolution.missingIds)
        guard !missingIds.isEmpty else {
            return []
        }

        let fetchedRelatedById = try await recipeDiscoveryCache.fetchPublicRecipes(ids: Array(missingIds))
        return canonicalRelatedRecipeIDs.compactMap { fetchedRelatedById[$0] }
    }

    func saveRecipeToLibrary(
        _ recipe: Recipe,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil,
        relatedRecipesToSave: [Recipe] = [],
        minimumVisibility: RecipeVisibility? = nil
    ) async throws -> RecipeSaveResult {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw RecipeSaveServiceError.notAuthenticated
        }

        if recipe.ownerId == userId, !recipe.isPreview {
            let resolvedRecipe = try await recipeWithMinimumVisibility(
                recipe,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
            return RecipeSaveResult(
                recipe: resolvedRecipe,
                savedReference: nil,
                savedRelatedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let sourceRecipeID = recipe.relatedGraphReferenceID

        if let existingReference = try await savedReferenceRepository.recipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeID
        ) {
            if let materializedRecipeId = existingReference.materializedRecipeId,
               let materializedRecipe = try await recipeRepository.fetch(id: materializedRecipeId) {
                return RecipeSaveResult(
                    recipe: materializedRecipe,
                    savedReference: existingReference,
                    savedRelatedRecipeCount: 0,
                    reusedExistingCopy: true
                )
            }

            return RecipeSaveResult(
                recipe: recipe,
                savedReference: existingReference,
                savedRelatedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        if let existingLocalRecipe = try await recipeRepository.fetch(id: recipe.id),
           existingLocalRecipe.ownerId == userId,
           !existingLocalRecipe.isPreview {
            let resolvedRecipe = try await recipeWithMinimumVisibility(
                existingLocalRecipe,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
            return RecipeSaveResult(
                recipe: resolvedRecipe,
                savedReference: nil,
                savedRelatedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let existingOwnedCopies = try await recipeRepository.fetchOwnedCopies(originalRecipeIds: [sourceRecipeID])
        if let existingOwnedCopy = existingOwnedCopies.first {
            let referenceResult = try await savedReferenceRepository.saveRecipeReference(
                sourceRecipe: recipe,
                userId: userId,
                originalCreatorName: originalCreatorName,
                materializedRecipeId: existingOwnedCopy.id
            )
            let resolvedRecipe = try await recipeWithMinimumVisibility(
                existingOwnedCopy,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
            return RecipeSaveResult(
                recipe: resolvedRecipe,
                savedReference: referenceResult.reference,
                savedRelatedRecipeCount: 0,
                reusedExistingCopy: true
            )
        }

        let savedRelatedRecipeCount = try await saveRelatedRecipeReferences(
            relatedRecipesToSave,
            userId: userId
        )
        let referenceResult = try await savedReferenceRepository.saveRecipeReference(
            sourceRecipe: recipe,
            userId: userId,
            originalCreatorName: originalCreatorName
        )

        NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)
        return RecipeSaveResult(
            recipe: recipe,
            savedReference: referenceResult.reference,
            savedRelatedRecipeCount: savedRelatedRecipeCount,
            reusedExistingCopy: referenceResult.reusedExistingReference
        )
    }

    func materializeSavedRecipeForEditing(
        _ recipe: Recipe,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil,
        minimumVisibility: RecipeVisibility? = nil
    ) async throws -> Recipe {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw RecipeSaveServiceError.notAuthenticated
        }

        if recipe.ownerId == userId, !recipe.isPreview {
            return try await recipeWithMinimumVisibility(
                recipe,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
        }

        let sourceRecipeID = recipe.relatedGraphReferenceID
        if let existingReference = try await savedReferenceRepository.recipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeID
        ), let materializedRecipeId = existingReference.materializedRecipeId,
           let materializedRecipe = try await recipeRepository.fetch(id: materializedRecipeId) {
            return try await recipeWithMinimumVisibility(
                materializedRecipe,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
        }

        let existingOwnedCopies = try await recipeRepository.fetchOwnedCopies(originalRecipeIds: [sourceRecipeID])
        if let existingOwnedCopy = existingOwnedCopies.first {
            _ = try await savedReferenceRepository.saveRecipeReference(
                sourceRecipe: recipe,
                userId: userId,
                originalCreatorName: originalCreatorName,
                materializedRecipeId: existingOwnedCopy.id
            )
            return try await recipeWithMinimumVisibility(
                existingOwnedCopy,
                userId: userId,
                minimumVisibility: minimumVisibility
            )
        }

        let canonicalRelatedRecipeIDs = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: recipe)
        let copiedRecipe = try await copyRecipeToOwner(
            recipe,
            userId: userId,
            originalCreatorId: originalCreatorId ?? recipe.ownerId,
            originalCreatorName: originalCreatorName,
            canonicalRelatedRecipeIDs: canonicalRelatedRecipeIDs,
            relatedRecipeIdMapping: [:]
        )

        _ = try await savedReferenceRepository.saveRecipeReference(
            sourceRecipe: recipe,
            userId: userId,
            originalCreatorName: originalCreatorName,
            materializedRecipeId: copiedRecipe.id
        )
        return try await recipeWithMinimumVisibility(
            copiedRecipe,
            userId: userId,
            minimumVisibility: minimumVisibility
        )
    }

    func materializeRecipeForOwnedCollectionMembership(
        _ recipe: Recipe,
        minimumVisibility: RecipeVisibility,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil
    ) async throws -> Recipe {
        try await materializeSavedRecipeForEditing(
            recipe,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            minimumVisibility: minimumVisibility
        )
    }

    private func saveRelatedRecipeReferences(
        _ relatedRecipes: [Recipe],
        userId: UUID
    ) async throws -> Int {
        var savedCount = 0

        for relatedRecipe in relatedRecipes {
            if relatedRecipe.ownerId == userId && !relatedRecipe.isPreview {
                continue
            }

            let result = try await savedReferenceRepository.saveRecipeReference(
                sourceRecipe: relatedRecipe,
                userId: userId,
                originalCreatorName: relatedRecipe.originalCreatorName
            )
            if !result.reusedExistingReference { savedCount += 1 }
        }

        return savedCount
    }

    private func recipeWithMinimumVisibility(
        _ recipe: Recipe,
        userId: UUID,
        minimumVisibility: RecipeVisibility?
    ) async throws -> Recipe {
        guard let minimumVisibility,
              !recipe.meetsMinimumVisibility(for: minimumVisibility),
              recipe.ownerId == userId else {
            return recipe
        }

        try await recipeRepository.updateVisibility(id: recipe.id, visibility: minimumVisibility)
        return try await recipeRepository.fetch(id: recipe.id) ?? recipe
    }

    private func convertPreviewToOwnedRecipe(
        _ preview: Recipe,
        sourceRecipe: Recipe,
        userId: UUID,
        originalCreatorId: UUID?,
        originalCreatorName: String?,
        canonicalRelatedRecipeIDs: [UUID],
        relatedRecipeIdMapping: [UUID: UUID]
    ) async throws -> Recipe {
        try await recipeRepository.delete(id: preview.id)

        let originalRecipeId = preview.originalRecipeId ?? preview.id
        let remappedRelatedIds = canonicalRelatedRecipeIDs.map { originalId in
            relatedRecipeIdMapping[originalId] ?? originalId
        }

        var copiedRecipe = Recipe(
            id: UUID(),
            title: preview.title,
            ingredients: preview.ingredients,
            steps: preview.steps,
            yields: preview.yields,
            totalMinutes: preview.totalMinutes,
            tags: preview.tags,
            nutrition: preview.nutrition,
            sourceURL: preview.sourceURL,
            sourceTitle: preview.sourceTitle,
            notes: preview.notes,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: userId,
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: preview.originalCreatorId ?? originalCreatorId ?? sourceRecipe.ownerId,
            originalCreatorName: preview.originalCreatorName ?? originalCreatorName,
            savedAt: Date(),
            sourceRecipeUpdatedAt: preview.sourceRecipeUpdatedAt ?? sourceRecipe.updatedAt,
            followsSourceUpdates: true,
            relatedRecipeIds: remappedRelatedIds,
            isPreview: false
        )

        try await recipeRepository.create(copiedRecipe)
        copiedRecipe = try await localizePublicImageIfNeeded(
            from: preview,
            sourceImageRecipeID: originalRecipeId,
            into: copiedRecipe
        )

        logger.info("Converted preview to owned recipe: \(copiedRecipe.title)")
        return copiedRecipe
    }

    private func copyRecipeToOwner(
        _ recipe: Recipe,
        userId: UUID,
        originalCreatorId: UUID?,
        originalCreatorName: String?,
        canonicalRelatedRecipeIDs: [UUID],
        relatedRecipeIdMapping: [UUID: UUID]
    ) async throws -> Recipe {
        let sourceImageRecipeID = recipe.sourceAssetReferenceID
        let remappedRelatedIds = canonicalRelatedRecipeIDs.map { originalId in
            relatedRecipeIdMapping[originalId] ?? originalId
        }

        var copiedRecipe = recipe.withOwner(
            userId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            visibility: .publicRecipe,
            relatedRecipeIds: remappedRelatedIds
        ).withCloudImageMetadata(recordName: nil, modifiedAt: nil)

        try await recipeRepository.create(copiedRecipe)
        copiedRecipe = try await localizePublicImageIfNeeded(
            from: recipe,
            sourceImageRecipeID: sourceImageRecipeID,
            into: copiedRecipe
        )

        logger.info("Saved recipe to library: \(copiedRecipe.title)")
        return copiedRecipe
    }

    private func localizePublicImageIfNeeded(
        from sourceRecipe: Recipe,
        sourceImageRecipeID: UUID,
        into savedRecipe: Recipe
    ) async throws -> Recipe {
        guard savedRecipe.imageURL == nil else {
            return savedRecipe
        }

        guard sourceRecipe.cloudImageRecordName != nil || sourceImageRecipeID != sourceRecipe.id else {
            return savedRecipe
        }

        do {
            guard let imageData = try await recipeCloudService.downloadImageAsset(
                recipeId: sourceImageRecipeID,
                fromPublic: true
            ), let image = UIImage(data: imageData) else {
                return savedRecipe
            }

            let filename = try await imageManager.saveImage(image, recipeId: savedRecipe.id)
            let imageURL = await imageManager.imageURL(for: filename)
            let updatedRecipe = savedRecipe.withImageState(
                imageURL: imageURL,
                cloudImageRecordName: nil,
                imageModifiedAt: nil
            )
            try await recipeRepository.update(
                updatedRecipe,
                shouldUpdateTimestamp: false
            )
            return updatedRecipe
        } catch {
            logger.warning("Failed to localize image for saved recipe \(savedRecipe.id): \(error.localizedDescription)")
            return savedRecipe
        }
    }
}

enum RecipeSaveServiceError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You need to sign in before saving recipes"
        }
    }
}
