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
        if hostMatches(host, domains: ["youtube.com", "youtu.be"]) {
            return .youtube
        }

        // TikTok detection
        if hostMatches(host, domains: ["tiktok.com"]) {
            return .tiktok
        }

        // Instagram detection
        if hostMatches(host, domains: ["instagram.com"]) {
            return .instagram
        }

        // Default to recipe website (will use existing HTML parser)
        return .recipeWebsite
    }

    /// Normalizes YouTube URLs to standard format
    nonisolated static func normalizeYouTubeURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        let host = url.host?.lowercased() ?? ""

        // Handle youtu.be short links
        if hostMatches(host, domains: ["youtu.be"]) {
            let videoID = url.pathComponents.last ?? ""
            return "https://www.youtube.com/watch?v=\(videoID)"
        }

        // Handle youtube.com/shorts
        if hostMatches(host, domains: ["youtube.com"]), url.path.contains("/shorts/") {
            let videoID = url.pathComponents.last ?? ""
            return "https://www.youtube.com/watch?v=\(videoID)"
        }

        // Already in standard format
        return urlString
    }

    nonisolated private static func hostMatches(_ host: String, domains: [String]) -> Bool {
        domains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }
}
