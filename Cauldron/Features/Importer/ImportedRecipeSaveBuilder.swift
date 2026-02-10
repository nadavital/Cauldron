//
//  ImportedRecipeSaveBuilder.swift
//  Cauldron
//
//  Shared transformation logic for imported recipes before saving.
//

import Foundation

enum ImportedRecipeSaveBuilder {
    static func recipeForSave(from recipe: Recipe, userId: UUID?) -> Recipe {
        let resolvedOwnerId = userId ?? recipe.ownerId
        let resolvedNotes = buildNotes(for: recipe)

        return Recipe(
            id: recipe.id,
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: recipe.yields,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags,
            nutrition: recipe.nutrition,
            sourceURL: recipe.sourceURL,
            sourceTitle: recipe.sourceTitle,
            notes: resolvedNotes,
            imageURL: recipe.imageURL,
            isFavorite: recipe.isFavorite,
            visibility: recipe.visibility,
            ownerId: resolvedOwnerId,
            cloudRecordName: recipe.cloudRecordName,
            cloudImageRecordName: recipe.cloudImageRecordName,
            imageModifiedAt: recipe.imageModifiedAt,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt,
            originalRecipeId: recipe.originalRecipeId,
            originalCreatorId: recipe.originalCreatorId,
            originalCreatorName: recipe.originalCreatorName,
            savedAt: recipe.savedAt,
            relatedRecipeIds: recipe.relatedRecipeIds,
            isPreview: recipe.isPreview
        )
    }

    private static func buildNotes(for recipe: Recipe) -> String? {
        guard let sourceURL = recipe.sourceURL else {
            return recipe.notes
        }

        let sourceLine = "Source: \(sourceURL.absoluteString)"

        if let existingNotes = recipe.notes,
           existingNotes.localizedCaseInsensitiveContains(sourceLine) {
            return existingNotes
        }

        if let existingNotes = recipe.notes,
           !existingNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existingNotes + "\n\n" + sourceLine
        }

        return sourceLine
    }

    static func recipeForSave(
        from recipe: Recipe,
        userId: UUID?,
        imageManager: RecipeImageManager
    ) async -> Recipe {
        var recipeToSave = recipeForSave(from: recipe, userId: userId)

        guard let imageURL = recipeToSave.imageURL else {
            return recipeToSave
        }

        guard !imageURL.isFileURL else {
            return recipeToSave
        }

        do {
            let filename = try await imageManager.downloadAndSaveImage(from: imageURL, recipeId: recipeToSave.id)
            let localImageURL = await imageManager.imageURL(for: filename)
            recipeToSave = recipeToSave.withImageURL(localImageURL)
        } catch {
            // Persist without image if we can't reliably localize it.
            recipeToSave = recipeToSave.withImageURL(nil)
        }

        return recipeToSave
    }
}
