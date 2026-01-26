//
//  TimeParser.swift
//  Cauldron
//
//  Created on January 25, 2026.
//

import Foundation

/// Extracts cooking time information from recipe text
///
/// Handles patterns like:
/// - "Cook time: 30 min", "Cook Time: 45 minutes"
/// - "Total time: 1 hour", "Total: 1 hr 30 min"
/// - "Prep: 15 min, Cook: 45 min"
/// - "Ready in 45 minutes"
/// - "Time: 1 hr 30 min"
/// - "Overnight (8 hours)"
struct TimeParser {

    /// Time extraction result containing categorized times
    struct TimeResult {
        var prepMinutes: Int?
        var cookMinutes: Int?
        var totalMinutes: Int?

        /// Get the best estimate for total time
        var bestTotalMinutes: Int? {
            if let total = totalMinutes {
                return total
            }
            if let prep = prepMinutes, let cook = cookMinutes {
                return prep + cook
            }
            return cookMinutes ?? prepMinutes
        }
    }

    /// Time patterns with their categories
    private enum TimeCategory {
        case prep
        case cook
        case total
    }

    /// Extract total cooking time in minutes from lines
    ///
    /// - Parameter lines: Array of text lines to search
    /// - Returns: Total time in minutes, or nil if not found
    ///
    /// Examples:
    /// ```swift
    /// TimeParser.extractTotalMinutes(from: ["Prep: 15 min", "Cook: 30 min"])
    /// // 45
    ///
    /// TimeParser.extractTotalMinutes(from: ["Total time: 1 hour"])
    /// // 60
    /// ```
    static func extractTotalMinutes(from lines: [String]) -> Int? {
        let result = extractAllTimes(from: lines)
        return result.bestTotalMinutes
    }

    /// Extract all time components from lines
    ///
    /// - Parameter lines: Array of text lines to search
    /// - Returns: TimeResult with all extracted times
    static func extractAllTimes(from lines: [String]) -> TimeResult {
        var result = TimeResult()

        for line in lines {
            let lowercased = line.lowercased()

            // Check for total time patterns
            if let totalMinutes = extractTotalTime(from: lowercased) {
                result.totalMinutes = totalMinutes
            }

            // Check for cook time patterns
            if let cookMinutes = extractCookTime(from: lowercased) {
                result.cookMinutes = cookMinutes
            }

            // Check for prep time patterns
            if let prepMinutes = extractPrepTime(from: lowercased) {
                result.prepMinutes = prepMinutes
            }

            // Check for generic time patterns
            if result.totalMinutes == nil && result.cookMinutes == nil {
                if let genericMinutes = extractGenericTime(from: lowercased) {
                    result.totalMinutes = genericMinutes
                }
            }
        }

        return result
    }

    /// Extract total time from text
    private static func extractTotalTime(from text: String) -> Int? {
        let patterns = [
            #"total\s*(?:time)?\s*:?\s*"#,
            #"ready\s+in\s*:?\s*"#,
            #"overall\s*(?:time)?\s*:?\s*"#
        ]

        for pattern in patterns {
            if let minutes = extractTimeAfterPattern(pattern, in: text) {
                return minutes
            }
        }
        return nil
    }

    /// Extract cook time from text
    private static func extractCookTime(from text: String) -> Int? {
        let patterns = [
            #"cook\s*(?:time|ing)?\s*:?\s*"#,
            #"bake\s*(?:time|ing)?\s*:?\s*"#,
            #"roast\s*(?:time|ing)?\s*:?\s*"#
        ]

        for pattern in patterns {
            if let minutes = extractTimeAfterPattern(pattern, in: text) {
                return minutes
            }
        }
        return nil
    }

    /// Extract prep time from text
    private static func extractPrepTime(from text: String) -> Int? {
        let patterns = [
            #"prep\s*(?:time|aration)?\s*:?\s*"#,
            #"preparation\s*(?:time)?\s*:?\s*"#
        ]

        for pattern in patterns {
            if let minutes = extractTimeAfterPattern(pattern, in: text) {
                return minutes
            }
        }
        return nil
    }

    /// Extract generic time from text (e.g., "Time: 30 min")
    private static func extractGenericTime(from text: String) -> Int? {
        let patterns = [
            #"^time\s*:?\s*"#,
            #"overnight\s*\(?(\d+)\s*(?:hours?|hrs?)\)?"#
        ]

        // Handle "overnight" specially
        if text.contains("overnight") {
            let overnightPattern = #"overnight\s*\(?(\d+)\s*(?:hours?|hrs?)\)?"#
            if let regex = try? NSRegularExpression(pattern: overnightPattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges >= 2,
               let range = Range(match.range(at: 1), in: text),
               let hours = Int(text[range]) {
                return hours * 60
            }
            // Default overnight to 8 hours
            return 8 * 60
        }

        for pattern in patterns {
            if let minutes = extractTimeAfterPattern(pattern, in: text) {
                return minutes
            }
        }
        return nil
    }

    /// Extract time value after a pattern match
    private static func extractTimeAfterPattern(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)

        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }

        // Get the text after the match
        let afterMatchStart = match.range.upperBound
        guard afterMatchStart < nsString.length else {
            return nil
        }

        let remainingText = nsString.substring(from: afterMatchStart)
        return parseTimeString(remainingText)
    }

    /// Parse a time string into minutes
    ///
    /// Handles formats like:
    /// - "30 min", "30 minutes", "30 mins"
    /// - "1 hour", "1 hr", "1 h"
    /// - "1 hour 30 minutes", "1h 30m", "1:30"
    /// - "90" (assumes minutes if standalone number)
    static func parseTimeString(_ text: String) -> Int? {
        let cleaned = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var totalMinutes = 0
        var foundTime = false

        // Pattern for hours and minutes combined: "1 hour 30 min", "1h30m", "1:30"
        let combinedPattern = #"(\d+)\s*(?:hours?|hrs?|h)\s*(?:and\s*)?(\d+)?\s*(?:minutes?|mins?|m)?"#
        if let regex = try? NSRegularExpression(pattern: combinedPattern),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
           match.numberOfRanges >= 2,
           let hoursRange = Range(match.range(at: 1), in: cleaned),
           let hours = Int(cleaned[hoursRange]) {
            totalMinutes += hours * 60
            foundTime = true

            if match.numberOfRanges >= 3,
               let minutesRange = Range(match.range(at: 2), in: cleaned),
               let minutes = Int(cleaned[minutesRange]) {
                totalMinutes += minutes
            }
        }

        // Pattern for colon format: "1:30"
        if !foundTime {
            let colonPattern = #"(\d+):(\d+)"#
            if let regex = try? NSRegularExpression(pattern: colonPattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               match.numberOfRanges >= 3,
               let hoursRange = Range(match.range(at: 1), in: cleaned),
               let minutesRange = Range(match.range(at: 2), in: cleaned),
               let hours = Int(cleaned[hoursRange]),
               let minutes = Int(cleaned[minutesRange]) {
                totalMinutes = hours * 60 + minutes
                foundTime = true
            }
        }

        // Pattern for hours only: "2 hours"
        if !foundTime {
            let hoursPattern = #"(\d+)\s*(?:hours?|hrs?|h)\b"#
            if let regex = try? NSRegularExpression(pattern: hoursPattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               match.numberOfRanges >= 2,
               let hoursRange = Range(match.range(at: 1), in: cleaned),
               let hours = Int(cleaned[hoursRange]) {
                totalMinutes = hours * 60
                foundTime = true
            }
        }

        // Pattern for minutes only: "30 min"
        if !foundTime {
            let minutesPattern = #"(\d+)\s*(?:minutes?|mins?|m)\b"#
            if let regex = try? NSRegularExpression(pattern: minutesPattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               match.numberOfRanges >= 2,
               let minutesRange = Range(match.range(at: 1), in: cleaned),
               let minutes = Int(cleaned[minutesRange]) {
                totalMinutes = minutes
                foundTime = true
            }
        }

        // Standalone number with no unit (assume minutes)
        if !foundTime {
            let standalonePattern = #"^(\d+)\s*$"#
            if let regex = try? NSRegularExpression(pattern: standalonePattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               match.numberOfRanges >= 2,
               let minutesRange = Range(match.range(at: 1), in: cleaned),
               let minutes = Int(cleaned[minutesRange]) {
                totalMinutes = minutes
                foundTime = true
            }
        }

        return foundTime && totalMinutes > 0 ? totalMinutes : nil
    }
}
