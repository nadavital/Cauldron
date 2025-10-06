//
//  Recommender.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Service for recipe recommendations based on pantry
actor Recommender {
    private let pantryRepo: PantryRepository
    private var coverageThreshold: Double = 0.7 // 70% default, can be adjusted
    
    init(pantryRepo: PantryRepository) {
        self.pantryRepo = pantryRepo
    }
    
    /// Update the coverage threshold for "cookable now" recipes
    func setCoverageThreshold(_ threshold: Double) {
        self.coverageThreshold = max(0.0, min(1.0, threshold))
    }
    
    func getCoverageThreshold() -> Double {
        return coverageThreshold
    }
    
    struct RecipeMatch {
        let recipe: Recipe
        let coveragePercent: Double
        let coverageScore: Double // Weighted by match quality
        let missingIngredients: [String]
        let partialMatches: [String] // Ingredients with insufficient quantity
        let ingredientScores: [IngredientMatchScore]
    }
    
    /// Recommend recipes based on what's in pantry
    func recommendRecipes(from recipes: [Recipe]) async throws -> [RecipeMatch] {
        let pantryItems = try await pantryRepo.fetchAll()
        
        var matches: [RecipeMatch] = []
        
        for recipe in recipes {
            let ingredientScores = recipe.ingredients.map { ingredient in
                IngredientMatcher.calculateMatchScore(ingredient: ingredient, pantryItems: pantryItems)
            }
            
            let totalIngredients = Double(recipe.ingredients.count)
            let matchedCount = ingredientScores.filter { $0.isAvailable }.count
            let coveragePercent = (Double(matchedCount) / totalIngredients) * 100
            
            // Calculate weighted score (considers match quality)
            let totalScore = ingredientScores.reduce(0.0) { $0 + $1.score }
            let coverageScore = (totalScore / totalIngredients) * 100
            
            // Collect missing and partial matches
            let missing = ingredientScores
                .filter { !$0.isAvailable }
                .map { $0.ingredient.name }
            
            let partial = ingredientScores
                .filter {
                    guard $0.isAvailable && !$0.quantityMatch.isSufficient else { return false }
                    switch $0.quantityMatch {
                    case .unknown:
                        return false
                    default:
                        return true
                    }
                }
                .map { $0.ingredient.name }
            
            matches.append(RecipeMatch(
                recipe: recipe,
                coveragePercent: coveragePercent,
                coverageScore: coverageScore,
                missingIngredients: missing,
                partialMatches: partial,
                ingredientScores: ingredientScores
            ))
        }
        
        // Sort by weighted score (better matching quality)
        return matches.sorted { $0.coverageScore > $1.coverageScore }
    }
    
    /// Filter recipes that can be cooked now (based on configurable threshold)
    func filterCookableNow(from recipes: [Recipe]) async throws -> [Recipe] {
        let matches = try await recommendRecipes(from: recipes)
        return matches
            .filter { $0.coverageScore >= (coverageThreshold * 100) }
            .map { $0.recipe }
    }
}

