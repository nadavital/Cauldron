//
//  RecipeScaler.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import Foundation
import SwiftUI

/// Service for smart recipe scaling with validation and rounding
struct RecipeScaler {
    
    /// Scale a recipe with smart handling of yields, quantities, and validation
    static func scale(_ recipe: Recipe, by factor: Double) -> ScaledRecipe {
        // Scale ingredients with smart rounding
        let scaledIngredients = recipe.ingredients.map { ingredient in
            scaleIngredient(ingredient, by: factor)
        }
        
        // Update yields string
        let scaledYields = scaleYields(recipe.yields, by: factor)
        
        // Scale nutrition
        let scaledNutrition = recipe.nutrition?.scaled(by: factor)
        
        // Check for warnings
        let warnings = generateWarnings(for: scaledIngredients, factor: factor)
        
        let scaledRecipe = Recipe(
            id: recipe.id,
            title: recipe.title,
            ingredients: scaledIngredients,
            steps: recipe.steps,
            yields: scaledYields,
            totalMinutes: recipe.totalMinutes,
            tags: recipe.tags,
            nutrition: scaledNutrition,
            sourceURL: recipe.sourceURL,
            sourceTitle: recipe.sourceTitle,
            notes: recipe.notes,
            imageURL: recipe.imageURL,
            isFavorite: recipe.isFavorite,
            createdAt: recipe.createdAt,
            updatedAt: Date()
        )
        
        return ScaledRecipe(recipe: scaledRecipe, factor: factor, warnings: warnings)
    }
    
    // MARK: - Ingredient Scaling with Smart Rounding
    
    private static func scaleIngredient(_ ingredient: Ingredient, by factor: Double) -> Ingredient {
        guard let quantity = ingredient.quantity else {
            return ingredient
        }
        
        let rawScaled = quantity.value * factor
        let roundedValue = smartRound(rawScaled, unit: quantity.unit)
        
        var scaledQuantity: Quantity
        if let upper = quantity.upperValue {
            let rawScaledUpper = upper * factor
            let roundedUpper = smartRound(rawScaledUpper, unit: quantity.unit)
            scaledQuantity = Quantity(value: roundedValue, upperValue: roundedUpper, unit: quantity.unit)
        } else {
            scaledQuantity = Quantity(value: roundedValue, unit: quantity.unit)
        }
        
        return Ingredient(
            id: ingredient.id,
            name: ingredient.name,
            quantity: scaledQuantity,
            note: ingredient.note
        )
    }
    
    /// Smart rounding based on quantity size and unit type
    private static func smartRound(_ value: Double, unit: UnitKind) -> Double {
        // For very small amounts, use more precision
        if value < 0.25 {
            return round(value * 16) / 16 // Round to nearest 1/16
        } else if value < 1.0 {
            return round(value * 8) / 8 // Round to nearest 1/8
        } else if value < 3.0 {
            return round(value * 4) / 4 // Round to nearest 1/4
        } else if value < 10.0 {
            return round(value * 2) / 2 // Round to nearest 1/2
        } else if value < 100.0 {
            return round(value) // Round to nearest whole
        } else {
            return round(value / 10) * 10 // Round to nearest 10
        }
    }
    
    // MARK: - Yields Scaling
    
    private static func scaleYields(_ yields: String, by factor: Double) -> String {
        // Try to parse and update numeric values in yields string
        // Each pattern tuple: (regex pattern, capture group index for the number)
        let patterns: [(String, Int)] = [
            // Match "4 servings", "6 people", "8 portions" - number is in group 1
            ("(\\d+)\\s+(servings?|people|persons?|portions?)", 1),
            // Match "serves 4", "feeds 6" - number is in group 2
            ("(serves?|feeds?)\\s+(\\d+)", 2),
            // Match "makes 12", "yields 24" - number is in group 2
            // Match "makes 12", "yields 24" - number is in group 2
            ("(makes?|yields?)\\s+(\\d+)", 2),
            // Generic: Number at start followed by text (e.g., "2 loaves", "12 cookies") - number is in group 1
            ("^(\\d+)\\s+.+", 1),
            // Generic: Just a number (e.g., "4") - number is in group 1
            ("^(\\d+)$", 1)
        ]

        var result = yields

        for (pattern, numberGroupIndex) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(yields.startIndex..., in: yields)

                if let match = regex.firstMatch(in: yields, range: range) {
                    // Extract the number from the specified capture group
                    if match.numberOfRanges > numberGroupIndex {
                        let numberRange = match.range(at: numberGroupIndex)
                        if let swiftRange = Range(numberRange, in: yields) {
                            let numberStr = String(yields[swiftRange])
                            if let originalNumber = Int(numberStr) {
                                let scaledNumber = Double(originalNumber) * factor
                                let formattedNumber = formatFactor(scaledNumber)
                                result = (yields as NSString).replacingCharacters(in: numberRange, with: "\(formattedNumber)")
                                return result
                            }
                        }
                    }
                }
            }
        }
        
        // If no pattern matched, append scaling info
        if factor != 1.0 {
            return "\(yields) (×\(formatFactor(factor)))"
        }
        
        return yields
    }
    
    private static func formatFactor(_ factor: Double) -> String {
        if factor == floor(factor) {
            return String(format: "%.0f", factor)
        } else if factor * 2 == floor(factor * 2) {
            return String(format: "%.1f", factor)
        } else {
            return String(format: "%.2f", factor)
        }
    }
    
    // MARK: - Validation & Warnings
    
    private static func generateWarnings(for ingredients: [Ingredient], factor: Double) -> [ScalingWarning] {
        var warnings: [ScalingWarning] = []
        
        // Check for impractical quantities
        for ingredient in ingredients {
            guard let quantity = ingredient.quantity else { continue }
            
            // Warn about very small quantities
            if quantity.value < 0.125 && !quantity.unit.isWeight {
                warnings.append(ScalingWarning(
                    type: .verySmallQuantity,
                    message: "'\(ingredient.name)' requires a very small amount (\(quantity.displayString)). Consider measuring carefully or omitting."
                ))
            }
            
            // Warn about fractional eggs
            if ingredient.name.lowercased().contains("egg") {
                let fractionalPart = quantity.value - floor(quantity.value)
                if fractionalPart > 0.01 && fractionalPart < 0.99 {
                    warnings.append(ScalingWarning(
                        type: .fractionalEggs,
                        message: "'\(ingredient.name)' scales to \(quantity.displayString). Round to \(Int(round(quantity.value))) egg(s) or use \(Int(ceil(quantity.value))) for more egg flavor."
                    ))
                }
            }
            
            // Warn about very large quantities
            if quantity.value > 50 && quantity.unit.isVolume {
                warnings.append(ScalingWarning(
                    type: .veryLargeQuantity,
                    message: "'\(ingredient.name)' requires a large amount (\(quantity.displayString)). Verify this is practical for your equipment."
                ))
            }
        }
        
        // Warn about extreme scaling
        if factor > 4.0 {
            warnings.append(ScalingWarning(
                type: .extremeScaling,
                message: "Scaling by \(formatFactor(factor))× is significant. Cooking times and pan sizes may need adjustment."
            ))
        } else if factor < 0.5 {
            warnings.append(ScalingWarning(
                type: .extremeScaling,
                message: "Scaling down by \(formatFactor(factor))× may result in very small quantities. Some ingredients may be difficult to measure."
            ))
        }
        
        return warnings
    }
}

// MARK: - Models

struct ScaledRecipe {
    let recipe: Recipe
    let factor: Double
    let warnings: [ScalingWarning]
    
    var hasWarnings: Bool {
        !warnings.isEmpty
    }
}

struct ScalingWarning: Identifiable {
    let id = UUID()
    let type: WarningType
    let message: String
    
    enum WarningType {
        case verySmallQuantity
        case veryLargeQuantity
        case fractionalEggs
        case extremeScaling
    }
    
    var icon: String {
        switch type {
        case .verySmallQuantity: return "exclamationmark.triangle.fill"
        case .veryLargeQuantity: return "exclamationmark.triangle.fill"
        case .fractionalEggs: return "info.circle.fill"
        case .extremeScaling: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch type {
        case .verySmallQuantity, .veryLargeQuantity, .extremeScaling:
            return .orange
        case .fractionalEggs:
            return .blue
        }
    }
}
