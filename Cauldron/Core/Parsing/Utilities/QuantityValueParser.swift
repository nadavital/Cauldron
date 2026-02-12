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
        cleaned = normalizeOCRNumericText(cleaned)

        // OCR occasionally collapses mixed numbers: "1 1/2" -> "11/2".
        if let mergedMixed = parseMergedMixedFraction(cleaned) {
            return mergedMixed
        }

        // Support mixed unicode fractions with optional missing space: "2¼", "2 ¼".
        if let mixedUnicode = parseMixedUnicodeFraction(cleaned) {
            return mixedUnicode
        }

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

    private static func parseMixedUnicodeFraction(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"^(\d+)\s*([½¼¾⅓⅔⅛⅜⅝⅞])$"#, options: []) else {
            return nil
        }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 3 else {
            return nil
        }

        let wholeText = nsString.substring(with: match.range(at: 1))
        let fractionUnicode = nsString.substring(with: match.range(at: 2))
        guard let whole = Double(wholeText),
              let decimalText = unicodeFractions[fractionUnicode],
              let fraction = Double(decimalText) else {
            return nil
        }
        return whole + fraction
    }

    private static func parseMergedMixedFraction(_ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"^([1-9])([1-9])/(\d{1,2})$"#, options: []) else {
            return nil
        }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 4 else {
            return nil
        }

        let wholeText = nsString.substring(with: match.range(at: 1))
        let numeratorText = nsString.substring(with: match.range(at: 2))
        let denominatorText = nsString.substring(with: match.range(at: 3))
        guard let whole = Double(wholeText),
              let numerator = Double(numeratorText),
              let denominator = Double(denominatorText),
              denominator != 0 else {
            return nil
        }

        let commonDenominators: Set<Double> = [2, 3, 4, 8, 16]
        guard commonDenominators.contains(denominator),
              numerator < denominator else {
            return nil
        }

        return whole + (numerator / denominator)
    }

    private static func normalizeOCRNumericText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")

        let replacements: [(pattern: String, replacement: String)] = [
            (#"^/\s*(?=\d+\s*/\s*\d+|[½¼¾⅓⅔⅛⅜⅝⅞])"#, ""),
            (#"([½¼¾⅓⅔⅛⅜⅝⅞])\d+\b"#, "$1"),
            (#"(?<![A-Za-z])[oO](?=\d)"#, "0"),
            (#"(?<=\d)[oO](?=\d|/|\b)"#, "0"),
            (#"(?<![A-Za-z])[Il](?=\d|/|\.|\b)"#, "1"),
            (#"(?<=\d)[Il](?=\d|/|\.|\b)"#, "1"),
            (#"(?<=\d),(?=\d)"#, "."),
        ]

        for (pattern, replacement) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(in: normalized, options: [], range: range, withTemplate: replacement)
        }

        return normalized
    }
}
