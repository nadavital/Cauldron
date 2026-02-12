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
    private static let mixedUnitPattern = #"^([0-9\s½¼¾⅓⅔⅛⅜⅝⅞/\.\-]+)\s+([a-zA-Z]+[.,]?)\s*(?:plus|and|&|\+)\s*([0-9\s½¼¾⅓⅔⅛⅜⅝⅞/\.\-]+)\s+([a-zA-Z]+[.,]?)\s+(.+)$"#
    private static let rangePattern = #"^([0-9\s½¼¾⅓⅔⅛⅜⅝⅞/\.\-]+)\s*(?:to|-|–|—)\s*([0-9\s½¼¾⅓⅔⅛⅜⅝⅞/\.\-]+)\s+([a-zA-Z]+[.,]?)\s+(.+)$"#

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
        let cleaned = normalizeQuantityUnitSpacing(
            normalizeOCRIngredientText(text.trimmingCharacters(in: .whitespaces))
        )

        if let (quantities, remainingText) = extractComplexQuantities(from: cleaned) {
            let ingredientName = remainingText.trimmingCharacters(in: .whitespacesAndNewlines)
            return Ingredient(
                name: ingredientName.isEmpty ? cleaned : ingredientName,
                quantity: quantities.first,
                additionalQuantities: Array(quantities.dropFirst())
            )
        }

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

    private static func extractComplexQuantities(from text: String) -> ([Quantity], String)? {
        if let mixed = parseMixedUnits(from: text) {
            return mixed
        }
        if let slashAlternatives = parseSlashAlternatives(from: text) {
            return slashAlternatives
        }
        if let ranged = parseRange(from: text) {
            return ranged
        }
        return nil
    }

    private static func normalizeQuantityUnitSpacing(_ text: String) -> String {
        var normalized = text
        normalized = replacing(pattern: #"(?<=\d)(?=[A-Za-z])"#, in: normalized, with: " ")
        normalized = replacing(pattern: #"(?<=[A-Za-z])(?=\d)"#, in: normalized, with: " ")
        normalized = replacing(pattern: #"(?<=[A-Za-z])\s*/\s*(?=\d)"#, in: normalized, with: " / ")
        normalized = replacing(pattern: #"\s+"#, in: normalized, with: " ")
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeOCRIngredientText(_ text: String) -> String {
        var normalized = text
        normalized = replacing(pattern: #"^\s*[•·▪◦●\-–—]+\s*"#, in: normalized, with: "")
        normalized = replacing(pattern: #"^\s*/+\s*(?=(?:\d+\s*/\s*\d+|[½¼¾⅓⅔⅛⅜⅝⅞]))"#, in: normalized, with: "")
        normalized = replacing(pattern: #"(?<![A-Za-z])[Il](?=\s*/\s*\d)"#, in: normalized, with: "1")
        normalized = replacing(pattern: #"(?<![A-Za-z])[oO](?=\s*[.,]?\d)"#, in: normalized, with: "0")
        normalized = replacing(pattern: #"\b[tT][bB]\s*5\s*[pP]\b"#, in: normalized, with: "tbsp")
        normalized = replacing(pattern: #"\b[tT]\s*5\s*[pP]\b"#, in: normalized, with: "tsp")
        normalized = replacing(pattern: #"\b[1iI][bB]\b"#, in: normalized, with: "lb")
        return normalized
    }

    private static func replacing(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func parseMixedUnits(from text: String) -> ([Quantity], String)? {
        guard let match = firstMatch(pattern: mixedUnitPattern, text: text),
              match.count == 6 else {
            return nil
        }

        let firstQuantityText = match[1].trimmingCharacters(in: .whitespaces)
        let firstUnitText = match[2].trimmingCharacters(in: .whitespaces)
        let secondQuantityText = match[3].trimmingCharacters(in: .whitespaces)
        let secondUnitText = match[4].trimmingCharacters(in: .whitespaces)
        let ingredientName = match[5].trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstValue = QuantityValueParser.parse(firstQuantityText),
              let secondValue = QuantityValueParser.parse(secondQuantityText),
              let firstUnit = UnitParser.parse(firstUnitText),
              let secondUnit = UnitParser.parse(secondUnitText),
              !ingredientName.isEmpty else {
            return nil
        }

        let firstQuantity = Quantity(value: firstValue, unit: firstUnit)
        let secondQuantity = Quantity(value: secondValue, unit: secondUnit)
        return ([firstQuantity, secondQuantity], ingredientName)
    }

    private static func parseRange(from text: String) -> ([Quantity], String)? {
        guard let match = firstMatch(pattern: rangePattern, text: text),
              match.count == 5 else {
            return nil
        }

        let lowerText = match[1].trimmingCharacters(in: .whitespaces)
        let upperText = match[2].trimmingCharacters(in: .whitespaces)
        let unitText = match[3].trimmingCharacters(in: .whitespaces)
        let ingredientName = match[4].trimmingCharacters(in: .whitespacesAndNewlines)

        guard let lowerValue = QuantityValueParser.parse(lowerText),
              let upperValue = QuantityValueParser.parse(upperText),
              !ingredientName.isEmpty else {
            return nil
        }

        var finalUnit = UnitParser.parse(unitText)
        var finalName = ingredientName
        if finalUnit == nil {
            // Handle forms like "3 to 4 garlic cloves" where the unit is the next token.
            let tailParts = ingredientName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let secondToken = tailParts.first,
               let secondUnit = UnitParser.parse(String(secondToken)) {
                let remainder = tailParts.count > 1 ? String(tailParts[1]) : ""
                finalName = "\(unitText) \(remainder)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                finalUnit = secondUnit
            } else {
                finalName = "\(unitText) \(ingredientName)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                finalUnit = .whole
            }
        }
        guard !finalName.isEmpty, let unit = finalUnit else {
            return nil
        }

        let minValue = min(lowerValue, upperValue)
        let maxValue = max(lowerValue, upperValue)
        let quantity = Quantity(value: minValue, upperValue: maxValue, unit: unit)
        return ([quantity], finalName)
    }

    private static func parseSlashAlternatives(from text: String) -> ([Quantity], String)? {
        guard text.contains("/") else {
            return nil
        }

        let tokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard tokens.count >= 4 else {
            return nil
        }

        var prefixTokens: [String] = []
        var splitIndex = 0
        for (index, token) in tokens.enumerated() {
            if isQuantityPrefixToken(token) {
                prefixTokens.append(token)
                splitIndex = index + 1
                continue
            }
            break
        }

        guard !prefixTokens.isEmpty,
              prefixTokens.contains("/"),
              splitIndex < tokens.count else {
            return nil
        }

        let ingredientName = tokens[splitIndex...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ingredientName.isEmpty else {
            return nil
        }

        let prefixText = prefixTokens.joined(separator: " ")
        let segments = prefixText
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard segments.count >= 2 else {
            return nil
        }

        var quantities: [Quantity] = []
        for segment in segments {
            let parsed = parseQuantitySegment(segment)
            if parsed.isEmpty {
                return nil
            }
            quantities.append(contentsOf: parsed)
        }

        guard !quantities.isEmpty else {
            return nil
        }

        return (quantities, ingredientName)
    }

    private static func isQuantityPrefixToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        if trimmed == "/" {
            return true
        }
        let punctuation = CharacterSet(charactersIn: "[]{}()<>.,:;!?\"'")
        let cleaned = trimmed.trimmingCharacters(in: punctuation)
        guard !cleaned.isEmpty else {
            return false
        }
        if QuantityValueParser.parse(cleaned) != nil {
            return true
        }
        return UnitParser.parse(cleaned) != nil
    }

    private static func parseQuantitySegment(_ segment: String) -> [Quantity] {
        let tokens = segment
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else {
            return []
        }

        var index = 0
        var quantities: [Quantity] = []
        while index < tokens.count {
            var value: Double?
            var consumed = 0

            if index + 1 < tokens.count {
                let secondToken = tokens[index + 1]
                if UnitParser.parse(secondToken) == nil {
                    let mixedCandidate = "\(tokens[index]) \(secondToken)"
                    if let mixedValue = QuantityValueParser.parse(mixedCandidate) {
                        value = mixedValue
                        consumed = 2
                    }
                }
            }

            if value == nil {
                guard let singleValue = QuantityValueParser.parse(tokens[index]) else {
                    break
                }
                value = singleValue
                consumed = 1
            }

            index += consumed

            var unit: UnitKind = .whole
            if index < tokens.count, let parsedUnit = UnitParser.parse(tokens[index]) {
                unit = parsedUnit
                index += 1
            }

            if let value {
                quantities.append(Quantity(value: value, unit: unit))
            }
        }

        return quantities
    }

    private static func firstMatch(pattern: String, text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let matchRange = match.range(at: index)
            if matchRange.location == NSNotFound {
                groups.append("")
            } else {
                groups.append(nsString.substring(with: matchRange))
            }
        }
        return groups
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
        let pattern = #"^([\d\s½¼¾⅓⅔⅛⅜⅝⅞/-]+)\s*([a-zA-Z]+[.,]?)?\s+"#

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
            if let parsedUnit = UnitParser.parse(unitText) {
                unit = parsedUnit
                remainingStartIndex = unitRange.upperBound
            } else {
                // Handle forms like "3 garlic cloves" where second token is the unit.
                let tailText = nsString.substring(from: unitRange.upperBound).trimmingCharacters(in: .whitespacesAndNewlines)
                let tailParts = tailText.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if let secondToken = tailParts.first,
                   let secondUnit = UnitParser.parse(String(secondToken)) {
                    let remainder = tailParts.count > 1 ? String(tailParts[1]) : ""
                    let ingredientName = "\(unitText) \(remainder)"
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let quantity = Quantity(value: value, unit: secondUnit)
                    return (quantity, ingredientName)
                }

                // Token after quantity is part of the ingredient name, not a unit.
                remainingStartIndex = quantityRange.upperBound
            }
        }

        let remainingText = nsString.substring(from: remainingStartIndex)
        // Default to `.whole` when no explicit unit is parsed (e.g., "2 eggs")
        let quantity = Quantity(value: value, unit: unit ?? .whole)

        return (quantity, remainingText)
    }
}
