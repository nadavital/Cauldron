//
//  RecipeImageService.swift
//  Cauldron
//
//  Created by Claude Code on 10/28/25.
//

import SwiftUI
import UIKit
import CloudKit

/// Centralized service for loading and caching recipe images
@MainActor
class RecipeImageService {
    // Memory cache for loaded images
    private let cache = NSCache<NSString, UIImage>()

    // Maximum cache size (50 images)
    private let maxCacheCount = 50

    // CloudKit service for fallback loading
    private let cloudKitService: CloudKitService
    private let imageManager: ImageManager

    init(cloudKitService: CloudKitService, imageManager: ImageManager) {
        self.cloudKitService = cloudKitService
        self.imageManager = imageManager
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

    /// Load an image for a recipe with CloudKit fallback
    /// - Parameters:
    ///   - recipeId: The recipe ID
    ///   - url: The local URL (optional, for cache key)
    ///   - ownerId: The owner ID of the recipe (to determine which database to use)
    /// - Returns: Result containing UIImage or error
    func loadImage(forRecipeId recipeId: UUID, localURL url: URL?, ownerId: UUID? = nil) async -> Result<UIImage, ImageLoadError> {
        // Try loading from local URL first
        if let url = url {
            let result = await loadImage(from: url)
            if case .success = result {
                return result
            }
        }

        // If local load failed, try CloudKit fallback
        // Strategy: Try both databases - public first (for shared recipes), then private
        do {
            // Determine which database to try first based on ownership
            let currentUserId = await CurrentUserSession.shared.currentUser?.id
            let isOwnRecipe = (ownerId == currentUserId) || (ownerId == nil)

            // Try public database first for shared recipes, private first for own recipes
            let databases = isOwnRecipe
                ? [try await cloudKitService.getPrivateDatabase(), try await cloudKitService.getPublicDatabase()]
                : [try await cloudKitService.getPublicDatabase(), try await cloudKitService.getPrivateDatabase()]

            for database in databases {
                if let filename = try await imageManager.downloadImageFromCloud(recipeId: recipeId, database: database) {
                    // Image downloaded successfully, load it
                    let fileManager = FileManager.default
                    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                        return .failure(.invalidURL)
                    }

                    let imageURL = documentsURL
                        .appendingPathComponent("RecipeImages")
                        .appendingPathComponent(filename)

                    return await loadImage(from: imageURL)
                }
            }
        } catch {
            // CloudKit fallback failed, return original error
        }

        return .failure(.loadFailed(NSError(domain: "RecipeImageService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Image not found locally or in CloudKit"])))
    }

    /// Prefetch images for multiple recipes (for collection grids)
    /// - Parameter recipeIds: Array of recipe IDs to prefetch
    func prefetchImages(forRecipeIds recipeIds: [UUID]) {
        Task {
            for recipeId in recipeIds.prefix(4) {  // Only prefetch first 4 for grid
                let filename = "\(recipeId.uuidString).jpg"
                _ = await loadImage(filename: filename)
            }
        }
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
