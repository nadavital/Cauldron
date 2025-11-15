//
//  QuantityValueParser.swift
//  Cauldron
//
//  Created on November 13, 2025.
//

import Foundation

/// Parses quantity values from text (fractions, decimals, ranges, mixed numbers, unicode fractions)
///
/// Supports various formats:
/// - Decimals: "2.5"
/// - Simple fractions: "1/2", "3/4"
/// - Mixed numbers: "1 1/2", "2 3/4"
/// - Unicode fractions: "½", "¼", "¾", "⅓", "⅔", "⅛", "⅜", "⅝", "⅞"
/// - Ranges: "1-2" (returns average)
struct QuantityValueParser {

    /// Unicode fraction to decimal mappings
    private static let unicodeFractions: [String: String] = [
        "½": "0.5",
        "¼": "0.25",
        "¾": "0.75",
        "⅓": "0.333",
        "⅔": "0.667",
        "⅛": "0.125",
        "⅜": "0.375",
        "⅝": "0.625",
        "⅞": "0.875"
    ]

    /// Parse quantity value from text
    ///
    /// - Parameter text: The text to parse (e.g., "1/2", "1 1/2", "½", "2.5", "1-2")
    /// - Returns: The numeric value, or nil if parsing fails
    ///
    /// Examples:
    /// ```swift
    /// QuantityValueParser.parse("1/2")     // 0.5
    /// QuantityValueParser.parse("1 1/2")   // 1.5
    /// QuantityValueParser.parse("½")       // 0.5
    /// QuantityValueParser.parse("2.5")     // 2.5
    /// QuantityValueParser.parse("1-2")     // 1.5 (average)
    /// ```
    static func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)

        // Convert unicode fractions to decimal
        for (unicode, decimal) in unicodeFractions {
            cleaned = cleaned.replacingOccurrences(of: unicode, with: decimal)
        }

        // Handle ranges like "1-2" - take the average
        if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
            if parts.count == 2,
               let first = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let second = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                return (first + second) / 2
            }
        }

        // Handle fractions like "1/2"
        if cleaned.contains("/") {
            let parts = cleaned.components(separatedBy: "/")
            if parts.count == 2,
               let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               denominator != 0 {
                return numerator / denominator
            }
        }

        // Handle mixed numbers like "1 1/2"
        let components = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if components.count == 2 {
            if let whole = Double(components[0]),
               let fraction = parse(components[1]) {  // Recursive call for the fraction part
                return whole + fraction
            }
        }

        // Try direct conversion
        return Double(cleaned)
    }
}
