//
//  Recommender.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Service for recipe recommendations (pantry features disabled)
actor Recommender {
    private var coverageThreshold: Double = 0.7 // 70% default, can be adjusted

    init() {
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
    
    /// Recommend recipes (pantry features disabled - returns empty)
    func recommendRecipes(from recipes: [Recipe]) async throws -> [RecipeMatch] {
        // Pantry features have been removed
        return []
    }

    /// Filter recipes that can be cooked now (pantry features disabled - returns empty)
    func filterCookableNow(from recipes: [Recipe]) async throws -> [Recipe] {
        // Pantry features have been removed
        return []
    }
}

