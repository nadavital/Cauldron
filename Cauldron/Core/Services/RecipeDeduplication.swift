//
//  RecipeDeduplication.swift
//  Cauldron
//

import Foundation

enum RecipeDeduplication {
    nonisolated static func byIdPreferringBest(_ recipes: [Recipe]) -> [UUID: Recipe] {
        recipes.reduce(into: [UUID: Recipe]()) { partialResult, recipe in
            guard let existing = partialResult[recipe.id] else {
                partialResult[recipe.id] = recipe
                return
            }

            if shouldPrefer(recipe, over: existing) {
                partialResult[recipe.id] = recipe
            }
        }
    }

    private nonisolated static func shouldPrefer(_ candidate: Recipe, over existing: Recipe) -> Bool {
        if existing.isPreview != candidate.isPreview {
            return !candidate.isPreview
        }
        if (existing.ownerId == nil) != (candidate.ownerId == nil) {
            return candidate.ownerId != nil
        }
        if (existing.cloudRecordName == nil) != (candidate.cloudRecordName == nil) {
            return candidate.cloudRecordName != nil
        }
        if (existing.cloudImageRecordName == nil) != (candidate.cloudImageRecordName == nil) {
            return candidate.cloudImageRecordName != nil
        }
        if (existing.imageURL == nil) != (candidate.imageURL == nil) {
            return candidate.imageURL != nil
        }
        return candidate.updatedAt > existing.updatedAt
    }
}
