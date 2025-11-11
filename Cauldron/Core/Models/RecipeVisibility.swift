//
//  RecipeVisibility.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Defines who can see a recipe
enum RecipeVisibility: String, Codable, Sendable, CaseIterable {
    case privateRecipe = "private"
    case publicRecipe = "public"

    var displayName: String {
        switch self {
        case .privateRecipe: return "Private"
        case .publicRecipe: return "Public"
        }
    }

    var description: String {
        switch self {
        case .privateRecipe: return "Only you can see this recipe"
        case .publicRecipe: return "Anyone can discover and view this recipe"
        }
    }

    var icon: String {
        switch self {
        case .privateRecipe: return "lock.fill"
        case .publicRecipe: return "globe"
        }
    }

    // MARK: - Migration Support

    /// Custom decoder to handle legacy "friends" visibility by migrating to "public"
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "private":
            self = .privateRecipe
        case "public":
            self = .publicRecipe
        case "friends":
            // Migration: friendsOnly → public
            self = .publicRecipe
        default:
            // Fallback to private for unknown values
            self = .privateRecipe
        }
    }
}
