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

    // Staleness tracking
    let lastValidatedAt: Date  // Last time we checked if the original collection still exists
    let cachedVisibility: String  // Cached visibility from when we saved it

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
        lastValidatedAt: Date = Date(),
        cachedVisibility: String = "public",
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
        self.lastValidatedAt = lastValidatedAt
        self.cachedVisibility = cachedVisibility
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
            recipeCount: collection.recipeCount,
            lastValidatedAt: Date(),
            cachedVisibility: collection.visibility.rawValue
        )
    }

    /// Check if this reference needs validation (older than 24 hours)
    var needsValidation: Bool {
        let dayInSeconds: TimeInterval = 24 * 60 * 60
        return Date().timeIntervalSince(lastValidatedAt) > dayInSeconds
    }

    /// Update validation timestamp
    func withUpdatedValidation() -> CollectionReference {
        CollectionReference(
            id: id,
            userId: userId,
            originalCollectionId: originalCollectionId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            collectionName: collectionName,
            collectionEmoji: collectionEmoji,
            recipeCount: recipeCount,
            lastValidatedAt: Date(),
            cachedVisibility: cachedVisibility,
            cloudRecordName: cloudRecordName
        )
    }

    /// Update cached metadata from current collection
    func withUpdatedMetadata(from collection: Collection) -> CollectionReference {
        CollectionReference(
            id: id,
            userId: userId,
            originalCollectionId: originalCollectionId,
            originalOwnerId: originalOwnerId,
            savedAt: savedAt,
            collectionName: collection.name,
            collectionEmoji: collection.emoji,
            recipeCount: collection.recipeCount,
            lastValidatedAt: Date(),
            cachedVisibility: collection.visibility.rawValue,
            cloudRecordName: cloudRecordName
        )
    }
}
