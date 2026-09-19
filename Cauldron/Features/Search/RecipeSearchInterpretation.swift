import Foundation

/// Conservative, local interpretation. Unrecognized language remains literal search text.
struct RecipeSearchInterpretation: Equatable {
    var text: String
    var time: RecipeTimeFilter?
    var excludedIngredients: String?
    var category: RecipeCategory?

    init(_ query: String) {
        text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let timePattern = #"\b(?:under|less than)\s+(15|30|60)\s*(?:minutes?|mins?)\b"#
        if let expression = try? NSRegularExpression(pattern: timePattern, options: .caseInsensitive),
           let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let numberRange = Range(match.range(at: 1), in: text),
           let fullRange = Range(match.range, in: text) {
            time = ["15": .under15, "30": .under30, "60": .under60][String(text[numberRange])]
            text.removeSubrange(fullRange)
        }
        // Only consume a terminal exclusion; never silently discard additional constraints.
        if let range = text.range(of: #"\bwithout\s+[^.!?]+$"#, options: [.regularExpression, .caseInsensitive]) {
            let clause = String(text[range]).dropFirst("without".count).trimmingCharacters(in: .whitespaces)
            let containsUnrecognizedConstraint = clause.range(
                of: #"\b(under|over|minutes?|mins?|servings?|calories|with|for)\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
            if !clause.isEmpty && !containsUnrecognizedConstraint {
                excludedIngredients = clause.replacingOccurrences(of: #"\s+and\s+"#, with: ", ", options: [.regularExpression, .caseInsensitive])
                text.removeSubrange(range)
            }
        }
        for candidate in [RecipeCategory.breakfast, .lunch, .dinner, .dessert, .snack] {
            let pattern = "\\b" + candidate.rawValue.lowercased() + "s?\\b"
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                category = candidate
                text.removeSubrange(range)
                break
            }
        }
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasFilters: Bool { time != nil || excludedIngredients != nil || category != nil }
}
