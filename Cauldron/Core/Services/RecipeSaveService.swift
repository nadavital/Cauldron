//
//  RecipeSaveService.swift
//  Cauldron
//

import Foundation
import UIKit
import os

struct RecipeSaveResult: Sendable, Equatable {
    let recipe: Recipe
    let savedRelatedRecipeCount: Int
    let reusedExistingCopy: Bool
}

actor RecipeSaveService {
    private let recipeRepository: RecipeRepository
    private let recipeCloudService: RecipeCloudService
    private let recipeDiscoveryCache: RecipeDiscoveryCache
    private let imageManager: RecipeImageManager
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeSaveService")

    init(
        recipeRepository: RecipeRepository,
        recipeCloudService: RecipeCloudService,
        recipeDiscoveryCache: RecipeDiscoveryCache,
        imageManager: RecipeImageManager
    ) {
        self.recipeRepository = recipeRepository
        self.recipeCloudService = recipeCloudService
        self.recipeDiscoveryCache = recipeDiscoveryCache
        self.imageManager = imageManager
    }

    func missingRelatedRecipesForSave(_ recipe: Recipe) async throws -> [Recipe] {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw RecipeSaveServiceError.notAuthenticated
        }

        let canonicalRelatedRecipeIDs = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: recipe)
        guard !canonicalRelatedRecipeIDs.isEmpty else {
            return []
        }

        let localResolution = try await recipeRepository.resolveLocalRelatedRecipes(
            referenceIds: canonicalRelatedRecipeIDs,
            includePreviews: false,
            preferredOwnerId: userId
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
        relatedRecipesToSave: [Recipe] = []
    ) async throws -> RecipeSaveResult {
        guard let userId = await MainActor.run(body: { CurrentUserSession.shared.userId }) else {
            throw RecipeSaveServiceError.notAuthenticated
        }

        if recipe.ownerId == userId {
            return RecipeSaveResult(recipe: recipe, savedRelatedRecipeCount: 0, reusedExistingCopy: true)
        }

        let sourceRecipeID = recipe.relatedGraphReferenceID
        let canonicalRelatedRecipeIDs = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: recipe)

        if let existingLocalRecipe = try await recipeRepository.fetch(id: recipe.id),
           !existingLocalRecipe.isPreview,
           existingLocalRecipe.ownerId == userId {
            return RecipeSaveResult(recipe: existingLocalRecipe, savedRelatedRecipeCount: 0, reusedExistingCopy: true)
        }

        let existingOwnedCopies = try await recipeRepository.fetchOwnedCopies(
            originalRecipeIds: [sourceRecipeID],
            ownerId: userId
        )
        if let existingOwnedCopy = existingOwnedCopies.first {
            return RecipeSaveResult(recipe: existingOwnedCopy, savedRelatedRecipeCount: 0, reusedExistingCopy: true)
        }

        let relatedSaveResult = try await saveRelatedRecipes(
            relatedRecipesToSave,
            userId: userId
        )
        let relatedRecipeIdMapping = relatedSaveResult.recipeIdMapping
        let savedRecipe: Recipe

        if let existingPreview = try await recipeRepository.fetch(id: recipe.id), existingPreview.isPreview {
            savedRecipe = try await convertPreviewToOwnedRecipe(
                existingPreview,
                sourceRecipe: recipe,
                userId: userId,
                originalCreatorId: originalCreatorId ?? recipe.ownerId,
                originalCreatorName: originalCreatorName,
                canonicalRelatedRecipeIDs: canonicalRelatedRecipeIDs,
                relatedRecipeIdMapping: relatedRecipeIdMapping
            )
        } else {
            savedRecipe = try await copyRecipeToOwner(
                recipe,
                userId: userId,
                originalCreatorId: originalCreatorId ?? recipe.ownerId,
                originalCreatorName: originalCreatorName,
                canonicalRelatedRecipeIDs: canonicalRelatedRecipeIDs,
                relatedRecipeIdMapping: relatedRecipeIdMapping
            )
        }

        NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)
        return RecipeSaveResult(
            recipe: savedRecipe,
            savedRelatedRecipeCount: relatedSaveResult.savedCount,
            reusedExistingCopy: false
        )
    }

    private func saveRelatedRecipes(
        _ relatedRecipes: [Recipe],
        userId: UUID
    ) async throws -> (recipeIdMapping: [UUID: UUID], savedCount: Int) {
        var relatedRecipeIdMapping: [UUID: UUID] = [:]
        var savedCount = 0

        for relatedRecipe in relatedRecipes {
            let relatedSourceRecipeId = relatedRecipe.relatedGraphReferenceID

            if relatedRecipe.ownerId == userId {
                relatedRecipeIdMapping[relatedSourceRecipeId] = relatedRecipe.id
                continue
            }

            if let localRelated = try await recipeRepository.fetch(id: relatedRecipe.id),
               !localRelated.isPreview,
               localRelated.ownerId == userId {
                relatedRecipeIdMapping[relatedSourceRecipeId] = localRelated.id
                continue
            }

            let existingRelatedCopies = try await recipeRepository.fetchOwnedCopies(
                originalRecipeIds: [relatedSourceRecipeId],
                ownerId: userId
            )
            if let existingRelatedCopy = existingRelatedCopies.first {
                relatedRecipeIdMapping[relatedSourceRecipeId] = existingRelatedCopy.id
                continue
            }

            let canonicalRelatedIDsForCopy = try await recipeCloudService.resolveCanonicalRelatedRecipeIDs(for: relatedRecipe)
            let relatedImageSourceRecipeID = relatedRecipe.sourceAssetReferenceID
            var copiedRelated = relatedRecipe.withOwner(
                userId,
                originalCreatorId: relatedRecipe.ownerId,
                originalCreatorName: relatedRecipe.originalCreatorName,
                visibility: .publicRecipe,
                relatedRecipeIds: canonicalRelatedIDsForCopy
            ).withCloudImageMetadata(recordName: nil, modifiedAt: nil)

            try await recipeRepository.create(copiedRelated)
            copiedRelated = try await localizePublicImageIfNeeded(
                from: relatedRecipe,
                sourceImageRecipeID: relatedImageSourceRecipeID,
                into: copiedRelated
            )

            relatedRecipeIdMapping[relatedSourceRecipeId] = copiedRelated.id
            savedCount += 1
        }

        return (relatedRecipeIdMapping, savedCount)
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

        let originalRecipeId = sourceRecipe.relatedGraphReferenceID
        let remappedRelatedIds = canonicalRelatedRecipeIDs.map { originalId in
            relatedRecipeIdMapping[originalId] ?? originalId
        }

        var copiedRecipe = Recipe(
            id: UUID(),
            title: sourceRecipe.title,
            ingredients: sourceRecipe.ingredients,
            steps: sourceRecipe.steps,
            yields: sourceRecipe.yields,
            totalMinutes: sourceRecipe.totalMinutes,
            tags: sourceRecipe.tags,
            nutrition: sourceRecipe.nutrition,
            sourceURL: sourceRecipe.sourceURL,
            sourceTitle: sourceRecipe.sourceTitle,
            notes: sourceRecipe.notes,
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
            sourceRecipeUpdatedAt: sourceRecipe.updatedAt,
            followsSourceUpdates: true,
            relatedRecipeIds: remappedRelatedIds,
            isPreview: false
        )

        try await recipeRepository.create(copiedRecipe)
        copiedRecipe = try await localizePublicImageIfNeeded(
            from: sourceRecipe,
            sourceImageRecipeID: sourceRecipe.sourceAssetReferenceID,
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
