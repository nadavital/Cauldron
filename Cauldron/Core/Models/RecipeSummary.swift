//
//  RecipeSummary.swift
//  Cauldron
//

import Foundation

/// Lightweight public recipe payload for browsing surfaces.
///
/// Summary records intentionally exclude full instructions and nutrition so
/// list/card queries can scale separately from detail fetches.
struct RecipeSummary: Sendable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let ingredients: [Ingredient]
    let yields: String
    let totalMinutes: Int?
    let tags: [Tag]
    let visibility: RecipeVisibility
    let ownerId: UUID?
    let cloudRecordName: String?
    let cloudImageRecordName: String?
    let imageModifiedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let originalRecipeId: UUID?
    let originalCreatorId: UUID?
    let originalCreatorName: String?
    let savedAt: Date?
    let sourceRecipeUpdatedAt: Date?
    let followsSourceUpdates: Bool
    let relatedRecipeIds: [UUID]
    let isPreview: Bool

    nonisolated var isFollowingSourceUpdates: Bool {
        Recipe.resolvedFollowsSourceUpdates(
            originalRecipeId: originalRecipeId,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            followsSourceUpdates: followsSourceUpdates
        )
    }

    nonisolated var previewRecipe: Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: ingredients,
            steps: [],
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            followsSourceUpdates: followsSourceUpdates,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
}

extension RecipeSummary: Codable {}
