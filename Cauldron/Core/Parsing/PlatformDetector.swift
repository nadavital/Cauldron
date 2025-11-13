import Foundation

/// Detects the platform/service from a URL to route to appropriate parser
enum Platform {
    case youtube
    case tiktok
    case instagram
    case recipeWebsite
    case unknown
}

struct PlatformDetector {
    /// Detects the platform from a URL string
    nonisolated static func detect(from urlString: String) -> Platform {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return .unknown
        }

        // YouTube detection
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        }

        // TikTok detection
        if host.contains("tiktok.com") {
            return .tiktok
        }

        // Instagram detection
        if host.contains("instagram.com") {
            return .instagram
        }

        // Default to recipe website (will use existing HTML parser)
        return .recipeWebsite
    }

    /// Normalizes YouTube URLs to standard format
    nonisolated static func normalizeYouTubeURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        // Handle youtu.be short links
        if url.host?.contains("youtu.be") == true {
            let videoID = url.pathComponents.last ?? ""
            return "https://www.youtube.com/watch?v=\(videoID)"
        }

        // Handle youtube.com/shorts
        if url.path.contains("/shorts/") {
            let videoID = url.pathComponents.last ?? ""
            return "https://www.youtube.com/watch?v=\(videoID)"
        }

        // Already in standard format
        return urlString
    }
}
