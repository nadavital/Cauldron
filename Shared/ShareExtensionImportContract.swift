import Foundation

/// Shared contract between Share Extension and app target for recipe import handoff.
enum ShareExtensionImportContract {
    static let appGroupID = "group.Nadav.Cauldron"
    static let pendingRecipeURLKey = "shareExtension.pendingRecipeURL"
    static let preparedRecipePayloadKey = "shareExtension.preparedRecipePayload"
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

    private enum CodingKeys: String, CodingKey {
        case title
        case ingredients
        case steps
        case yields
        case totalMinutes
        case sourceURL
        case sourceTitle
        case imageURL
    }

    nonisolated init(
        title: String,
        ingredients: [String],
        steps: [String],
        yields: String? = nil,
        totalMinutes: Int? = nil,
        sourceURL: String? = nil,
        sourceTitle: String? = nil,
        imageURL: String? = nil
    ) {
        self.title = title
        self.ingredients = ingredients
        self.steps = steps
        self.yields = yields
        self.totalMinutes = totalMinutes
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.imageURL = imageURL
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        self.steps = try container.decodeIfPresent([String].self, forKey: .steps) ?? []
        self.yields = try container.decodeIfPresent(String.self, forKey: .yields)
        self.totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes)
        self.sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL)
        self.sourceTitle = try container.decodeIfPresent(String.self, forKey: .sourceTitle)
        self.imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
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
    }
}
