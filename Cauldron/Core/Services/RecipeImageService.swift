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
                // Remote URL - download
                let (downloadedData, _) = try await URLSession.shared.data(from: url)
                data = downloadedData
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

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid image URL"
        case .invalidImageData:
            return "Unable to decode image data"
        case .loadFailed(let error):
            return "Failed to load image: \(error.localizedDescription)"
        }
    }
}
