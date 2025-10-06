//
//  IngredientMatcher.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import Foundation

/// Service for intelligent ingredient matching with synonyms, plurals, and partial matching
struct IngredientMatcher {
    
    /// Ingredient synonyms database
    private static let synonyms: [String: Set<String>] = [
        "cilantro": ["coriander", "chinese parsley"],
        "coriander": ["cilantro"],
        "scallions": ["green onions", "spring onions"],
        "green onions": ["scallions", "spring onions"],
        "bell pepper": ["sweet pepper", "capsicum"],
        "zucchini": ["courgette"],
        "eggplant": ["aubergine"],
        "arugula": ["rocket"],
        "shrimp": ["prawns"],
        "ground beef": ["minced beef", "beef mince"],
        "heavy cream": ["heavy whipping cream", "double cream"],
        "confectioners sugar": ["powdered sugar", "icing sugar"],
        "kosher salt": ["sea salt", "table salt", "salt"],
        "all-purpose flour": ["plain flour", "flour"],
        "cornstarch": ["corn flour", "cornflour"],
        "baking soda": ["bicarbonate of soda"],
        "molasses": ["treacle"],
        "cookies": ["biscuits"],
        "candy": ["sweets"],
        "soda": ["fizzy drink", "pop"]
    ]
    
    /// Check if an ingredient is available in the pantry
    static func isAvailable(ingredient: String, in pantryItems: Set<String>) -> MatchResult {
        let normalized = normalize(ingredient)
        
        // Direct exact match
        if pantryItems.contains(normalized) {
            return .exact
        }
        
        // Check pantry items for contains match
        for pantryItem in pantryItems {
            if normalized.contains(pantryItem) || pantryItem.contains(normalized) {
                return .partial
            }
        }
        
        // Check synonyms
        if let syns = synonyms[normalized] {
            for synonym in syns {
                if pantryItems.contains(synonym) {
                    return .synonym
                }
                
                // Check if any pantry item contains the synonym
                for pantryItem in pantryItems {
                    if pantryItem.contains(synonym) || synonym.contains(pantryItem) {
                        return .synonym
                    }
                }
            }
        }
        
        // Check if ingredient has a synonym in our database that matches pantry
        for (key, syns) in synonyms where syns.contains(normalized) {
            if pantryItems.contains(key) {
                return .synonym
            }
            
            for pantryItem in pantryItems {
                if pantryItem.contains(key) || key.contains(pantryItem) {
                    return .synonym
                }
            }
        }
        
        // Check base ingredient (remove adjectives/descriptors)
        let baseIngredient = extractBaseIngredient(normalized)
        if baseIngredient != normalized {
            for pantryItem in pantryItems {
                if pantryItem.contains(baseIngredient) || baseIngredient.contains(pantryItem) {
                    return .base
                }
            }
        }
        
        return .notFound
    }
    
    /// Normalize ingredient string for matching
    private static func normalize(_ ingredient: String) -> String {
        var normalized = ingredient.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common descriptors that don't affect matching
        let descriptorsToRemove = [
            "fresh", "dried", "frozen", "canned", "raw", "cooked",
            "chopped", "diced", "minced", "sliced", "shredded", "grated",
            "large", "small", "medium", "extra", "optional",
            "or to taste", "to taste", "pinch of", "dash of"
        ]
        
        for descriptor in descriptorsToRemove {
            normalized = normalized.replacingOccurrences(of: descriptor, with: "")
        }
        
        // Handle plurals - simple approach
        if normalized.hasSuffix("ies") {
            normalized = String(normalized.dropLast(3)) + "y"
        } else if normalized.hasSuffix("es") {
            normalized = String(normalized.dropLast(2))
        } else if normalized.hasSuffix("s") && !normalized.hasSuffix("ss") {
            normalized = String(normalized.dropLast())
        }
        
        return normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    /// Extract base ingredient by removing quantities and common descriptors
    private static func extractBaseIngredient(_ ingredient: String) -> String {
        let words = ingredient.split(separator: " ")
        
        // Common cooking verbs and adjectives to skip
        let skipWords: Set<String> = [
            "boneless", "skinless", "seedless",
            "unsalted", "salted", "sweetened", "unsweetened",
            "whole", "fat", "low", "reduced", "free",
            "organic", "natural", "pure"
        ]
        
        let filtered = words.filter { word in
            !skipWords.contains(String(word))
        }
        
        // Return the last 1-2 words as the base ingredient
        if filtered.count >= 2 {
            return filtered.suffix(2).joined(separator: " ")
        } else if !filtered.isEmpty {
            return filtered.last.map(String.init) ?? ingredient
        }
        
        return ingredient
    }
    
    /// Calculate match score between ingredient and pantry items
    static func calculateMatchScore(ingredient: Ingredient, pantryItems: [(id: UUID, name: String, quantity: Quantity?)]) -> IngredientMatchScore {
        let pantryNames = Set(pantryItems.map { normalize($0.name) })
        let matchResult = isAvailable(ingredient: ingredient.name, in: pantryNames)
        
        // Check if we have enough quantity (if both have quantities)
        var quantityMatch: QuantityMatch = .unknown
        if let neededQty = ingredient.quantity {
            // Find best matching pantry item
            for pantryItem in pantryItems {
                let itemMatchResult = isAvailable(ingredient: ingredient.name, in: [normalize(pantryItem.name)])
                if itemMatchResult != .notFound, let availableQty = pantryItem.quantity {
                    // If same unit, compare quantities
                    if neededQty.unit == availableQty.unit {
                        if availableQty.value >= neededQty.value {
                            quantityMatch = .sufficient
                        } else {
                            quantityMatch = .insufficient(available: availableQty.value, needed: neededQty.value)
                        }
                        break
                    }
                }
            }
        }
        
        return IngredientMatchScore(
            ingredient: ingredient,
            matchResult: matchResult,
            quantityMatch: quantityMatch
        )
    }
    
    enum MatchResult {
        case exact          // Direct match
        case partial        // Substring match
        case synonym        // Known synonym
        case base           // Base ingredient match (e.g., "chicken" matches "chicken breast")
        case notFound       // No match
        
        var isMatch: Bool {
            self != .notFound
        }
        
        var score: Double {
            switch self {
            case .exact: return 1.0
            case .partial: return 0.8
            case .synonym: return 0.9
            case .base: return 0.7
            case .notFound: return 0.0
            }
        }
    }
    
    enum QuantityMatch {
        case sufficient
        case insufficient(available: Double, needed: Double)
        case unknown
        
        var isSufficient: Bool {
            if case .sufficient = self { return true }
            return false
        }
    }
}

struct IngredientMatchScore {
    let ingredient: Ingredient
    let matchResult: IngredientMatcher.MatchResult
    let quantityMatch: IngredientMatcher.QuantityMatch
    
    var isAvailable: Bool {
        matchResult.isMatch
    }
    
    var score: Double {
        var baseScore = matchResult.score
        
        // Adjust for quantity
        if case .insufficient(let available, let needed) = quantityMatch {
            let ratio = available / needed
            baseScore *= ratio
        }
        
        return baseScore
    }
}
