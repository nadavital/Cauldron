//
//  ImageCache.swift
//  Cauldron
//
//  In-memory cache for loaded images to prevent redundant loading during navigation
//

import UIKit
import os

/// Shared in-memory cache for loaded images
@MainActor
class ImageCache {
    static let shared = ImageCache()

    private var cache: [String: UIImage] = [:]
    private let logger = Logger(subsystem: "com.cauldron", category: "ImageCache")

    private init() {}

    /// Get cached image for a key
    func get(_ key: String) -> UIImage? {
        return cache[key]
    }

    /// Store image in cache
    func set(_ key: String, image: UIImage) {
        cache[key] = image
        // Cached image (don't log routine operations)
    }

    /// Remove image from cache
    func remove(_ key: String) {
        cache.removeValue(forKey: key)
        // Removed cached image (don't log routine operations)
    }

    /// Clear all cached images
    func clear() {
        let count = cache.count
        cache.removeAll()
        logger.info("🗑️ Cleared \(count) cached images")
    }

    /// Clear all profile images from cache
    /// Useful when refreshing friend data to force reload
    func clearProfileImages() {
        let profileKeys = cache.keys.filter { $0.hasPrefix("profile_") }
        for key in profileKeys {
            cache.removeValue(forKey: key)
        }
        logger.info("🗑️ Cleared \(profileKeys.count) profile images from cache")
    }

    /// Clear all recipe images from cache
    /// Useful when refreshing recipe data to force reload
    func clearRecipeImages() {
        let recipeKeys = cache.keys.filter { $0.hasPrefix("recipe_") }
        for key in recipeKeys {
            cache.removeValue(forKey: key)
        }
        logger.info("🗑️ Cleared \(recipeKeys.count) recipe images from cache")
    }

    /// Generate cache key for user profile image
    static func profileImageKey(userId: UUID) -> String {
        return "profile_\(userId.uuidString)"
    }

    /// Generate cache key for recipe image
    static func recipeImageKey(recipeId: UUID) -> String {
        return "recipe_\(recipeId.uuidString)"
    }

    /// Generate cache key for collection cover image
    static func collectionImageKey(collectionId: UUID) -> String {
        return "collection_\(collectionId.uuidString)"
    }
}
