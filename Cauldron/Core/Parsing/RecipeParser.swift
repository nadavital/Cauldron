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
    
    /// Extract timer specifications from text
    static func extractTimers(from text: String) -> [TimerSpec] {
        var timers: [TimerSpec] = []
        let lowercased = text.lowercased()
        
        // Pattern: X minutes/mins/min
        let minutePattern = #/(\d+)\s*(minutes?|mins?)\b/#
        if let match = try? minutePattern.firstMatch(in: lowercased) {
            if let value = Int(match.1) {
                timers.append(.minutes(value, label: "Cook"))
            }
        }
        
        // Pattern: X hours/hrs/hr
        let hourPattern = #/(\d+)\s*(hours?|hrs?)\b/#
        if let match = try? hourPattern.firstMatch(in: lowercased) {
            if let value = Int(match.1) {
                timers.append(.hours(value, label: "Cook"))
            }
        }
        
        // Pattern: X seconds/secs/sec
        let secondPattern = #/(\d+)\s*(seconds?|secs?)\b/#
        if let match = try? secondPattern.firstMatch(in: lowercased) {
            if let value = Int(match.1) {
                timers.append(TimerSpec(seconds: value, label: "Cook"))
            }
        }
        
        return timers
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
