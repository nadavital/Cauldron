//
//  ShareableLink.swift
//  Cauldron
//
//  External sharing models for generating and handling share links
//

import Foundation
import UIKit

/// A shareable link with preview information
struct ShareableLink: Identifiable {
    let id = UUID()
    let url: URL
    let previewText: String
    var image: UIImage?
}

/// Metadata sent to backend when creating a share link
struct ShareMetadata: Codable {
    // Recipe sharing
    struct RecipeShare: Codable {
        let recipeId: String
        let ownerId: String
        let identityRecordName: String
        let title: String
        let totalMinutes: Int?
        let tags: [String]
        let capability: String
        let shouldCreate: Bool

        nonisolated init(
            recipe: Recipe,
            identityRecordName: String,
            capability: String,
            shouldCreate: Bool = true
        ) {
            recipeId = recipe.id.uuidString
            ownerId = recipe.ownerId?.uuidString ?? ""
            self.identityRecordName = identityRecordName
            title = recipe.title
            totalMinutes = recipe.totalMinutes
            tags = recipe.tags.map(\.name)
            self.capability = capability
            self.shouldCreate = shouldCreate
        }
    }

    struct RecipeUnshare: Codable {
        let recipeId: String
        let ownerId: String
        let identityRecordName: String
        let capability: String
    }

    // Profile sharing
    struct ProfileShare: Codable {
        let userId: String
        let identityRecordName: String
        let username: String
        let displayName: String
        let profileEmoji: String?
        let profileColor: String?
        let recipeCount: Int?
        let capability: String
        let shouldCreate: Bool
    }

    struct ProfileUnshare: Codable {
        let userId: String
        let identityRecordName: String
        let username: String
        let capability: String
    }

    struct AccountUnshare: Codable {
        let userId: String
        let identityRecordName: String
        let capability: String
    }

    // Collection sharing
    struct CollectionShare: Codable {
        let collectionId: String
        let ownerId: String
        let identityRecordName: String
        let title: String
        let recipeCount: Int
        let recipeIds: [String]
        let capability: String
        let shouldCreate: Bool
    }

    struct CollectionUnshare: Codable {
        let collectionId: String
        let ownerId: String
        let identityRecordName: String
        let capability: String
    }
}

/// Response from backend when creating a share link
struct ShareResponse: Codable {
    let shareId: String
    let shareUrl: String
}

struct UnshareResponse: Codable {
    let success: Bool
}

/// Content imported from a share link
enum ImportedContent {
    case recipe(Recipe, originalCreator: User?)
    case profile(User)
    case collection(Collection, owner: User?)
}

/// Full data returned from backend for import
struct ShareData: Codable {
    let success: Bool
    let data: DataContent

    struct DataContent: Codable {
        // Recipe fields
        let recipeId: String?
        let title: String?
        let imageURL: String?
        let ingredientCount: Int?
        let totalMinutes: Int?
        let tags: [String]?

        // Profile fields
        let userId: String?
        let username: String?
        let displayName: String?
        let profileImageURL: String?
        let recipeCount: Int?

        // Collection fields
        let collectionId: String?
        let coverImageURL: String?
        let recipeIds: [String]?

        // Common fields
        let ownerId: String?
        let viewCount: Int?
    }
}
