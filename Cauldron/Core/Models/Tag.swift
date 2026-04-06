//
//  Tag.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents a tag for categorizing recipes
struct Tag: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    
    nonisolated init(id: UUID = UUID(), name: String) {
        self.id = id
        
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if this matches a known category and use the canonical name
        if let category = RecipeCategory.match(string: trimmed) {
            self.name = category.displayName
        } else {
            // Otherwise just Title Case it
            self.name = trimmed.capitalized
        }
    }
    
    /// Create a tag from a string
    nonisolated static func from(_ string: String) -> Tag {
        Tag(name: string)
    }
    
    /// Common tags to suggest to users
    nonisolated static let commonTags: [String] = [
        "Breakfast", "Lunch", "Dinner", "Dessert", "Snack",
        "Vegetarian", "Vegan", "Gluten-Free", "Keto", "Paleo",
        "Quick & Easy", "Healthy", "Comfort Food", "Baking",
        "Italian", "Mexican", "Asian", "Mediterranean", "American"
    ]
}

extension Tag: @preconcurrency Codable {}

extension Tag: Comparable {
    nonisolated static func < (lhs: Tag, rhs: Tag) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
