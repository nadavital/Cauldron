//
//  CloudKitService+Search.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

extension CloudKitService {
    // MARK: - Search
    
    /// Search public recipes by query and/or categories
    /// - Parameters:
    ///   - query: The search text (searches title and tags)
    ///   - categories: Optional list of category names to filter by (AND logic)
    ///   - limit: Maximum number of results
    func searchPublicRecipes(query: String, categories: [String]?, limit: Int = 50) async throws -> [Recipe] {
        let db = try getPublicDatabase()
        var predicates: [NSPredicate] = []
        
        // 1. Visibility Predicate
        predicates.append(NSPredicate(format: "visibility == %@", RecipeVisibility.publicRecipe.rawValue))
        
        // 2. Text Search Predicate
        if !query.isEmpty {
            // Search title OR tags
            // Note: CloudKit doesn't support complex OR queries well with other AND clauses in some cases,
            // but (A OR B) AND C is generally supported.
            let titlePredicate = NSPredicate(format: "title BEGINSWITH %@", query) // BEGINSWITH is often faster/better supported than CONTAINS for tokenized fields, but let's try CONTAINS[cd] if possible or stick to simple token matching.
            // Actually, for "Self-Service Search", CloudKit recommends using `allTokens` or `self` for tokenized search if configured.
            // But since we don't know the index configuration, let's use `allTokens` tokenized search if possible, or fall back to standard text matching.
            // Let's use a simple approach first: Title contains query OR tags contains query
            
            // Note: CONTAINS[cd] requires a "Queryable" index on the field.
            // We'll assume "title" and "searchableTags" are queryable.
            
            let textPredicate = NSPredicate(format: "title BEGINSWITH %@ OR searchableTags CONTAINS %@", query, query)
            // Using BEGINSWITH for title as it's often a default index. CONTAINS might require explicit index.
            // For tags, CONTAINS checks if the array contains the element.
            
            predicates.append(textPredicate)
        }
        
        // 3. Category Filter Predicate
        if let categories = categories, !categories.isEmpty {
            for category in categories {
                // For each category, the recipe's tags must contain it
                let categoryPredicate = NSPredicate(format: "searchableTags CONTAINS %@", category)
                predicates.append(categoryPredicate)
            }
        }
        
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        let queryObj = CKQuery(recordType: recipeRecordType, predicate: compoundPredicate)
        queryObj.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let results = try await db.records(matching: queryObj, resultsLimit: limit)
        
        var recipes: [Recipe] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let recipe = try? recipeFromRecord(record) {
                recipes.append(recipe)
            }
        }
        
        return recipes
    }
}
