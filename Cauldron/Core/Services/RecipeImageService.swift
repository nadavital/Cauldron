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
    private let imageManager: RecipeImageManager
    private var inFlightLoads: [String: Task<Result<UIImage, ImageLoadError>, Never>] = [:]

    init(imageManager: RecipeImageManager) {
        self.imageManager = imageManager
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    /// Load an image from a URL (local or remote) with caching
    /// - Parameter url: The URL of the image to load
    /// - Returns: Result containing UIImage or error
    func loadImage(from url: URL?, targetPixelSize: CGFloat? = nil) async -> Result<UIImage, ImageLoadError> {
        guard let url = url else {
            return .failure(.invalidURL)
        }

        let cacheKey = cacheKey(for: url, targetPixelSize: targetPixelSize)

        // Check cache first
        if let cachedImage = await ImageCache.shared.load(cacheKey) {
            return .success(cachedImage)
        }

        if let existingTask = inFlightLoads[cacheKey] {
            return await existingTask.value
        }

        let loadTask = Task<Result<UIImage, ImageLoadError>, Never> {
            do {
                let image: UIImage

                if url.isFileURL {
                    image = try await ImageLoadingPipeline.loadImage(fromFileURL: url, maxPixelSize: targetPixelSize)
                } else {
                    let data = try await self.downloadImageWithRetry(from: url)
                    image = try await ImageLoadingPipeline.decodeImage(from: data, maxPixelSize: targetPixelSize)
                }

                await MainActor.run {
                    ImageCache.shared.set(cacheKey, image: image)
                }

                return .success(image)
            } catch let error as ImageLoadError {
                return .failure(error)
            } catch ImageLoadingPipelineError.invalidImageData {
                return .failure(.invalidImageData)
            } catch {
                return .failure(.loadFailed(error))
            }
        }

        inFlightLoads[cacheKey] = loadTask
        let result = await loadTask.value
        inFlightLoads[cacheKey] = nil
        return result
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
    func loadImage(filename: String, targetPixelSize: CGFloat? = nil) async -> Result<UIImage, ImageLoadError> {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .failure(.invalidURL)
        }

        let imageURL = documentsURL
            .appendingPathComponent("RecipeImages")
            .appendingPathComponent(filename)

        return await loadImage(from: imageURL, targetPixelSize: targetPixelSize)
    }

    /// Load an image for a recipe with CloudKit fallback
    /// - Parameters:
    ///   - recipeId: The recipe ID
    ///   - url: The local URL (optional, for cache key)
    ///   - ownerId: The owner ID of the recipe (to determine which database to use)
    /// - Returns: Result containing UIImage or error
    func loadImage(
        forRecipeId recipeId: UUID,
        localURL url: URL?,
        ownerId: UUID? = nil,
        targetPixelSize: CGFloat? = nil,
        cacheVariant: String? = nil,
        privateRecordName: String? = nil
    ) async -> Result<UIImage, ImageLoadError> {
        let recipeCacheKey = ImageCache.recipeImageKey(
            recipeId: recipeId,
            variant: cacheVariant ?? variantKey(for: targetPixelSize)
        )

        if let cachedImage = await ImageCache.shared.load(recipeCacheKey) {
            if cachedImageSatisfiesRequest(cachedImage, targetPixelSize: targetPixelSize) {
                return .success(cachedImage)
            }
            ImageCache.shared.remove(recipeCacheKey)
        }

        // Try loading from local URL first
        if let url = url {
            // For non-owned recipes, verify file exists before attempting load
            let currentUserId = CurrentUserSession.shared.currentUser?.id
            if let ownerId = ownerId, ownerId != currentUserId {
                // This is a friend's recipe - check if file exists
                if !FileManager.default.fileExists(atPath: url.path) {
                    // Skip local load, file doesn't exist for friend's recipe
                    // Fall through to CloudKit
                } else {
                    let result = await loadImage(from: url, targetPixelSize: targetPixelSize)
                    if case .success(let image) = result {
                        ImageCache.shared.set(recipeCacheKey, image: image)
                        return result
                    }
                }
            } else {
                // Own recipe - try loading normally
                let result = await loadImage(from: url, targetPixelSize: targetPixelSize)
                if case .success(let image) = result {
                    ImageCache.shared.set(recipeCacheKey, image: image)
                    return result
                }
            }
        }

        // If local load failed, try CloudKit fallback
        // Strategy: Try both databases - public first (for shared recipes), then private
        do {
            // Determine which database to try first based on ownership
            let currentUserId = CurrentUserSession.shared.currentUser?.id
            let isOwnRecipe = (ownerId == currentUserId) || (ownerId == nil)

            // Try private database first for own recipes, public first for shared recipes
            let tryOrder: [Bool] = isOwnRecipe ? [false, true] : [true, false]  // fromPublic values

            for fromPublic in tryOrder {
                if let filename = try await imageManager.downloadImageFromCloud(recipeId: recipeId, fromPublic: fromPublic, privateRecordName: fromPublic ? nil : privateRecordName) {
                    // Image downloaded successfully, load it
                    let fileManager = FileManager.default
                    guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                        return .failure(.invalidURL)
                    }

                    let imageURL = documentsURL
                        .appendingPathComponent("RecipeImages")
                        .appendingPathComponent(filename)

                    let result = await loadImage(from: imageURL, targetPixelSize: targetPixelSize)
                    if case .success(let image) = result {
                        ImageCache.shared.set(recipeCacheKey, image: image)
                    }
                    return result
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
                let localURL = await imageManager.imageURL(recipeId: recipeId)
                _ = await loadImage(
                    forRecipeId: recipeId,
                    localURL: localURL,
                    targetPixelSize: 720,
                    cacheVariant: "card"
                )
            }
        }
    }

    /// Clear all cached images from memory
    func clearCache() {
        ImageCache.shared.clearRecipeImages()
    }

    /// Remove a specific image from cache
    func removeFromCache(url: URL?) {
        guard let url = url else { return }
        ImageCache.shared.remove(cacheKey(for: url, targetPixelSize: nil))
    }

    private func cacheKey(for url: URL, targetPixelSize: CGFloat?) -> String {
        let sizeKey: String
        if let targetPixelSize, targetPixelSize > 0 {
            sizeKey = String(Int(targetPixelSize.rounded(.up)))
        } else {
            sizeKey = "full"
        }

        return "image_\(url.absoluteString)_\(sizeKey)"
    }

    private func variantKey(for targetPixelSize: CGFloat?) -> String {
        if let targetPixelSize, targetPixelSize > 0 {
            return String(Int(targetPixelSize.rounded(.up)))
        }

        return "full"
    }

    private func cachedImageSatisfiesRequest(_ image: UIImage, targetPixelSize: CGFloat?) -> Bool {
        guard let targetPixelSize, targetPixelSize > 0 else {
            return true
        }

        let pixelWidth = image.cgImage.map { CGFloat($0.width) } ?? (image.size.width * image.scale)
        let pixelHeight = image.cgImage.map { CGFloat($0.height) } ?? (image.size.height * image.scale)
        let longestEdge = max(pixelWidth, pixelHeight)

        guard longestEdge > 0 else {
            return true
        }

        return longestEdge + 1 >= targetPixelSize
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
