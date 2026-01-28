//
//  PlatformDetectorTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class PlatformDetectorTests: XCTestCase {

    // MARK: - YouTube Detection Tests

    func testDetect_YouTube_StandardURL() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    func testDetect_YouTube_ShortURL() {
        let url = "https://youtu.be/dQw4w9WgXcQ"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    func testDetect_YouTube_MobileURL() {
        let url = "https://m.youtube.com/watch?v=dQw4w9WgXcQ"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    func testDetect_YouTube_ShortsURL() {
        let url = "https://www.youtube.com/shorts/abcd1234"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    func testDetect_YouTube_WithQueryParams() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share&t=123"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    func testDetect_YouTube_NoProtocol() {
        // URLs without protocol (http/https) cannot be parsed by URL(string:)
        // so they return .unknown
        let url = "youtube.com/watch?v=dQw4w9WgXcQ"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .unknown, "URLs without protocol scheme should return .unknown")
    }

    func testDetect_YouTube_NoWWW() {
        let url = "https://youtube.com/watch?v=dQw4w9WgXcQ"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .youtube)
    }

    // MARK: - TikTok Detection Tests

    func testDetect_TikTok_StandardURL() {
        let url = "https://www.tiktok.com/@user/video/1234567890"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .tiktok)
    }

    func testDetect_TikTok_ShortURL() {
        let url = "https://vm.tiktok.com/abcd1234/"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .tiktok)
    }

    func testDetect_TikTok_NoWWW() {
        let url = "https://tiktok.com/@chef/video/9876543210"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .tiktok)
    }

    // MARK: - Instagram Detection Tests

    func testDetect_Instagram_ReelURL() {
        let url = "https://www.instagram.com/reel/abcd1234/"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .instagram)
    }

    func testDetect_Instagram_PostURL() {
        let url = "https://instagram.com/p/abcd1234/"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .instagram)
    }

    func testDetect_Instagram_WithWWW() {
        let url = "https://www.instagram.com/p/xyz9876/"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .instagram)
    }

    // MARK: - Recipe Website Detection Tests

    func testDetect_RecipeWebsite_AllRecipes() {
        let url = "https://www.allrecipes.com/recipe/12345/cookies/"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .recipeWebsite)
    }

    func testDetect_RecipeWebsite_FoodNetwork() {
        let url = "https://www.foodnetwork.com/recipes/chocolate-chip-cookies"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .recipeWebsite)
    }

    func testDetect_RecipeWebsite_GenericBlog() {
        let url = "https://www.myblog.com/recipe/cookies"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .recipeWebsite)
    }

    // MARK: - Unknown/Invalid URL Tests

    func testDetect_InvalidURL() {
        let url = "not-a-valid-url"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .unknown)
    }

    func testDetect_EmptyString() {
        let url = ""
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .unknown)
    }

    func testDetect_NoHost() {
        let url = "file:///local/path"
        let platform = PlatformDetector.detect(from: url)
        XCTAssertEqual(platform, .unknown)
    }

    // MARK: - YouTube URL Normalization Tests

    func testNormalizeYouTubeURL_StandardFormat() {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        XCTAssertEqual(normalized, url, "Standard format should remain unchanged")
    }

    func testNormalizeYouTubeURL_ShortLink() {
        let url = "https://youtu.be/dQw4w9WgXcQ"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        XCTAssertEqual(normalized, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testNormalizeYouTubeURL_ShortsFormat() {
        let url = "https://www.youtube.com/shorts/abcd1234"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        XCTAssertEqual(normalized, "https://www.youtube.com/watch?v=abcd1234")
    }

    func testNormalizeYouTubeURL_ShortLinkWithQueryParams() {
        let url = "https://youtu.be/dQw4w9WgXcQ?t=30"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        // Should normalize to standard format (query params might be lost)
        XCTAssertTrue(normalized?.contains("watch?v=dQw4w9WgXcQ") ?? false)
    }

    func testNormalizeYouTubeURL_MobileURL() {
        let url = "https://m.youtube.com/watch?v=dQw4w9WgXcQ"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        XCTAssertEqual(normalized, url, "Mobile URL should remain unchanged")
    }

    func testNormalizeYouTubeURL_InvalidURL() {
        // Note: URL(string:) is actually quite permissive and will parse many strings
        // including "not-a-url" as a relative URL. For it to return nil, we need
        // invalid characters or malformed syntax
        let url = "not-a-url"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        // The function returns the original string if it's not a youtu.be or shorts URL
        XCTAssertEqual(normalized, url, "Non-YouTube URLs should return original string")
    }

    func testNormalizeYouTubeURL_NonYouTubeURL() {
        let url = "https://www.example.com"
        let normalized = PlatformDetector.normalizeYouTubeURL(url)
        XCTAssertEqual(normalized, url, "Non-YouTube URL should remain unchanged")
    }

    // MARK: - Edge Cases

    func testDetect_CaseInsensitive() {
        let urls = [
            "https://WWW.YOUTUBE.COM/watch?v=test",
            "https://www.YouTube.com/watch?v=test",
            "https://YOUTUBE.COM/watch?v=test"
        ]

        for url in urls {
            let platform = PlatformDetector.detect(from: url)
            XCTAssertEqual(platform, .youtube, "Should detect YouTube regardless of case: \(url)")
        }
    }

    func testNormalizeYouTubeURL_PreservesVideoID() {
        let testCases = [
            ("https://youtu.be/abc123", "abc123"),
            ("https://www.youtube.com/shorts/xyz789", "xyz789"),
            ("https://www.youtube.com/watch?v=test123", "test123")
        ]

        for (input, expectedVideoID) in testCases {
            let normalized = PlatformDetector.normalizeYouTubeURL(input)
            XCTAssertTrue(normalized?.contains(expectedVideoID) ?? false,
                         "Normalized URL should contain video ID \(expectedVideoID)")
        }
    }

    // MARK: - Bulk Test with Fixtures

    func testDetect_AllYouTubeFixtures() {
        for url in TestFixtures.youtubeURLs {
            let platform = PlatformDetector.detect(from: url)
            XCTAssertEqual(platform, .youtube, "Failed to detect YouTube for: \(url)")
        }
    }

    func testDetect_AllTikTokFixtures() {
        for url in TestFixtures.tiktokURLs {
            let platform = PlatformDetector.detect(from: url)
            XCTAssertEqual(platform, .tiktok, "Failed to detect TikTok for: \(url)")
        }
    }

    func testDetect_AllInstagramFixtures() {
        for url in TestFixtures.instagramURLs {
            let platform = PlatformDetector.detect(from: url)
            XCTAssertEqual(platform, .instagram, "Failed to detect Instagram for: \(url)")
        }
    }
}
