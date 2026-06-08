import Foundation

/// Shared contract between Share Extension and app target for recipe import handoff.
enum ShareExtensionImportContract {
    static let appGroupID = "group.Nadav.Cauldron"
    static let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    static let pendingRecipeTextKey = "shareExtension.pendingRecipeText"
    static let preparedRecipePayloadKey = "shareExtension.preparedRecipePayload"

    static func firstHTTPURL(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return validHTTPURL(from: trimmed)
        }

        let range = NSRange(location: 0, length: trimmed.utf16.count)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        for match in matches {
            guard let url = match.url,
                  isHTTPURL(url) else {
                continue
            }
            return url
        }

        return validHTTPURL(from: trimmed)
    }

    static func plainTextRecipeShouldTakePrecedenceOverURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let textWithoutURLs = removingHTTPURLs(from: trimmed)
        let meaningfulLines = textWithoutURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let normalized = textWithoutURLs.lowercased()

        guard !normalized.isEmpty else { return false }

        if normalized.contains("ingredients") || normalized.contains("instructions") || normalized.contains("directions") {
            return true
        }

        let hasIngredientQuantity = normalized.range(
            of: #"\b\d+([./]\d+)?\s*(cup|cups|tbsp|tablespoon|tablespoons|tsp|teaspoon|teaspoons|oz|ounce|ounces|g|gram|grams|lb|pound|pounds|ml|l)\b"#,
            options: .regularExpression
        ) != nil
        let hasCookingAction = [
            "bake", "boil", "broil", "chop", "cook", "fold", "fry", "knead",
            "mix", "preheat", "roast", "saute", "sauté", "simmer", "stir", "whisk"
        ].contains { normalized.contains($0) }

        if hasIngredientQuantity && (hasCookingAction || meaningfulLines.count >= 2) {
            return true
        }

        if meaningfulLines.count >= 4 {
            return true
        }

        return textWithoutURLs.count >= 120 && meaningfulLines.count >= 2
    }

    private static func removingHTTPURLs(from text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }

        let mutable = NSMutableString(string: text)
        let range = NSRange(location: 0, length: mutable.length)
        let matches = detector.matches(in: text, options: [], range: range)
        for match in matches.reversed() {
            guard let url = match.url, isHTTPURL(url) else { continue }
            mutable.replaceCharacters(in: match.range, with: "")
        }
        return mutable.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func validHTTPURL(from string: String) -> URL? {
        guard let url = URL(string: string), isHTTPURL(url) else { return nil }
        return url
    }

    private static func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

/// Transport payload written by the Share Extension and consumed by the app.
struct PreparedShareRecipePayload: Codable, Sendable {
    let title: String
    let ingredients: [String]
    let steps: [String]
    let yields: String?
    let totalMinutes: Int?
    let sourceURL: String?
    let sourceTitle: String?
    let imageURL: String?
    let tagNames: [String]

    private enum CodingKeys: String, CodingKey {
        case title
        case ingredients
        case steps
        case yields
        case totalMinutes
        case sourceURL
        case sourceTitle
        case imageURL
        case tagNames
    }

    nonisolated init(
        title: String,
        ingredients: [String],
        steps: [String],
        yields: String? = nil,
        totalMinutes: Int? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        imageURL: String? = nil,
        tagNames: [String] = []
    ) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.imageURL = imageURL
        self.tagNames = tagNames
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decode(String.self, forKey: .title)
        self.ingredients = try container.decode([String].self, forKey: .ingredients)
        self.steps = try container.decode([String].self, forKey: .steps)
        self.yields = try container.decodeIfPresent(String.self, forKey: .yields)
        self.totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        self.tagNames = try container.decodeIfPresent([String].self, forKey: .tagNames) ?? []
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(ingredients, forKey: .ingredients)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(yields, forKey: .yields)
        try container.encodeIfPresent(totalMinutes, forKey: .totalMinutes)
        try container.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try container.encodeIfPresent(sourceTitle, forKey: .sourceTitle)
        try container.encodeIfPresent(imageURL, forKey: .imageURL)
        if !tagNames.isEmpty {
            try container.encode(tagNames, forKey: .tagNames)
        }
    }
}
