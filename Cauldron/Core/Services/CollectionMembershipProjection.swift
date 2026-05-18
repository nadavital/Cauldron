//
//  CollectionMembershipProjection.swift
//  Cauldron
//

import Foundation

enum CollectionMembershipProjection {
    nonisolated static func activeRecipeIds(from edges: [CollectionMembershipEdge]) -> [UUID] {
        let latestEdgesByRecipe = Dictionary(grouping: edges, by: \.recipeId)
            .compactMapValues { recipeEdges in
                recipeEdges.max { lhs, rhs in
                    lhs.updatedAt < rhs.updatedAt
                }
            }

        return latestEdgesByRecipe.values
            .filter { $0.status == .active }
            .sorted {
                if $0.sortOrder == $1.sortOrder {
                    return $0.updatedAt < $1.updatedAt
                }
                return $0.sortOrder < $1.sortOrder
            }
            .map(\.recipeId)
    }

    nonisolated static func collectionWithRecipeIds(_ collection: Collection, _ recipeIds: [UUID]) -> Collection {
        Collection(
            id: collection.id,
            name: collection.name,
            description: collection.description,
            userId: collection.userId,
            recipeIds: recipeIds,
            visibility: collection.visibility,
            emoji: collection.emoji,
            symbolName: collection.symbolName,
            color: collection.color,
            coverImageType: collection.coverImageType,
            coverImageURL: collection.coverImageURL,
            cloudCoverImageRecordName: collection.cloudCoverImageRecordName,
            coverImageModifiedAt: collection.coverImageModifiedAt,
            cloudRecordName: collection.cloudRecordName,
            originalCollectionId: collection.originalCollectionId,
            originalCollectionOwnerId: collection.originalCollectionOwnerId,
            originalCollectionName: collection.originalCollectionName,
            savedAt: collection.savedAt,
            sourceCollectionUpdatedAt: collection.sourceCollectionUpdatedAt,
            followsSourceUpdates: collection.followsSourceUpdates,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt
        )
    }
}
