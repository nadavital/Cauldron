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
        let title: String
        let imageURL: String?
        let ingredientCount: Int
        let totalMinutes: Int?
        let tags: [String]
    }

    // Profile sharing
    struct ProfileShare: Codable {
        let userId: String
        let username: String
        let displayName: String
        let profileImageURL: String?
        let recipeCount: Int
    }

    // Collection sharing
    struct CollectionShare: Codable {
        let collectionId: String
        let ownerId: String
        let title: String
        let coverImageURL: String?
        let recipeCount: Int
        let recipeIds: [String]
    }
}

/// Response from backend when creating a share link
struct ShareResponse: Codable {
    let shareId: String
    let shareUrl: String
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
