//
//  RecipeReferenceManager.swift
//  Cauldron
//
//  Created by Claude on 10/21/25.
//

import Foundation
import os

/// Service for managing recipe references (bookmarks to shared recipes)
actor RecipeReferenceManager {
    private let cloudKitService: CloudKitService
    private let recipeRepository: RecipeRepository
    private let logger = Logger(subsystem: "com.cauldron", category: "RecipeReferenceManager")

    init(cloudKitService: CloudKitService, recipeRepository: RecipeRepository) {
        self.cloudKitService = cloudKitService
        self.recipeRepository = recipeRepository
    }

    // MARK: - Fetch References

    /// Fetch all recipe references for a user
    func fetchReferences(for userId: UUID) async throws -> [RecipeReference] {
        logger.info("Fetching recipe references for user: \(userId)")
        let references = try await cloudKitService.fetchRecipeReferences(forUserId: userId)
        logger.info("Fetched \(references.count) recipe references")
        return references
    }

    /// Find a specific reference for a recipe by the current user
    func findReference(for recipeId: UUID, userId: UUID) async throws -> RecipeReference? {
        logger.info("Looking for reference to recipe \(recipeId) by user \(userId)")
        let references = try await cloudKitService.fetchRecipeReferences(forUserId: userId)
        let reference = references.first { $0.originalRecipeId == recipeId }

        if let reference = reference {
            logger.info("Found reference: \(reference.id)")
        } else {
            logger.info("No reference found for recipe \(recipeId)")
        }

        return reference
    }

    /// Check if a reference already exists for a recipe
    func hasReference(for recipeId: UUID, userId: UUID) async throws -> Bool {
        logger.info("Checking if reference exists for recipe \(recipeId) by user \(userId)")
        let reference = try await findReference(for: recipeId, userId: userId)
        let hasRef = reference != nil
        logger.info("Reference exists: \(hasRef)")
        return hasRef
    }

    // MARK: - Delete Reference

    /// Delete a recipe reference (removes bookmark, doesn't affect original recipe)
    func deleteReference(_ referenceId: UUID) async throws {
        logger.info("Deleting recipe reference: \(referenceId)")
        try await cloudKitService.deleteRecipeReference(referenceId)
        logger.info("Successfully deleted recipe reference")
    }

    /// Delete a reference by finding it first
    /// Throws RecipeReferenceError.referenceNotFound if no reference exists for this recipe
    func deleteReference(for recipeId: UUID, userId: UUID) async throws {
        guard let reference = try await findReference(for: recipeId, userId: userId) else {
            logger.info("No reference found to delete for recipe \(recipeId) by user \(userId)")
            logger.info("This is expected when the recipe is a public/shared recipe viewed directly from PUBLIC database")
            throw RecipeReferenceError.referenceNotFound
        }
        try await deleteReference(reference.id)
    }

    // MARK: - Convert to Copy

    /// Convert a referenced recipe into an owned copy
    /// This creates a new recipe in the user's personal collection with a new ID
    func convertReferenceToOwnedCopy(recipe: Recipe, currentUserId: UUID) async throws -> Recipe {
        logger.info("Converting reference to owned copy: \(recipe.title)")

        // Create a new recipe with the current user as owner
        let ownedCopy = await MainActor.run {
            recipe.withOwner(currentUserId)
        }

        // Save the copy to local storage
        try await recipeRepository.create(ownedCopy)
        logger.info("Created owned copy with ID: \(ownedCopy.id)")

        // Optionally delete the reference (user might want to keep both)
        // Let the caller decide whether to delete the reference

        return ownedCopy
    }

    /// Convert a referenced recipe to owned copy AND delete the reference
    func convertReferenceToOwnedCopyAndDeleteReference(
        recipe: Recipe,
        currentUserId: UUID
    ) async throws -> Recipe {
        // Create the owned copy
        let ownedCopy = try await convertReferenceToOwnedCopy(recipe: recipe, currentUserId: currentUserId)

        // Delete the reference
        do {
            try await deleteReference(for: recipe.id, userId: currentUserId)
            logger.info("Deleted reference after creating owned copy")
        } catch {
            logger.warning("Failed to delete reference after creating copy: \(error.localizedDescription)")
            // Don't throw - the copy was created successfully
        }

        return ownedCopy
    }
}

// MARK: - Errors

enum RecipeReferenceError: LocalizedError {
    case referenceNotFound
    case alreadyOwned
    case invalidRecipe

    var errorDescription: String? {
        switch self {
        case .referenceNotFound:
            return "Recipe reference not found"
        case .alreadyOwned:
            return "You already own this recipe"
        case .invalidRecipe:
            return "Invalid recipe data"
        }
    }
}
