//
//  RecipeParser.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Protocol for recipe parsing
protocol RecipeParser {
    func parse(from source: String) async throws -> Recipe
}

/// Errors that can occur during parsing
enum ParsingError: Error, LocalizedError {
    case invalidSource
    case noIngredientsFound
    case noStepsFound
    case networkError(Error)
    case decodingError(Error)
    case platformNotSupported(String)
    case invalidURL
    case invalidHTML
    case noRecipeFound
    case imageNotFound

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "Invalid recipe source"
        case .noIngredientsFound:
            return "No ingredients found in recipe"
        case .noStepsFound:
            return "No cooking steps found in recipe"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode recipe: \(error.localizedDescription)"
        case .platformNotSupported(let platform):
            return "\(platform) recipe import is not yet supported. Try copying the recipe text manually."
        case .invalidURL:
            return "Invalid URL. Please check the URL and try again."
        case .invalidHTML:
            return "Could not read content from URL"
        case .noRecipeFound:
            return "No recipe found in the video description. Make sure the video contains a recipe in its description."
        case .imageNotFound:
            return "Could not find recipe image"
        }
    }
}

/// Helper for extracting timers from step text
struct TimerExtractor {

    /// Context keywords that indicate timer purpose
    private static let labelKeywords: [(keywords: [String], label: String)] = [
        (["rest", "resting"], "Rest"),
        (["chill", "chilling", "refrigerate", "refrigerating", "cool", "cooling"], "Chill"),
        (["rise", "rising", "proof", "proofing", "ferment"], "Rise"),
        (["marinate", "marinating", "marinade"], "Marinate"),
        (["simmer", "simmering"], "Simmer"),
        (["boil", "boiling"], "Boil"),
        (["bake", "baking"], "Bake"),
        (["roast", "roasting"], "Roast"),
        (["fry", "frying", "sauté", "saute", "sautéing"], "Fry"),
        (["grill", "grilling"], "Grill"),
        (["steam", "steaming"], "Steam"),
        (["soak", "soaking"], "Soak"),
        (["freeze", "freezing"], "Freeze"),
        (["thaw", "thawing"], "Thaw"),
        (["wait", "waiting", "let sit", "sit for", "stand"], "Wait"),
        (["set", "setting"], "Set"),
        (["brown", "browning"], "Brown"),
        (["toast", "toasting"], "Toast"),
        (["blend", "blending"], "Blend"),
        (["knead", "kneading"], "Knead")
    ]

    /// Extract ALL timer specifications from text
    ///
    /// - Parameter text: The step text to analyze
    /// - Returns: Array of TimerSpec for each time reference found
    ///
    /// Examples:
    /// ```swift
    /// TimerExtractor.extractTimers(from: "Cook for 5 minutes, then rest for 10 minutes")
    /// // [TimerSpec(5 min, "Cook"), TimerSpec(10 min, "Rest")]
    /// ```
    static func extractTimers(from text: String) -> [TimerSpec] {
        var timers: [TimerSpec] = []
        let lowercased = text.lowercased()

        // Extract all time references with their positions
        var timeMatches: [(value: Int, unit: TimeUnit, range: Range<String.Index>)] = []

        // Pattern: X minutes/mins/min
        let minutePattern = #"(\d+)\s*(minutes?|mins?)\b"#
        timeMatches.append(contentsOf: findAllMatches(pattern: minutePattern, in: lowercased, unit: .minutes))

        // Pattern: X hours/hrs/hr
        let hourPattern = #"(\d+)\s*(hours?|hrs?)\b"#
        timeMatches.append(contentsOf: findAllMatches(pattern: hourPattern, in: lowercased, unit: .hours))

        // Pattern: X seconds/secs/sec
        let secondPattern = #"(\d+)\s*(seconds?|secs?)\b"#
        timeMatches.append(contentsOf: findAllMatches(pattern: secondPattern, in: lowercased, unit: .seconds))

        // Sort by position in text
        timeMatches.sort { $0.range.lowerBound < $1.range.lowerBound }

        // Convert to TimerSpecs with inferred labels
        for (index, match) in timeMatches.enumerated() {
            let label = inferLabel(for: match.range, in: lowercased, index: index, totalCount: timeMatches.count)

            let timer: TimerSpec
            switch match.unit {
            case .seconds:
                timer = TimerSpec(seconds: match.value, label: label)
            case .minutes:
                timer = .minutes(match.value, label: label)
            case .hours:
                timer = .hours(match.value, label: label)
            }

            timers.append(timer)
        }

        return timers
    }

    private enum TimeUnit {
        case seconds, minutes, hours
    }

    /// Find all regex matches in text
    private static func findAllMatches(
        pattern: String,
        in text: String,
        unit: TimeUnit
    ) -> [(value: Int, unit: TimeUnit, range: Range<String.Index>)] {
        var results: [(value: Int, unit: TimeUnit, range: Range<String.Index>)] = []

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return results
        }

        let nsString = text as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let matches = regex.matches(in: text, range: fullRange)

        for match in matches {
            guard match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range(at: 0), in: text),
                  let value = Int(text[valueRange]) else {
                continue
            }

            results.append((value: value, unit: unit, range: fullRange))
        }

        return results
    }

    /// Infer the label for a timer based on surrounding context
    private static func inferLabel(
        for range: Range<String.Index>,
        in text: String,
        index: Int,
        totalCount: Int
    ) -> String {
        // Get context BEFORE the time reference (most relevant for identifying the action)
        let contextStart = text.index(range.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
        let contextBefore = String(text[contextStart..<range.lowerBound])

        // First, check context before the timer (highest priority)
        for (keywords, label) in labelKeywords {
            for keyword in keywords {
                if contextBefore.contains(keyword) {
                    return label
                }
            }
        }

        // If no match in context before, check a bit after for cases like "10 minutes rest"
        let contextEnd = text.index(range.upperBound, offsetBy: 20, limitedBy: text.endIndex) ?? text.endIndex
        let contextAfter = String(text[range.upperBound..<contextEnd])

        for (keywords, label) in labelKeywords {
            for keyword in keywords {
                if contextAfter.contains(keyword) {
                    return label
                }
            }
        }

        // Default based on position
        if totalCount > 1 && index == totalCount - 1 {
            // Last timer in multi-timer step - often "rest" or "let sit"
            if contextBefore.contains("then") || contextBefore.contains("after") {
                return "Rest"
            }
        }

        return "Cook"
    }
}

/// Helper for parsing quantities from text
struct QuantityParser {
    
    /// Parse a quantity string like "2 cups" or "1/2 tsp" or "2-3 cups"
    static func parse(_ text: String) -> Quantity? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Try to match a range pattern (e.g., "1-2", "1 - 2")
        // We look for: Number [-] Number [Unit]
        // Note: This Regex is a bit simplified; for a robust parser we'd handle more
        // Check for range pattern "X-Y unit"
        if trimmed.contains("-") {
             let rangeComponents = trimmed.components(separatedBy: "-")
             if rangeComponents.count == 2 {
                 // Format: "1 " and " 2 cups"
                 let firstPart = rangeComponents[0].trimmingCharacters(in: .whitespaces)
                 let secondPart = rangeComponents[1].trimmingCharacters(in: .whitespaces)
                 
                 // First part should be just a number
                 if let lowerValue = parseValue(firstPart) {
                     // Second part usually contains the upper number AND the unit
                     // Split second part by space to separation number and unit
                     let secondComponents = secondPart.components(separatedBy: .whitespaces)
                     if secondComponents.count >= 1 {
                         let upperValueString = secondComponents[0]
                         if let upperValue = parseValue(upperValueString) {
                             // The rest is the unit
                             let unitText = secondComponents.dropFirst().joined(separator: " ")
                             if let unit = parseUnit(unitText) {
                                  return Quantity(value: lowerValue, upperValue: upperValue, unit: unit)
                             }
                         }
                     }
                 }
             }
        }
        
        // Try to extract number and unit (standard case)
        let components = trimmed.components(separatedBy: .whitespaces)
        guard components.count >= 2 else { return nil }
        
        // Check for "mixed fraction range" edge cases if simple range fail
        // e.g. "1 1/2" is handled by parseValue, but "1 - 2" is handled above.
        
        let valueText = components[0]
        let unitText = components[1...].joined(separator: " ")
        
        // Parse value (including fractions)
        guard let value = parseValue(valueText) else { return nil }
        
        // Parse unit
        guard let unit = parseUnit(unitText) else { return nil }
        
        return Quantity(value: value, unit: unit)
    }
    
    private static func parseValue(_ text: String) -> Double? {
        // Handle fractions
        if text.contains("/") {
            let parts = text.components(separatedBy: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else {
                return nil
            }
            return numerator / denominator
        }
        
        // Handle mixed numbers like "1 1/2"
        if text.contains(" ") {
            let parts = text.components(separatedBy: " ")
            if parts.count == 2,
               let whole = Double(parts[0]),
               let fraction = parseValue(parts[1]) {
                return whole + fraction
            }
        }
        
        return Double(text)
    }
    
    private static func parseUnit(_ text: String) -> UnitKind? {
        let normalized = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try exact matches first
        for unit in UnitKind.allCases {
            if normalized == unit.rawValue ||
               normalized == unit.displayName ||
               normalized == unit.pluralName {
                return unit
            }
        }
        
        // Try common abbreviations
        switch normalized {
        case "t", "tsp", "teaspoons", "teaspoon": return .teaspoon
        case "T", "tbsp", "tablespoons", "tablespoon": return .tablespoon
        case "c", "cups": return .cup
        case "oz", "ounces": return .ounce
        case "lb", "lbs", "pounds": return .pound
        case "g", "grams": return .gram
        case "kg", "kilograms": return .kilogram
        case "ml", "milliliters": return .milliliter
        case "l", "liters": return .liter
        default: return nil
        }
    }
}
