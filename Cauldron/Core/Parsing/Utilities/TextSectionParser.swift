//
//  TextSectionParser.swift
//  Cauldron
//
//  Created on November 13, 2025.
//

import Foundation

/// Utilities for parsing structured text sections
///
/// Helps detect:
/// - Numbered steps (1., 2), Step 3:, etc.)
/// - Ingredient-like lines (starting with quantities)
/// - Section headers (Ingredients, Instructions, etc.)
struct TextSectionParser {

    // MARK: - Step Detection

    /// Check if a line looks like a numbered step
    ///
    /// - Parameter line: The text line to check
    /// - Returns: True if the line appears to be a numbered step
    ///
    /// Recognizes patterns like:
    /// - "1. Mix ingredients"
    /// - "2) Beat eggs"
    /// - "3 - Preheat oven"
    /// - "4: Bake for 20 minutes"
    /// - "Step 5. Cool completely"
    ///
    /// Examples:
    /// ```swift
    /// TextSectionParser.looksLikeNumberedStep("1. Mix ingredients")  // true
    /// TextSectionParser.looksLikeNumberedStep("Mix ingredients")     // false
    /// TextSectionParser.looksLikeNumberedStep("1.")                  // false (too short)
    /// ```
    static func looksLikeNumberedStep(_ line: String) -> Bool {
        // Match patterns like: "1.", "2)", "3 -", "4:", "Step 5.", etc.
        let patterns = [
            #"^\d+\.\s+"#,           // "1. Mix ingredients"
            #"^\d+\)\s+"#,           // "1) Mix ingredients"
            #"^\d+\s+-\s+"#,         // "1 - Mix ingredients"
            #"^\d+:\s+"#,            // "1: Mix ingredients"
            #"^Step\s+\d+[.):]\s+"#  // "Step 1. Mix ingredients"
        ]

        for pattern in patterns {
            if line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                // Make sure it has some content after the number (not just "1.")
                return line.count > 5
            }
        }

        return false
    }

    // MARK: - Ingredient Detection

    /// Check if a line looks like an ingredient (starts with quantity)
    ///
    /// - Parameter line: The text line to check
    /// - Returns: True if the line appears to start with a quantity
    ///
    /// Recognizes lines starting with:
    /// - Numbers (2 cups, 1.5 tsp)
    /// - Fractions (1/2, 3/4)
    /// - Unicode fractions (½, ¼)
    ///
    /// Examples:
    /// ```swift
    /// TextSectionParser.looksLikeIngredient("2 cups flour")      // true
    /// TextSectionParser.looksLikeIngredient("½ tsp salt")        // true
    /// TextSectionParser.looksLikeIngredient("Salt to taste")     // false
    /// ```
    static func looksLikeIngredient(_ line: String) -> Bool {
        // Empty or whitespace-only lines are not ingredients
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return false
        }

        let pattern = #"^[\d\s½¼¾⅓⅔⅛⅜⅝⅞/-]+"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Section Header Detection

    /// Detect if line is an ingredient section header
    ///
    /// - Parameter line: The text line to check
    /// - Returns: True if the line appears to be an ingredients section header
    ///
    /// Recognizes headers like:
    /// - "Ingredients"
    /// - "Ingredients:"
    /// - "For the dough:"
    ///
    /// Examples:
    /// ```swift
    /// TextSectionParser.isIngredientSectionHeader("Ingredients")       // true
    /// TextSectionParser.isIngredientSectionHeader("Ingredients:")      // true
    /// TextSectionParser.isIngredientSectionHeader("2 cups flour")      // false
    /// ```
    static func isIngredientSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        // Must contain "ingredient" and be relatively short (not a full sentence)
        return lowercased.contains("ingredient") && lowercased.count < 50
    }

    /// Detect if line is a steps/instructions section header
    ///
    /// - Parameter line: The text line to check
    /// - Returns: True if the line appears to be a steps section header
    ///
    /// Recognizes headers like:
    /// - "Instructions"
    /// - "Directions"
    /// - "Method"
    /// - "How to make"
    /// - "Preparation"
    /// - "Steps"
    ///
    /// Examples:
    /// ```swift
    /// TextSectionParser.isStepsSectionHeader("Instructions")        // true
    /// TextSectionParser.isStepsSectionHeader("Directions:")         // true
    /// TextSectionParser.isStepsSectionHeader("How to make")         // true
    /// TextSectionParser.isStepsSectionHeader("Mix ingredients")     // false
    /// ```
    static func isStepsSectionHeader(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        // First check: if this looks like a numbered step, it's NOT a header
        if looksLikeNumberedStep(line) {
            return false
        }

        // Check for common section header keywords
        let keywords = [
            "instruction",
            "direction",
            "method",
            "how to",
            "preparation"
        ]

        for keyword in keywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        // Check for "step" but only if it's a short line (likely a header, not "Step 1. Mix...")
        if lowercased.contains("step") && lowercased.count < 50 {
            return true
        }

        return false
    }
}
