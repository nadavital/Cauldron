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
}
