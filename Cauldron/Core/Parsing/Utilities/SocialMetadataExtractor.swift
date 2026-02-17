import Foundation

/// Shared text and metadata helpers used by social import parsers.
enum SocialMetadataExtractor {
    private static let recipeKeywords = [
        "ingredient", "ingredients", "recipe", "directions", "instructions", "steps",
        "cup", "cups", "tablespoon", "teaspoon", "tbsp", "tsp",
        "bake", "cook", "mix", "stir", "combine", "blend",
        "flour", "sugar", "salt", "pepper", "oil", "butter", "water"
    ]

    static func normalizedLines(from text: String) -> [String] {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func looksLikeRecipe(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let keywordCount = recipeKeywords.filter { lowercased.contains($0) }.count
        return keywordCount >= 2
    }

    static func extractMetaContent(from html: String, name: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "<meta\\s+name=\"\(escapedName)\"\\s+content=\"([^\"]+)\""
        return extractWithRegex(html, pattern: pattern)
    }

    static func extractMetaContent(from html: String, property: String) -> String? {
        let escapedProperty = NSRegularExpression.escapedPattern(for: property)
        let pattern = "<meta\\s+property=\"\(escapedProperty)\"\\s+content=\"([^\"]+)\""
        return extractWithRegex(html, pattern: pattern)
    }

    static func extractWithRegex(
        _ text: String,
        pattern: String,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 2,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let captured = String(text[captureRange])
        return HTMLEntityDecoder.decode(captured, stripTags: false)
    }
}
