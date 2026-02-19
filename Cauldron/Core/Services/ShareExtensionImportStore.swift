//
//  ShareExtensionImportStore.swift
//  Cauldron
//
//  App Group storage for pending recipe URLs sent from Share Extension.
//

import Foundation

enum ShareExtensionImportStore {
    static func pendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: ShareExtensionImportContract.appGroupID),
              let urlString = defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey) else {
            return nil
        }
        return URL(string: urlString)
    }

    static func consumePendingRecipeURL() -> URL? {
        guard let defaults = UserDefaults(suiteName: ShareExtensionImportContract.appGroupID),
              let url = pendingRecipeURL() else {
            return nil
        }

        defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        return url
    }

    static func consumePreparedRecipe() -> PreparedSharedRecipe? {
        guard let defaults = UserDefaults(suiteName: ShareExtensionImportContract.appGroupID),
              let payloadData = defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey) else {
            return nil
        }

        guard let preparedRecipe = preparedRecipe(from: payloadData) else {
            defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
            return nil
        }

        defaults.removeObject(forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
        // Prepared payload supersedes a plain pending URL.
        defaults.removeObject(forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        return preparedRecipe
    }

    static func preparedRecipe(from payloadData: Data) -> PreparedSharedRecipe? {
        do {
            let payload = try JSONDecoder().decode(PreparedShareRecipePayload.self, from: payloadData)
            return payload.toPreparedRecipe()
        } catch {
            AppLogger.general.error("❌ Failed to decode prepared share payload: \(error.localizedDescription)")
            return nil
        }
    }
}

struct PreparedSharedRecipe {
    let recipe: Recipe
    let sourceInfo: String
}

extension PreparedSharedRecipe {
    func recipeParserInputText() -> String {
        recipe.recipeParserInputText()
    }

    func recipeMergedWithParsedContent(_ parsedRecipe: Recipe) -> Recipe {
        recipe.mergedWithParsedContent(parsedRecipe)
    }
}

extension Recipe {
    fileprivate func recipeParserInputText() -> String {
        var lines: [String] = [title]

        if let yields = yields.nonEmpty {
            lines.append("Servings: \(yields)")
        }

        if let totalMinutes {
            lines.append("Total Time: \(totalMinutes) minutes")
        }

        lines.append("")
        lines.append("Ingredients:")
        lines.append(contentsOf: parserInputIngredientLines())

        lines.append("")
        lines.append("Instructions:")
        lines.append(contentsOf: parserInputStepLines())

        if let notes = notes?.nonEmpty {
            lines.append("")
            lines.append("Notes:")
            lines.append(
                contentsOf: notes
                    .components(separatedBy: .newlines)
                    .map(\.trimmed)
                    .filter { !$0.isEmpty }
            )
        }

        return lines.joined(separator: "\n")
    }

    fileprivate func mergedWithParsedContent(_ parsed: Recipe) -> Recipe {
        let mergedTitle = parsed.title.nonEmpty ?? title
        let mergedYields = parsed.yields.nonEmpty ?? yields
        let mergedNotes = parsed.notes?.nonEmpty ?? notes?.nonEmpty

        return Recipe(
            id: id,
            title: mergedTitle,
            ingredients: parsed.ingredients,
            steps: parsed.steps,
            yields: mergedYields,
            totalMinutes: parsed.totalMinutes ?? totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL ?? parsed.sourceURL,
            sourceTitle: sourceTitle ?? parsed.sourceTitle,
            notes: mergedNotes,
            imageURL: imageURL ?? parsed.imageURL,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }

    private func parserInputIngredientLines() -> [String] {
        var lines: [String] = []
        var currentSection: String?

        for ingredient in ingredients {
            let section = ingredient.section?.nonEmpty
            if section != currentSection {
                currentSection = section
                if let section {
                    lines.append("\(section):")
                }
            }
            lines.append(ingredient.displayString)
        }

        return lines
    }

    private func parserInputStepLines() -> [String] {
        var lines: [String] = []
        var currentSection: String?

        for step in steps.sorted(by: { $0.index < $1.index }) {
            let section = step.section?.nonEmpty
            if section != currentSection {
                currentSection = section
                if let section {
                    lines.append("\(section):")
                }
            }

            lines.append("\(step.index + 1). \(step.text.trimmed)")
        }

        return lines
    }
}

extension PreparedShareRecipePayload {
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
