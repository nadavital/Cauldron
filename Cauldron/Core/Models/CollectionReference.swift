//
//  CollectionReference.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation

/// A saved reference to someone else's shared collection (stored in CloudKit PUBLIC database)
///
/// This represents a user's **explicit save** of a public/shared collection to their personal collections.
/// Unlike browsing shared collections in the Friends tab, CollectionReference is persistent and appears
/// in the user's Collections view.
///
/// Key characteristics:
/// - Stored as a separate record in CloudKit (not a copy of the collection)
/// - Points to the original collection via originalCollectionId
/// - References stay synced with the original - when owner updates, you see changes
/// - Can be deleted independently without affecting the original collection
/// - Allows users to "bookmark" collections they can view but don't own
///
/// Important: Collection references do NOT copy recipes. When viewing a referenced collection,
/// you see the owner's current recipes. To cook from those recipes, you can either:
/// - View/cook directly (temporary access)
/// - Save individual recipes to your collection (creates RecipeReference)
struct CollectionReference: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let userId: UUID  // Who saved this reference
    let originalCollectionId: UUID  // Points to the actual collection
    let originalOwnerId: UUID  // Collection owner
    let savedAt: Date

    // Cached metadata for fast list display (avoid fetching full collection)
    let collectionName: String
    let collectionEmoji: String?
    let recipeCount: Int

    // CloudKit sync
    let cloudRecordName: String?

    init(
        id: UUID = UUID(),
        userId: UUID,
        originalCollectionId: UUID,
        originalOwnerId: UUID,
        savedAt: Date = Date(),
        collectionName: String,
        collectionEmoji: String? = nil,
        recipeCount: Int = 0,
        cloudRecordName: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.originalCollectionId = originalCollectionId
        self.originalOwnerId = originalOwnerId
        self.savedAt = savedAt
        self.collectionName = collectionName
        self.collectionEmoji = collectionEmoji
        self.recipeCount = recipeCount
        self.cloudRecordName = cloudRecordName
    }

    /// Create a reference to a shared collection
    static func reference(
        userId: UUID,
        collection: Collection
    ) -> CollectionReference {
        CollectionReference(
            userId: userId,
            originalCollectionId: collection.id,
            originalOwnerId: collection.userId,
            collectionName: collection.name,
            collectionEmoji: collection.emoji,
            recipeCount: collection.recipeCount
        )
    }
}
