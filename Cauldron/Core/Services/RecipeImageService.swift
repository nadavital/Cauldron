//
//  RecipeImageService.swift
//  Cauldron
//
//  Created by Claude Code on 10/28/25.
//

import SwiftUI
import UIKit

/// Centralized service for loading and caching recipe images
@MainActor
class RecipeImageService {
    static let shared = RecipeImageService()

    // Memory cache for loaded images
    private let cache = NSCache<NSString, UIImage>()

    // Maximum cache size (50 images)
    private let maxCacheCount = 50

    private init() {
        cache.countLimit = maxCacheCount
    }

    /// Load an image from a URL (local or remote) with caching
    /// - Parameter url: The URL of the image to load
    /// - Returns: Result containing UIImage or error
    func loadImage(from url: URL?) async -> Result<UIImage, ImageLoadError> {
        guard let url = url else {
            return .failure(.invalidURL)
        }

        let cacheKey = url.absoluteString as NSString

        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
            return .success(cachedImage)
        }

        // Load from disk or remote
        do {
            let data: Data

            if url.isFileURL {
                // Local file - load from disk
                data = try Data(contentsOf: url)
            } else {
                // Remote URL - download with retry logic
                data = try await downloadImageWithRetry(from: url)
            }

            guard let image = UIImage(data: data) else {
                return .failure(.invalidImageData)
            }

            // Cache the loaded image
            cache.setObject(image, forKey: cacheKey)

            return .success(image)
        } catch {
            return .failure(.loadFailed(error))
        }
    }

    /// Download image from remote URL with retry logic
    private func downloadImageWithRetry(from url: URL, maxRetries: Int = 2) async throws -> Data {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                request.cachePolicy = .returnCacheDataElseLoad

                let (data, response) = try await URLSession.shared.data(for: request)

                // Verify response
                if let httpResponse = response as? HTTPURLResponse {
                    guard (200...299).contains(httpResponse.statusCode) else {
                        throw ImageLoadError.httpError(statusCode: httpResponse.statusCode)
                    }
                }

                return data
            } catch {
                lastError = error
                if attempt < maxRetries {
                    // Wait before retrying (exponential backoff)
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 500_000_000)) // 0.5s, 1s, 2s...
                }
            }
        }

        throw lastError ?? ImageLoadError.loadFailed(NSError(domain: "RecipeImageService", code: -1, userInfo: nil))
    }

    /// Load an image from a filename in the RecipeImages directory
    /// - Parameter filename: The filename (e.g., "recipeId.jpg")
    /// - Returns: Result containing UIImage or error
    func loadImage(filename: String) async -> Result<UIImage, ImageLoadError> {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.invalidURL)
        }

        let imageURL = documentsURL
            .appendingPathComponent("RecipeImages")
            .appendingPathComponent(filename)

        return await loadImage(from: imageURL)
    }

    /// Clear all cached images from memory
    func clearCache() {
        cache.removeAllObjects()
    }

    /// Remove a specific image from cache
    func removeFromCache(url: URL?) {
        guard let url = url else { return }
        cache.removeObject(forKey: url.absoluteString as NSString)
    }
}

/// Errors that can occur during image loading
enum ImageLoadError: Error, LocalizedError {
    case invalidURL
    case invalidImageData
    case loadFailed(Error)
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .invalidImageData:
            return "Unable to decode image data"
        case .loadFailed(let error):
            return "Failed to load image: \(error.localizedDescription)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}
