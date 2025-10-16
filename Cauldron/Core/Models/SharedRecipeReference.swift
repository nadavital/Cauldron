//
//  SharedRecipeReference.swift
//  Cauldron
//
//  Created by Claude on 10/16/25.
//

import Foundation

/// Type of recipe sharing
enum ShareType: String, Codable, Sendable, CaseIterable {
    case direct = "direct"           // Shared with specific friend via app
    case link = "link"               // Shared via iCloud link
    case friendsOnly = "friendsOnly" // Auto-visible to all friends
    case publicRecipe = "public"     // Auto-visible to everyone

    var displayName: String {
        switch self {
        case .direct: return "Direct Share"
        case .link: return "Link Share"
        case .friendsOnly: return "Friends Only"
        case .publicRecipe: return "Public"
        }
    }
}

/// Lightweight reference to a shared recipe
/// Instead of duplicating the full recipe, this points to the original in the owner's private database
struct SharedRecipeReference: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let originalRecipeId: UUID       // ID of the actual recipe
    let originalOwnerId: UUID        // User who owns the original recipe
    let sharedWithUserId: UUID?      // Recipient (nil for friendsOnly/public)
    let sharedByUserId: UUID         // User who created this share
    let sharedAt: Date
    let shareType: ShareType
    let shareURL: URL?               // iCloud share URL for link shares
    let recipeTitle: String          // Cached for display without fetching full recipe
    let recipeTags: [String]         // Cached for filtering/search

    init(
        id: UUID = UUID(),
        originalRecipeId: UUID,
        originalOwnerId: UUID,
        sharedWithUserId: UUID? = nil,
        sharedByUserId: UUID,
        sharedAt: Date = Date(),
        shareType: ShareType,
        shareURL: URL? = nil,
        recipeTitle: String,
        recipeTags: [String] = []
    ) {
        self.id = id
        self.originalRecipeId = originalRecipeId
        self.originalOwnerId = originalOwnerId
        self.sharedWithUserId = sharedWithUserId
        self.sharedByUserId = sharedByUserId
        self.sharedAt = sharedAt
        self.shareType = shareType
        self.shareURL = shareURL
        self.recipeTitle = recipeTitle
        self.recipeTags = recipeTags
    }

    /// Create a direct share reference (specific friend)
    static func directShare(
        recipeId: UUID,
        ownerId: UUID,
        sharedWithUserId: UUID,
        sharedByUserId: UUID,
        recipeTitle: String,
        recipeTags: [String] = []
    ) -> SharedRecipeReference {
        SharedRecipeReference(
            originalRecipeId: recipeId,
            originalOwnerId: ownerId,
            sharedWithUserId: sharedWithUserId,
            sharedByUserId: sharedByUserId,
            shareType: .direct,
            recipeTitle: recipeTitle,
            recipeTags: recipeTags
        )
    }

    /// Create a link share reference (iCloud URL)
    static func linkShare(
        recipeId: UUID,
        ownerId: UUID,
        shareURL: URL,
        recipeTitle: String,
        recipeTags: [String] = []
    ) -> SharedRecipeReference {
        SharedRecipeReference(
            originalRecipeId: recipeId,
            originalOwnerId: ownerId,
            sharedByUserId: ownerId,
            shareType: .link,
            shareURL: shareURL,
            recipeTitle: recipeTitle,
            recipeTags: recipeTags
        )
    }

    /// Create a friends-only visibility reference
    static func friendsOnly(
        recipeId: UUID,
        ownerId: UUID,
        recipeTitle: String,
        recipeTags: [String] = []
    ) -> SharedRecipeReference {
        SharedRecipeReference(
            originalRecipeId: recipeId,
            originalOwnerId: ownerId,
            sharedByUserId: ownerId,
            shareType: .friendsOnly,
            recipeTitle: recipeTitle,
            recipeTags: recipeTags
        )
    }

    /// Create a public visibility reference
    static func publicRecipe(
        recipeId: UUID,
        ownerId: UUID,
        recipeTitle: String,
        recipeTags: [String] = []
    ) -> SharedRecipeReference {
        SharedRecipeReference(
            originalRecipeId: recipeId,
            originalOwnerId: ownerId,
            sharedByUserId: ownerId,
            shareType: .publicRecipe,
            recipeTitle: recipeTitle,
            recipeTags: recipeTags
        )
    }
}
