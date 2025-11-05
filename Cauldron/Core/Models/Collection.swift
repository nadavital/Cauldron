//
//  Collection.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import Foundation

/// A user-created collection of recipes for organization and sharing
///
/// Collections allow users to group recipes together for specific purposes
/// (e.g., "Holiday Foods", "Quick Dinners", "Chocolate Desserts").
///
/// Key characteristics:
/// - Explicit membership: recipes are manually added/removed
/// - Can contain both owned recipes and referenced recipes
/// - Support visibility levels (private/friends/public) for sharing
/// - Stored in CloudKit PUBLIC database to enable sharing
/// - Custom presentation with emoji/color theme
///
/// Collections follow the same sharing pattern as recipes:
/// - Private collections: only visible to owner
/// - Friends collections: visible to connected friends
/// - Public collections: visible to all users
@preconcurrency
struct Collection: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let userId: UUID  // Owner of the collection
    let recipeIds: [UUID]  // Explicit list of recipes in this collection
    let visibility: RecipeVisibility

    // Presentation metadata
    let emoji: String?  // Optional emoji icon (e.g., "🎄", "⚡")
    let color: String?  // Optional hex color (e.g., "#FF5733")
    let coverImageType: CoverImageType  // How to display the collection card

    // CloudKit sync
    let cloudRecordName: String?

    // Timestamps
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        userId: UUID,
        recipeIds: [UUID] = [],
        visibility: RecipeVisibility = .privateRecipe,
        emoji: String? = nil,
        color: String? = nil,
        coverImageType: CoverImageType = .recipeGrid,
        cloudRecordName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.userId = userId
        self.recipeIds = recipeIds
        self.visibility = visibility
        self.emoji = emoji
        self.color = color
        self.coverImageType = coverImageType
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Create a new collection with default settings
    static func new(name: String, userId: UUID) -> Collection {
        Collection(
            name: name,
            userId: userId,
            visibility: .privateRecipe
        )
    }

    /// Create an updated copy of this collection
    func updated(
        name: String? = nil,
        description: String? = nil,
        recipeIds: [UUID]? = nil,
        visibility: RecipeVisibility? = nil,
        emoji: String? = nil,
        color: String? = nil,
        coverImageType: CoverImageType? = nil
    ) -> Collection {
        Collection(
            id: self.id,
            name: name ?? self.name,
            description: description ?? self.description,
            userId: self.userId,
            recipeIds: recipeIds ?? self.recipeIds,
            visibility: visibility ?? self.visibility,
            emoji: emoji ?? self.emoji,
            color: color ?? self.color,
            coverImageType: coverImageType ?? self.coverImageType,
            cloudRecordName: self.cloudRecordName,
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }

    /// Add a recipe to this collection
    func addingRecipe(_ recipeId: UUID) -> Collection {
        guard !recipeIds.contains(recipeId) else { return self }
        var newRecipeIds = recipeIds
        newRecipeIds.append(recipeId)
        return updated(recipeIds: newRecipeIds)
    }

    /// Remove a recipe from this collection
    func removingRecipe(_ recipeId: UUID) -> Collection {
        let newRecipeIds = recipeIds.filter { $0 != recipeId }
        return updated(recipeIds: newRecipeIds)
    }

    /// Check if collection contains a recipe
    func contains(recipeId: UUID) -> Bool {
        recipeIds.contains(recipeId)
    }

    /// Number of recipes in collection
    var recipeCount: Int {
        recipeIds.count
    }

    /// Check if collection is empty
    var isEmpty: Bool {
        recipeIds.isEmpty
    }

    /// Check if collection is shared (visible to others)
    var isShared: Bool {
        visibility != .privateRecipe
    }

    /// Get non-conforming recipes based on collection visibility
    /// - Parameter recipes: Array of recipes to check against collection visibility
    /// - Returns: Array of recipes that don't meet the minimum visibility requirement
    func nonConformingRecipes(from recipes: [Recipe]) -> [Recipe] {
        recipes.filter { recipe in
            !recipe.meetsMinimumVisibility(for: visibility)
        }
    }

    /// Get the minimum visibility description for this collection
    var minimumVisibilityDescription: String {
        switch visibility {
        case .publicRecipe:
            return "public"
        case .friendsOnly:
            return "public or friends-only"
        case .privateRecipe:
            return "any visibility"
        }
    }

    // MARK: - Hashable & Equatable

    static func == (lhs: Collection, rhs: Collection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// How the collection cover should be displayed
enum CoverImageType: String, Codable, Sendable, CaseIterable {
    case recipeGrid  // Show 2x2 grid of recipe images
    case emoji       // Show custom emoji
    case color       // Show solid color background with name
}
