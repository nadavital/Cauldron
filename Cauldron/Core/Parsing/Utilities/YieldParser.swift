//
//  YieldParser.swift
//  Cauldron
//
//  Created on January 25, 2026.
//

import Foundation

/// Extracts serving/yield information from recipe text
///
/// Handles patterns like:
/// - "Serves 4", "Serves 4-6", "Serves: 4"
/// - "Makes 12 cookies", "Makes about 2 cups"
/// - "Yields 6", "Yield: 1 loaf"
/// - "Recipe for 8 people", "For 4 servings"
struct YieldParser {

    /// Common yield patterns with named capture groups
    private static let yieldPatterns: [(pattern: String, format: String)] = [
        // "Serves 4" or "Serves: 4" or "Serves 4-6" or "Serves 4 to 6"
        (#"(?i)\bserves?\s*:?\s*(\d+(?:\s*[-–to]+\s*\d+)?)\b"#, "{number} servings"),

        // "Servings: 4" or "4 servings"
        (#"(?i)\bservings?\s*:?\s*(\d+(?:\s*[-–to]+\s*\d+)?)\b"#, "{number} servings"),
        (#"(?i)(\d+(?:\s*[-–to]+\s*\d+)?)\s+servings?\b"#, "{number} servings"),

        // "Makes 12 cookies" or "Makes about 24 muffins" or "Makes 24 standard cupcakes"
        // Skip common adjectives (standard, small, large, medium, mini, regular, jumbo) to capture the noun
        (#"(?i)\bmakes?\s+(?:about\s+)?(\d+(?:\s*[-–to]+\s*\d+)?)\s+(?:(?:standard|small|medium|large|mini|regular|jumbo|big|little)\s+)?(\w+)"#, "{number} {unit}"),

        // "Yields 6" or "Yield: 6"
        (#"(?i)\byields?\s*:?\s*(\d+(?:\s*[-–to]+\s*\d+)?)\s*(\w*)"#, "{number} {unit}"),

        // "Recipe for 8" or "For 4 people"
        (#"(?i)\b(?:recipe\s+)?for\s+(\d+(?:\s*[-–to]+\s*\d+)?)\s*(?:people|persons?)?\b"#, "{number} servings"),

        // "Portions: 6" or "4 portions"
        (#"(?i)\bportions?\s*:?\s*(\d+(?:\s*[-–to]+\s*\d+)?)\b"#, "{number} portions"),
        (#"(?i)(\d+(?:\s*[-–to]+\s*\d+)?)\s+portions?\b"#, "{number} portions"),

        // "1 loaf", "2 dozen", "3 batches" (standalone yield descriptions)
        (#"(?i)^(\d+(?:\s*[-–to]+\s*\d+)?)\s+(loaf|loaves|dozen|batch|batches|cups?|pounds?|lbs?)\b"#, "{number} {unit}")
    ]

    /// Extract yield from a single line of text
    ///
    /// - Parameter text: The text to search
    /// - Returns: The formatted yield string, or nil if not found
    ///
    /// Examples:
    /// ```swift
    /// YieldParser.extractYield(from: "Serves 4")
    /// // "4 servings"
    ///
    /// YieldParser.extractYield(from: "Makes about 24 cookies")
    /// // "24 cookies"
    /// ```
    static func extractYield(from text: String) -> String? {
        for (pattern, format) in yieldPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let nsString = text as NSString
            let range = NSRange(location: 0, length: nsString.length)

            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges >= 2 else {
                continue
            }

            // Extract the number
            let numberRange = match.range(at: 1)
            var number = nsString.substring(with: numberRange)

            // Normalize range separators
            number = number.replacingOccurrences(of: " to ", with: "-")
            number = number.replacingOccurrences(of: "–", with: "-")
            number = number.replacingOccurrences(of: "  ", with: " ")
            number = number.trimmingCharacters(in: .whitespaces)

            // Extract the unit if present
            var unit = "servings"
            if match.numberOfRanges >= 3 {
                let unitRange = match.range(at: 2)
                if unitRange.location != NSNotFound {
                    let extractedUnit = nsString.substring(with: unitRange)
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    if !extractedUnit.isEmpty {
                        unit = normalizeUnit(extractedUnit)
                    }
                }
            }

            // Build result string
            var result = format
            result = result.replacingOccurrences(of: "{number}", with: number)
            result = result.replacingOccurrences(of: "{unit}", with: unit)
            result = result.trimmingCharacters(in: .whitespaces)

            // Clean up double spaces and trailing servings if empty
            result = result.replacingOccurrences(of: "  ", with: " ")
            if result.hasSuffix(" ") {
                result = result.trimmingCharacters(in: .whitespaces)
            }

            return result.isEmpty ? nil : result
        }

        return nil
    }

    /// Extract yield by searching through multiple lines
    ///
    /// - Parameter lines: Array of text lines to search
    /// - Returns: The formatted yield string, or nil if not found
    ///
    /// Searches lines for common yield patterns and returns the first match.
    static func extractYieldFromLines(_ lines: [String]) -> String? {
        // First, look for dedicated yield lines (more reliable)
        let yieldLineKeywords = ["serves", "servings", "yield", "makes", "portions", "for "]

        for line in lines {
            let lowercased = line.lowercased()

            // Check if line starts with or contains yield keywords
            for keyword in yieldLineKeywords {
                if lowercased.contains(keyword) {
                    if let yield = extractYield(from: line) {
                        return yield
                    }
                }
            }
        }

        // Fallback: search all lines
        for line in lines {
            if let yield = extractYield(from: line) {
                return yield
            }
        }

        return nil
    }

    /// Normalize unit names for consistency
    private static func normalizeUnit(_ unit: String) -> String {
        switch unit.lowercased() {
        case "loaf": return "loaf"
        case "loaves": return "loaves"
        case "cookie", "cookies": return "cookies"
        case "muffin", "muffins": return "muffins"
        case "cupcake", "cupcakes": return "cupcakes"
        case "pancake", "pancakes": return "pancakes"
        case "serving", "servings": return "servings"
        case "portion", "portions": return "portions"
        case "piece", "pieces": return "pieces"
        case "slice", "slices": return "slices"
        case "roll", "rolls": return "rolls"
        case "dozen": return "dozen"
        case "batch", "batches": return "batches"
        case "cup", "cups": return "cups"
        case "pound", "pounds", "lb", "lbs": return "pounds"
        case "people", "person", "persons": return "servings"
        default: return unit.isEmpty ? "servings" : unit
        }
    }
}
