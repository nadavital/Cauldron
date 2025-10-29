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
    case friendsOnly = "friends"
    case publicRecipe = "public"
    
    var displayName: String {
        switch self {
        case .privateRecipe: return "Private"
        case .friendsOnly: return "Friends Only"
        case .publicRecipe: return "Public"
        }
    }
    
    var description: String {
        switch self {
        case .privateRecipe: return "Only you can see this recipe"
        case .friendsOnly: return "Only your friends can see this recipe"
        case .publicRecipe: return "Anyone can discover and view this recipe"
        }
    }
    
    var icon: String {
        switch self {
        case .privateRecipe: return "lock.fill"
        case .friendsOnly: return "person.2.fill"
        case .publicRecipe: return "globe"
        }
    }
}
