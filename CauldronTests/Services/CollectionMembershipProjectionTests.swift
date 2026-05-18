//
//  CollectionMembershipProjectionTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class CollectionMembershipProjectionTests: XCTestCase {
    func testActiveRecipeIdsUseLatestEdgeAndSortOrderOverLegacyCache() {
        let collectionId = UUID()
        let ownerId = UUID()
        let staleRecipeId = UUID()
        let keptRecipeId = UUID()
        let addedRecipeId = UUID()
        let now = Date()

        let collection = Collection(
            name: "Public Collection",
            userId: ownerId,
            recipeIds: [staleRecipeId],
            visibility: .publicRecipe,
            updatedAt: now
        )

        let edges = [
            CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: staleRecipeId,
                ownerId: ownerId,
                status: .active,
                updatedAt: now.addingTimeInterval(-100),
                sortOrder: 0
            ),
            CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: staleRecipeId,
                ownerId: ownerId,
                status: .removed,
                updatedAt: now,
                sortOrder: 0
            ),
            CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: addedRecipeId,
                ownerId: ownerId,
                status: .active,
                updatedAt: now.addingTimeInterval(-20),
                sortOrder: 1
            ),
            CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: keptRecipeId,
                ownerId: ownerId,
                status: .active,
                updatedAt: now.addingTimeInterval(-10),
                sortOrder: 0
            )
        ]

        let recipeIds = CollectionMembershipProjection.activeRecipeIds(from: edges)
        let projected = CollectionMembershipProjection.collectionWithRecipeIds(collection, recipeIds)

        XCTAssertEqual(projected.recipeIds, [keptRecipeId, addedRecipeId])
        XCTAssertEqual(projected.updatedAt, collection.updatedAt)
        XCTAssertEqual(projected.visibility, .publicRecipe)
    }
}
