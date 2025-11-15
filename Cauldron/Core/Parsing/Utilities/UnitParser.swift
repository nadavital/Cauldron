//
//  UnitParser.swift
//  Cauldron
//
//  Created on November 13, 2025.
//

import Foundation

/// Parses cooking unit abbreviations and variations
///
/// Supports common abbreviations like "tsp", "tbsp", "cup", "oz", "lb", "g", "kg", "ml", "l", etc.
/// Also handles full names and plural forms.
struct UnitParser {

    /// Common unit abbreviations and variations mapped to UnitKind
    private static let abbreviationMap: [String: UnitKind] = [
        // Teaspoon
        "t": .teaspoon,
        "tsp": .teaspoon,
        "tsps": .teaspoon,
        "teaspoon": .teaspoon,
        "teaspoons": .teaspoon,

        // Tablespoon (note: both "t" and "T" lowercase to "t", so we need context or longer form)
        // Since we lowercase everything, we can't distinguish "T" from "t"
        // Using "tbsp" is preferred for tablespoon
        "tbsp": .tablespoon,
        "tbsps": .tablespoon,
        "tablespoon": .tablespoon,
        "tablespoons": .tablespoon,

        // Cup
        "c": .cup,
        "cup": .cup,
        "cups": .cup,

        // Ounce
        "oz": .ounce,
        "ounce": .ounce,
        "ounces": .ounce,

        // Pound
        "lb": .pound,
        "lbs": .pound,
        "pound": .pound,
        "pounds": .pound,

        // Gram
        "g": .gram,
        "gram": .gram,
        "grams": .gram,

        // Kilogram
        "kg": .kilogram,
        "kgs": .kilogram,
        "kilogram": .kilogram,
        "kilograms": .kilogram,

        // Milliliter
        "ml": .milliliter,
        "mls": .milliliter,
        "milliliter": .milliliter,
        "milliliters": .milliliter,

        // Liter
        "l": .liter,
        "liter": .liter,
        "liters": .liter,

        // Pint
        "pt": .pint,
        "pts": .pint,
        "pint": .pint,
        "pints": .pint,

        // Quart
        "qt": .quart,
        "qts": .quart,
        "quart": .quart,
        "quarts": .quart,

        // Gallon
        "gal": .gallon,
        "gals": .gallon,
        "gallon": .gallon,
        "gallons": .gallon,

        // Fluid Ounce
        "fl oz": .fluidOunce,
        "floz": .fluidOunce,
        "fluid ounce": .fluidOunce,
        "fluid ounces": .fluidOunce
    ]

    /// Parse unit from text abbreviation or name
    ///
    /// - Parameter text: The text to parse (e.g., "tsp", "tablespoon", "cups")
    /// - Returns: The corresponding UnitKind, or nil if not recognized
    ///
    /// Examples:
    /// ```swift
    /// UnitParser.parse("tsp")         // .teaspoon
    /// UnitParser.parse("tablespoon")  // .tablespoon
    /// UnitParser.parse("cups")        // .cup
    /// UnitParser.parse("oz")          // .ounce
    /// ```
    static func parse(_ text: String) -> UnitKind? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Special case: "T" (capital) means tablespoon, "t" (lowercase) means teaspoon
        if trimmed == "T" {
            return .tablespoon
        }

        let normalized = trimmed.lowercased()

        // Try exact matches against UnitKind enum cases
        for unit in UnitKind.allCases {
            if normalized == unit.rawValue ||
               normalized == unit.displayName ||
               normalized == unit.pluralName {
                return unit
            }
        }

        // Try abbreviation map
        return abbreviationMap[normalized]
    }
}
