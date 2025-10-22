//
//  Recipe.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Domain model representing a complete recipe
struct Recipe: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let title: String
    let ingredients: [Ingredient]
    let steps: [CookStep]
    let yields: String
    let totalMinutes: Int?
    let tags: [Tag]
    let nutrition: Nutrition?
    let sourceURL: URL?
    let sourceTitle: String?
    let notes: String?
    let imageURL: URL?
    let isFavorite: Bool
    let visibility: RecipeVisibility
    let ownerId: UUID?  // User who owns this recipe (for cloud sync)
    let cloudRecordName: String?  // CloudKit record name
    let createdAt: Date
    let updatedAt: Date
    
    init(
        id: UUID = UUID(),
        title: String,
        ingredients: [Ingredient],
        steps: [CookStep],
        yields: String = "4 servings",
        totalMinutes: Int? = nil,
        tags: [Tag] = [],
        nutrition: Nutrition? = nil,
        sourceURL: URL? = nil,
        sourceTitle: String? = nil,
        notes: String? = nil,
        imageURL: URL? = nil,
        isFavorite: Bool = false,
        visibility: RecipeVisibility = .privateRecipe,  // Private by default, but still syncs to iCloud
        ownerId: UUID? = nil,
        cloudRecordName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.tags = tags
        self.nutrition = nutrition
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.notes = notes
        self.imageURL = imageURL
        self.isFavorite = isFavorite
        self.visibility = visibility
        self.ownerId = ownerId
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    var displayTime: String? {
        guard let minutes = totalMinutes else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    /// Scale the recipe by a factor
    func scaled(by factor: Double) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: ingredients.map { $0.scaled(by: factor) },
            steps: steps,
            yields: yields, // Could be smart about parsing/updating this
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition?.scaled(by: factor),
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: imageURL,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
    
    /// Check if the recipe is valid (has minimum required data)
    var isValid: Bool {
        !title.isEmpty && !ingredients.isEmpty && !steps.isEmpty
    }
    
    /// Create a copy with updated image URL
    func withImageURL(_ url: URL?) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: url,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    /// Create a copy with a new owner (for saving shared recipes)
    func withOwner(_ userId: UUID) -> Recipe {
        Recipe(
            id: UUID(), // New ID for the copy
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: imageURL,
            isFavorite: false, // Reset favorite status
            visibility: .privateRecipe, // Make it private by default
            ownerId: userId,
            cloudRecordName: nil, // Clear cloud record name for new copy
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Create a copy with updated favorite flag
    func withFavorite(_ isFavorite: Bool) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: imageURL,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    /// Toggle the favorite status while preserving metadata
    func toggledFavorite() -> Recipe {
        withFavorite(!isFavorite)
    }

    /// Check if the current user owns this recipe
    @MainActor
    func isOwnedByCurrentUser() -> Bool {
        guard let ownerId = ownerId,
              let currentUserId = CurrentUserSession.shared.userId else {
            return false
        }
        return ownerId == currentUserId
    }

    /// Check if this is a referenced recipe (not owned by current user)
    @MainActor
    var isReference: Bool {
        !isOwnedByCurrentUser()
    }
}
