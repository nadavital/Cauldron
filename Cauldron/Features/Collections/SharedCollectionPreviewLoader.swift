//
//  SharedCollectionPreviewLoader.swift
//  Cauldron
//
//  Batched preview-image loading for shared collection cards.
//

import Foundation

enum SharedCollectionPreviewLoader {
    static func loadPreviewImageURLs(
        for collection: Collection,
        dependencies: DependencyContainer,
        imageLimit: Int = 4,
        recipeScanLimit: Int = 12
    ) async -> [URL?] {
        let candidateRecipeIds = Array(collection.recipeIds.prefix(max(imageLimit, recipeScanLimit)))
        guard !candidateRecipeIds.isEmpty else { return [] }

        do {
            let recipesById = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(ids: candidateRecipeIds)
            var previewURLs: [URL?] = []
            previewURLs.reserveCapacity(imageLimit)

            for recipeId in candidateRecipeIds {
                guard let recipe = recipesById[recipeId],
                      recipe.imageURL != nil || recipe.cloudImageRecordName != nil else {
                    continue
                }

                if let localURL = await resolveLocalImageURL(for: recipe, dependencies: dependencies) {
                    previewURLs.append(localURL)
                }

                if previewURLs.count == imageLimit {
                    break
                }
            }

            return previewURLs
        } catch {
            AppLogger.general.warning("Failed to load shared collection previews for \(collection.id.uuidString): \(error.localizedDescription)")
            return []
        }
    }

    private static func resolveLocalImageURL(
        for recipe: Recipe,
        dependencies: DependencyContainer
    ) async -> URL? {
        let localURL = await dependencies.imageManager.imageURL(recipeId: recipe.id)
        if await dependencies.imageManager.imageExists(entityId: recipe.id) {
            return localURL
        }

        if let recipeImageURL = recipe.imageURL, recipeImageURL.isFileURL {
            return recipeImageURL
        }

        guard recipe.cloudImageRecordName != nil else {
            return nil
        }

        do {
            if let filename = try await dependencies.imageManager.downloadImageFromCloud(
                recipeId: recipe.id,
                fromPublic: true
            ) {
                return await dependencies.imageManager.imageURL(for: filename)
            }
        } catch {
            AppLogger.general.warning("Failed to download shared collection preview image for recipe \(recipe.id.uuidString): \(error.localizedDescription)")
        }

        return nil
    }
}
