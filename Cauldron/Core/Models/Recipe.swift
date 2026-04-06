//
//  Recipe.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Domain model representing a complete recipe
struct Recipe: Sendable, Hashable, Identifiable {
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
    let imageURL: URL?  // Computed from imageFilename when loading from disk
    let isFavorite: Bool
    let visibility: RecipeVisibility
    let ownerId: UUID?  // User who owns this recipe (for cloud sync)
    let cloudRecordName: String?  // CloudKit record name
    let cloudImageRecordName: String?  // CloudKit asset record name for image
    let imageModifiedAt: Date?  // Timestamp when image was last modified
    let createdAt: Date
    let updatedAt: Date

    // Attribution fields for copied recipes
    let originalRecipeId: UUID?  // ID of the original recipe (if this is a copy) - enables update sync
    let originalCreatorId: UUID?  // ID of the user who originally created this recipe (if copied)
    let originalCreatorName: String?  // Display name of the original creator (cached for performance)
    let savedAt: Date?  // When this recipe was saved/copied (if it's a copy)
    let relatedRecipeIds: [UUID] // IDs of related recipes
    let isPreview: Bool  // true = saved locally but not owned (invisible in library), false = owned recipe

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case ingredients
        case steps
        case yields
        case totalMinutes
        case tags
        case nutrition
        case sourceURL
        case sourceTitle
        case notes
        case imageURL
        case isFavorite
        case visibility
        case ownerId
        case cloudRecordName
        case cloudImageRecordName
        case imageModifiedAt
        case createdAt
        case updatedAt
        case originalRecipeId
        case originalCreatorId
        case originalCreatorName
        case savedAt
        case relatedRecipeIds
        case isPreview
    }
    
    nonisolated init(
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
        visibility: RecipeVisibility = .publicRecipe,  // Public by default to encourage sharing
        ownerId: UUID? = nil,
        cloudRecordName: String? = nil,
        cloudImageRecordName: String? = nil,
        imageModifiedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        originalRecipeId: UUID? = nil,
        originalCreatorId: UUID? = nil,
        originalCreatorName: String? = nil,
        savedAt: Date? = nil,
        relatedRecipeIds: [UUID] = [],
        isPreview: Bool = false
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
        self.cloudImageRecordName = cloudImageRecordName
        self.imageModifiedAt = imageModifiedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originalRecipeId = originalRecipeId
        self.originalCreatorId = originalCreatorId
        self.originalCreatorName = originalCreatorName
        self.savedAt = savedAt
        self.relatedRecipeIds = relatedRecipeIds
        self.isPreview = isPreview
    }
    
    nonisolated var displayTime: String? {
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
    nonisolated func scaled(by factor: Double) -> Recipe {
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
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
    
    /// Check if the recipe is valid (has minimum required data)
    nonisolated var isValid: Bool {
        !title.isEmpty && !ingredients.isEmpty && !steps.isEmpty
    }
    
    /// Create a copy with updated image URL
    nonisolated func withImageURL(_ url: URL?) -> Recipe {
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
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }

    /// Create a copy with a new owner (for saving shared recipes)
    /// - Parameters:
    ///   - userId: The ID of the user who will own the copy
    ///   - originalCreatorId: Optional ID of the original creator (for attribution)
    ///   - originalCreatorName: Optional name of the original creator (for attribution)
    /// - Returns: A new Recipe instance owned by the specified user
    nonisolated func withOwner(_ userId: UUID, originalCreatorId: UUID? = nil, originalCreatorName: String? = nil) -> Recipe {
        // Determine attribution - use provided values or fall back to current owner
        let creatorId = originalCreatorId ?? ownerId
        let creatorName = originalCreatorName

        return Recipe(
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
            imageURL: nil, // Clear imageURL - will be set after downloading from CloudKit
            isFavorite: false, // Reset favorite status
            visibility: .publicRecipe, // Keep it public by default to maintain sharing spirit
            ownerId: userId,
            cloudRecordName: nil, // Clear cloud record name for new copy
            cloudImageRecordName: cloudImageRecordName, // Keep cloud image reference so we know to download it
            imageModifiedAt: imageModifiedAt, // Preserve image modified timestamp
            createdAt: Date(),
            updatedAt: Date(),
            originalRecipeId: self.id, // Track the original recipe for update sync
            originalCreatorId: creatorId,
            originalCreatorName: creatorName,
            savedAt: Date(),
            relatedRecipeIds: relatedRecipeIds // Preserve related recipe IDs
        )
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

    /// Check if a viewer can access this recipe based on visibility and relationship
    /// - Parameters:
    ///   - viewerId: ID of the user attempting to view the recipe (nil for current user)
    /// - Returns: True if the recipe is accessible to the viewer
    nonisolated func isAccessible(to viewerId: UUID?, isFriend: Bool = false) -> Bool {
        // Owner can always see their own recipes
        if let viewerId = viewerId, viewerId == ownerId {
            return true
        }

        // Check based on visibility
        // Note: isFriend parameter is deprecated but kept for backward compatibility
        switch visibility {
        case .publicRecipe:
            return true
        case .privateRecipe:
            return false
        }
    }

    /// Check if this recipe meets the minimum visibility requirement for a collection
    /// - Parameter collectionVisibility: The visibility level of the collection
    /// - Returns: True if recipe visibility is sufficient for the collection
    nonisolated func meetsMinimumVisibility(for collectionVisibility: RecipeVisibility) -> Bool {
        switch collectionVisibility {
        case .publicRecipe:
            // Public collections should only contain public recipes
            return visibility == .publicRecipe
        case .privateRecipe:
            // Private collections can contain any visibility
            return true
        }
    }

    /// Create a copy with updated cloud image metadata
    /// - Parameters:
    ///   - recordName: CloudKit asset record name
    ///   - modifiedAt: Timestamp when image was last modified
    /// - Returns: A new Recipe instance with updated cloud image metadata
    nonisolated func withCloudImageMetadata(recordName: String?, modifiedAt: Date?) -> Recipe {
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
            cloudImageRecordName: recordName,
            imageModifiedAt: modifiedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }

    /// Check if the recipe image needs to be uploaded to CloudKit
    /// - Parameter localImageModified: The modification date of the local image file
    /// - Returns: True if local image is newer than cloud or no cloud image exists
    nonisolated func needsImageUpload(localImageModified: Date?) -> Bool {
        // If no local image, no upload needed
        guard let localModified = localImageModified else {
            return false
        }

        // If no cloud image record, upload needed
        guard cloudImageRecordName != nil else {
            return true
        }

        // If no cloud modification date, upload needed
        guard let cloudModified = imageModifiedAt else {
            return true
        }

        // Upload if local is newer than cloud
        return localModified > cloudModified
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.ingredients = try container.decodeIfPresent([Ingredient].self, forKey: .ingredients) ?? []
        self.steps = try container.decodeIfPresent([CookStep].self, forKey: .steps) ?? []
        self.yields = try container.decodeIfPresent(String.self, forKey: .yields) ?? "4 servings"
        self.totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes)
        self.tags = try container.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        self.nutrition = try container.decodeIfPresent(Nutrition.self, forKey: .nutrition)
        self.sourceURL = try container.decodeIfPresent(URL.self, forKey: .sourceURL)
        self.sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        self.notes = try container.decodeIfPresent(String.self, forKey: .notes)
        self.imageURL = try container.decodeIfPresent(URL.self, forKey: .imageURL)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.visibility = try container.decodeIfPresent(RecipeVisibility.self, forKey: .visibility) ?? .publicRecipe
        self.ownerId = try container.decodeIfPresent(UUID.self, forKey: .ownerId)
        self.cloudRecordName = try container.decodeIfPresent(String.self, forKey: .cloudRecordName)
        self.cloudImageRecordName = try container.decodeIfPresent(String.self, forKey: .cloudImageRecordName)
        self.imageModifiedAt = try container.decodeIfPresent(Date.self, forKey: .imageModifiedAt)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.originalRecipeId = try container.decodeIfPresent(UUID.self, forKey: .originalRecipeId)
        self.originalCreatorId = try container.decodeIfPresent(UUID.self, forKey: .originalCreatorId)
        self.originalCreatorName = try container.decodeIfPresent(String.self, forKey: .originalCreatorName)
        self.savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
        self.relatedRecipeIds = try container.decodeIfPresent([UUID].self, forKey: .relatedRecipeIds) ?? []
        self.isPreview = try container.decodeIfPresent(Bool.self, forKey: .isPreview) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        try container.encode(yields, forKey: .yields)
        try container.encodeIfPresent(totalMinutes, forKey: .totalMinutes)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(nutrition, forKey: .nutrition)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(visibility, forKey: .visibility)
        try container.encodeIfPresent(ownerId, forKey: .ownerId)
        try container.encodeIfPresent(cloudRecordName, forKey: .cloudRecordName)
        try container.encodeIfPresent(cloudImageRecordName, forKey: .cloudImageRecordName)
        try container.encodeIfPresent(imageModifiedAt, forKey: .imageModifiedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(originalRecipeId, forKey: .originalRecipeId)
        try container.encodeIfPresent(originalCreatorId, forKey: .originalCreatorId)
        try container.encodeIfPresent(originalCreatorName, forKey: .originalCreatorName)
        try container.encodeIfPresent(savedAt, forKey: .savedAt)
        try container.encode(relatedRecipeIds, forKey: .relatedRecipeIds)
        try container.encode(isPreview, forKey: .isPreview)
    }
}

extension Recipe: Codable {}
