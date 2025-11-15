//
//  IngredientParser.swift
//  Cauldron
//
//  Created on November 13, 2025.
//

import Foundation

/// Parses ingredient text into structured Ingredient objects
///
/// Handles various ingredient formats:
/// - "2 cups flour" → Ingredient(quantity: 2 cups, name: "flour")
/// - "1/2 tsp salt" → Ingredient(quantity: 0.5 tsp, name: "salt")
/// - "Salt to taste" → Ingredient(quantity: nil, name: "Salt to taste")
struct IngredientParser {

    /// Parse ingredient text into structured Ingredient
    ///
    /// - Parameter text: The ingredient text to parse
    /// - Returns: An Ingredient with parsed quantity/unit and name
    ///
    /// Examples:
    /// ```swift
    /// IngredientParser.parseIngredientText("2 cups flour")
    /// // Ingredient(quantity: Quantity(value: 2, unit: .cup), name: "flour")
    ///
    /// IngredientParser.parseIngredientText("Salt to taste")
    /// // Ingredient(quantity: nil, name: "Salt to taste")
    /// ```
    static func parseIngredientText(_ text: String) -> Ingredient {
        let cleaned = text.trimmingCharacters(in: .whitespaces)

        // Try to parse quantity and unit from the beginning of the string
        if let (quantity, remainingText) = extractQuantityAndUnit(from: cleaned) {
            let ingredientName = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
            return Ingredient(
                name: ingredientName.isEmpty ? cleaned : ingredientName,
                quantity: quantity
            )
        }

        // If parsing fails, return the whole text as ingredient name (no quantity)
        return Ingredient(name: cleaned, quantity: nil)
    }

    /// Extract quantity and unit from beginning of text
    ///
    /// - Parameter text: The text to parse
    /// - Returns: A tuple of (Quantity, remainingText), or nil if no quantity found
    ///
    /// This method extracts the quantity value and unit from the start of the ingredient text,
    /// leaving the remaining text as the ingredient name/description.
    ///
    /// Examples:
    /// ```swift
    /// extractQuantityAndUnit(from: "2 cups flour")
    /// // (Quantity(value: 2, unit: .cup), "flour")
    ///
    /// extractQuantityAndUnit(from: "1/2 tsp salt, divided")
    /// // (Quantity(value: 0.5, unit: .teaspoon), "salt, divided")
    /// ```
    static func extractQuantityAndUnit(from text: String) -> (Quantity, String)? {
        // Pattern to match quantity at the start: number (possibly with fraction or unicode fraction)
        // followed by optional unit
        // Examples: "2 cups", "1/2 cup", "1 ½ cups", "2½ tablespoons", "200g", "1-2 teaspoons"
        let pattern = #"^([\d\s½¼¾⅓⅔⅛⅜⅝⅞/-]+)\s*([a-zA-Z]+)?\s+"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let nsString = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }

        // Extract quantity text
        let quantityRange = match.range(at: 1)
        let quantityText = nsString.substring(with: quantityRange).trimmingCharacters(in: .whitespaces)

        // Parse the quantity value
        guard let value = QuantityValueParser.parse(quantityText) else {
            return nil
        }

        // Parse the unit if present
        var unit: UnitKind? = nil
        var remainingStartIndex = quantityRange.upperBound

        if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
            let unitRange = match.range(at: 2)
            let unitText = nsString.substring(with: unitRange)
            unit = UnitParser.parse(unitText)
            remainingStartIndex = unitRange.upperBound
        }

        let remainingText = nsString.substring(from: remainingStartIndex)
        // Default to `.whole` when no explicit unit is parsed (e.g., "2 eggs")
        let quantity = Quantity(value: value, unit: unit ?? .whole)

        return (quantity, remainingText)
    }
}
