//
//  ShareExtensionImportStore.swift
//  Cauldron
//
//  App Group storage for pending recipe URLs sent from Share Extension.
//

import Foundation

enum ShareExtensionImportStore {
    static let appGroupID = "group.Nadav.Cauldron"
    static let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    static let preparedRecipePayloadKey = "shareExtension.preparedRecipePayload"

    static func pendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let urlString = defaults.string(forKey: pendingRecipeURLKey) else {
            return nil
        }
        return URL(string: urlString)
    }

    static func consumePendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let url = pendingRecipeURL() else {
            return nil
        }

        defaults.removeObject(forKey: pendingRecipeURLKey)
        return url
    }

    static func consumePreparedRecipe() -> PreparedSharedRecipe? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let payloadData = defaults.data(forKey: preparedRecipePayloadKey) else {
            return nil
        }

        do {
            let payload = try JSONDecoder().decode(PreparedSharedRecipePayload.self, from: payloadData)
            guard let preparedRecipe = payload.toPreparedRecipe() else {
                defaults.removeObject(forKey: preparedRecipePayloadKey)
                return nil
            }

            defaults.removeObject(forKey: preparedRecipePayloadKey)
            // Prepared payload supersedes a plain pending URL.
            defaults.removeObject(forKey: pendingRecipeURLKey)
            return preparedRecipe
        } catch {
            AppLogger.general.error("❌ Failed to decode prepared share payload: \(error.localizedDescription)")
            defaults.removeObject(forKey: preparedRecipePayloadKey)
            return nil
        }
    }
}

struct PreparedSharedRecipe {
    let recipe: Recipe
    let sourceInfo: String
}

private struct PreparedSharedRecipePayload: Codable {
    let title: String
    let ingredients: [String]
    let steps: [String]
    let yields: String?
    let totalMinutes: Int?
    let sourceURL: String?
    let sourceTitle: String?
    let imageURL: String?

    func toPreparedRecipe() -> PreparedSharedRecipe? {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedIngredients = ingredients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedSteps = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedTitle.isEmpty,
              !cleanedIngredients.isEmpty,
              !cleanedSteps.isEmpty else {
            return nil
        }

        let parsedSourceURL = sourceURL.flatMap { URL(string: $0) }
        let parsedImageURL = imageURL.flatMap { URL(string: $0) }
        let ingredientModels = cleanedIngredients.map { Ingredient(name: $0) }
        let stepModels = cleanedSteps.enumerated().map { index, text in
            CookStep(index: index, text: text)
        }
        let resolvedYields: String = {
            guard let yields else { return "4 servings" }
            let cleaned = yields.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "4 servings" : cleaned
        }()

        let recipe = Recipe(
            title: cleanedTitle,
            ingredients: ingredientModels,
            steps: stepModels,
            yields: resolvedYields,
            totalMinutes: totalMinutes,
            sourceURL: parsedSourceURL,
            sourceTitle: sourceTitle,
            imageURL: parsedImageURL
        )

        let sourceInfo: String
        if let url = parsedSourceURL {
            sourceInfo = "Imported from \(url.absoluteString)"
        } else {
            sourceInfo = "Imported from shared webpage"
        }

        return PreparedSharedRecipe(recipe: recipe, sourceInfo: sourceInfo)
    }
}
