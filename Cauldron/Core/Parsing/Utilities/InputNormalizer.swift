//
//  InputNormalizer.swift
//  Cauldron
//
//  Created on January 25, 2026.
//

import Foundation

/// Normalizes and cleans raw input text for recipe parsing
///
/// Handles:
/// - Line break normalization (\r\n → \n)
/// - HTML entity decoding
/// - Social media artifact removal (hashtags, @mentions)
/// - Unicode bullet normalization
/// - Excessive whitespace cleanup
struct InputNormalizer {

    /// Normalize input text for recipe parsing
    ///
    /// - Parameter text: The raw input text
    /// - Returns: Cleaned and normalized text
    ///
    /// Examples:
    /// ```swift
    /// InputNormalizer.normalize("Recipe\r\n\r\nIngredients:")
    /// // "Recipe\n\nIngredients:"
    ///
    /// InputNormalizer.normalize("Great recipe! #foodie @chef")
    /// // "Great recipe!"
    /// ```
    static func normalize(_ text: String) -> String {
        var result = text

        // Normalize line breaks
        result = normalizeLineBreaks(result)

        // Decode HTML entities
        result = HTMLEntityDecoder.decode(result, stripTags: true)

        // Remove social media artifacts
        result = removeSocialMediaArtifacts(result)

        // Normalize unicode bullets to standard bullet
        result = normalizeUnicodeBullets(result)

        // Clean excessive whitespace while preserving line structure
        result = cleanWhitespace(result)

        return result
    }

    /// Normalize various line break formats to \n
    private static func normalizeLineBreaks(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\r\n", with: "\n")
        result = result.replacingOccurrences(of: "\r", with: "\n")
        return result
    }

    /// Remove social media artifacts like hashtags and @mentions
    private static func removeSocialMediaArtifacts(_ text: String) -> String {
        var result = text

        // Remove hashtags (but keep # in measurements like #10 can)
        // Only remove hashtags followed by letters
        result = result.replacingOccurrences(
            of: #"#[a-zA-Z][a-zA-Z0-9_]*"#,
            with: "",
            options: .regularExpression
        )

        // Remove @mentions
        result = result.replacingOccurrences(
            of: #"@[a-zA-Z0-9_]+"#,
            with: "",
            options: .regularExpression
        )

        // Remove common social media calls to action
        let socialPhrases = [
            #"(?i)follow\s+(me\s+)?(@\w+\s*)?for\s+more"#,
            #"(?i)link\s+in\s+bio"#,
            #"(?i)tap\s+to\s+shop"#,
            #"(?i)swipe\s+(left|right|up)\s+for"#,
            #"(?i)double\s+tap\s+if"#,
            #"(?i)save\s+this\s+(post|recipe)"#,
            #"(?i)share\s+this\s+with"#,
            #"(?i)tag\s+(a\s+)?friend"#
        ]

        for pattern in socialPhrases {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return result
    }

    /// Normalize various unicode bullets to a standard format
    private static func normalizeUnicodeBullets(_ text: String) -> String {
        var result = text

        // Map various bullets to standard bullet (for easier bullet removal later)
        let bulletMap: [String: String] = [
            "●": "•",  // Black circle
            "○": "•",  // White circle
            "◦": "•",  // White bullet
            "▪": "•",  // Black small square
            "▫": "•",  // White small square
            "■": "•",  // Black square
            "□": "•",  // White square
            "▸": "•",  // Right-pointing triangle
            "▹": "•",  // White right-pointing triangle
            "►": "•",  // Right-pointing pointer
            "▻": "•",  // White right-pointing pointer
            "➤": "•",  // Right arrowhead
            "➢": "•",  // Three-D right arrowhead
            "→": "•",  // Rightwards arrow
            "–": "-",  // En dash to hyphen
            "—": "-"   // Em dash to hyphen
        ]

        for (unicode, replacement) in bulletMap {
            result = result.replacingOccurrences(of: unicode, with: replacement)
        }

        return result
    }

    /// Clean excessive whitespace while preserving paragraph structure
    private static func cleanWhitespace(_ text: String) -> String {
        var result = text

        // Collapse multiple spaces to single space (but not newlines)
        result = result.replacingOccurrences(
            of: #"[^\S\n]+"#,
            with: " ",
            options: .regularExpression
        )

        // Collapse more than 2 consecutive newlines to 2
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        // Trim each line
        let lines = result.components(separatedBy: "\n")
        result = lines.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")

        // Trim overall
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    /// Check if text appears to contain recipe-like content
    ///
    /// - Parameter text: The text to check
    /// - Returns: True if the text likely contains a recipe
    ///
    /// Uses keyword matching to validate input before parsing
    static func textLooksLikeRecipe(_ text: String) -> Bool {
        let lowercased = text.lowercased()

        // Keywords that indicate recipe content
        let recipeKeywords = [
            // Ingredients
            "ingredient", "cup", "tablespoon", "teaspoon", "tbsp", "tsp",
            "ounce", "pound", "gram", "oz", "lb", "ml", "liter",
            // Actions
            "cook", "bake", "fry", "boil", "simmer", "roast", "grill",
            "mix", "stir", "whisk", "blend", "chop", "dice", "slice",
            "preheat", "oven", "heat", "add", "combine", "pour",
            // Structure
            "ingredients", "instructions", "directions", "steps",
            "recipe", "serves", "servings", "yield", "makes",
            "prep time", "cook time", "total time"
        ]

        // Count how many keywords appear
        let matchCount = recipeKeywords.filter { lowercased.contains($0) }.count

        // Require at least 3 keyword matches to consider it recipe-like
        return matchCount >= 3
    }
}
