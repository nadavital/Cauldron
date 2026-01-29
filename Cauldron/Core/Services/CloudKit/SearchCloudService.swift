//
//  SearchCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for search operations.
//

import Foundation
import CloudKit
import os

/// CloudKit service for search-related operations.
///
/// Handles:
/// - Public recipe search by query and categories
/// - Discovery of public content
actor SearchCloudService {
    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "SearchCloudService")

    init(core: CloudKitCore) {
        self.core = core
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Search

    /// Search public recipes by query and/or categories
    /// - Parameters:
    ///   - query: The search text (searches title and tags)
    ///   - categories: Optional list of category names to filter by (AND logic)
    ///   - limit: Maximum number of results
    func searchPublicRecipes(query: String, categories: [String]?, limit: Int = 50) async throws -> [Recipe] {
        let db = try await core.getPublicDatabase()
        var predicates: [NSPredicate] = []

        // 1. Visibility Predicate
        predicates.append(NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue))

        // Text and category filtering is done client-side in RecipeGroupingService
        // CloudKit's predicate support is limited (no CONTAINS, no complex OR)
        // We fetch all public recipes and filter client-side for proper substring matching

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        // Query SharedRecipe record type (public recipes), not Recipe (private)
        let queryObj = CKQuery(recordType: CloudKitCore.RecordType.sharedRecipe, predicate: compoundPredicate)
        queryObj.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        logger.info("🔍 Searching SharedRecipe with predicate: \(compoundPredicate.predicateFormat)")

        let results = try await db.records(matching: queryObj, resultsLimit: limit)

        logger.info("🔍 Search returned \(results.matchResults.count) raw results")

        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            switch result {
            case .success(let record):
                do {
                    let recipe = try recipeFromRecord(record)
                    recipes.append(recipe)
                } catch {
                    logger.error("❌ Failed to parse record \(record.recordID.recordName): \(error.localizedDescription)")
                }
            case .failure(let error):
                logger.error("❌ Failed to get record: \(error.localizedDescription)")
            }
        }

        logger.info("✅ Search returning \(recipes.count) parsed recipes")
        return recipes
    }

    // MARK: - Private Helpers

    private func recipeFromRecord(_ record: CKRecord) throws -> Recipe {
        guard let recipeIdString = record["recipeId"] as? String,
              let recipeId = UUID(uuidString: recipeIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let title = record["title"] as? String,
              let visibilityString = record["visibility"] as? String,
              let visibility = RecipeVisibility(rawValue: visibilityString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        let decoder = JSONDecoder()

        let ingredients: [Ingredient]
        if let ingredientsData = record["ingredientsData"] as? Data {
            ingredients = (try? decoder.decode([Ingredient].self, from: ingredientsData)) ?? []
        } else {
            ingredients = []
        }

        let steps: [CookStep]
        if let stepsData = record["stepsData"] as? Data {
            steps = (try? decoder.decode([CookStep].self, from: stepsData)) ?? []
        } else {
            steps = []
        }

        let tags: [Tag]
        if let tagsData = record["tagsData"] as? Data {
            tags = (try? decoder.decode([Tag].self, from: tagsData)) ?? []
        } else {
            tags = []
        }

        let yields = record["yields"] as? String ?? "4 servings"
        let totalMinutes = record["totalMinutes"] as? Int

        let relatedRecipeIds: [UUID]
        if let relatedIdsData = record["relatedRecipeIdsData"] as? Data {
            relatedRecipeIds = (try? decoder.decode([UUID].self, from: relatedIdsData)) ?? []
        } else {
            relatedRecipeIds = []
        }

        let cloudImageRecordName: String? = (record["imageAsset"] as? CKAsset) != nil ? record.recordID.recordName : nil
        let imageModifiedAt = record["imageModifiedAt"] as? Date
        let imageURL: URL? = nil

        let originalRecipeId: UUID? = {
            if let idString = record["originalRecipeId"] as? String {
                return UUID(uuidString: idString)
            }
            return nil
        }()
        let originalCreatorId: UUID? = {
            if let idString = record["originalCreatorId"] as? String {
                return UUID(uuidString: idString)
            }
            return nil
        }()
        let originalCreatorName = record["originalCreatorName"] as? String
        let savedAt = record["savedAt"] as? Date
        let notes = record["notes"] as? String
        let isPreview = record["isPreview"] as? Bool ?? false

        return Recipe(
            id: recipeId,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: notes,
            imageURL: imageURL,
            isFavorite: false,
            visibility: visibility,
            ownerId: ownerId,
            cloudRecordName: record.recordID.recordName,
            cloudImageRecordName: cloudImageRecordName,
            imageModifiedAt: imageModifiedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            originalCreatorId: originalCreatorId,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            relatedRecipeIds: relatedRecipeIds,
            isPreview: isPreview
        )
    }
}
