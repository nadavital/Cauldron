//
//  QuantityTextParser.swift
//  Cauldron
//
//  Parses user-entered quantity text (decimals, fractions, mixed numbers, and
//  ranges) into numeric values. Extracted from RecipeEditorViewModel so it can
//  be reused and unit-tested independently of the editor UI.
//

import Foundation

enum QuantityTextParser {
    /// Parse quantity text into a value and optional upper bound (for ranges).
    /// Examples: "2" → (2, nil); "1/2" → (0.5, nil); "1 1/2" → (1.5, nil);
    /// "1-2" → (1, 2). Returns nil for empty or unparseable input.
    static func parse(_ rawText: String) -> (value: Double, upperValue: Double?)? {
        let trimmed = rawText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Range: "1-2" or "1 - 2"
        if trimmed.contains("-") {
            let components = trimmed.components(separatedBy: "-")
            if components.count == 2,
               let lower = parseSingleValue(components[0]),
               let upper = parseSingleValue(components[1]) {
                return (lower, upper)
            }
        }

        // Single value
        if let val = parseSingleValue(trimmed) {
            return (val, nil)
        }

        return nil
    }

    private static func parseSingleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // Fractions like "1/2", "1/4", "2/3"
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            if parts.count == 2,
               let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               denominator != 0 {
                return numerator / denominator
            }
        }

        // Mixed numbers like "1 1/2"
        if trimmed.contains(" ") {
            let parts = trimmed.split(separator: " ")
            if parts.count == 2,
               let whole = Double(parts[0].trimmingCharacters(in: .whitespaces)) {
                let fractionPart = String(parts[1].trimmingCharacters(in: .whitespaces))
                if fractionPart.contains("/") {
                    let fracParts = fractionPart.split(separator: "/")
                    if fracParts.count == 2,
                       let numerator = Double(fracParts[0].trimmingCharacters(in: .whitespaces)),
                       let denominator = Double(fracParts[1].trimmingCharacters(in: .whitespaces)),
                       denominator != 0 {
                        return whole + (numerator / denominator)
                    }
                }
            }
        }

        // Regular decimals
        return Double(trimmed)
    }
}
