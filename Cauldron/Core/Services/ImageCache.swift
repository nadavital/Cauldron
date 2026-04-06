//
//  ImageCache.swift
//  Cauldron
//
//  Two-tier cache for images: L1 (memory) + L2 (disk) for persistence across app launches
//

import UIKit
import os
import CryptoKit

/// Shared two-tier cache for loaded images
/// L1: In-memory NSCache with size limits
/// L2: Persistent disk cache in Library/Caches/
@MainActor
class ImageCache {
    static let shared = ImageCache()

    // L1: Memory cache with automatic eviction
    private let memoryCache: NSCache<NSString, UIImage>

    // L2: Disk cache directory
    private let diskCacheDirectory: URL
    private var trackedKeys = Set<String>()

    private let logger = Logger(subsystem: "com.cauldron", category: "ImageCache")

    // Memory cache limits
    private let maxMemoryCacheCount = 100
    private let maxMemoryCacheCost = 50 * 1024 * 1024 // 50MB

    // Disk cache limits
    private let maxDiskCacheAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    private init() {
        // Initialize memory cache with limits
        memoryCache = NSCache<NSString, UIImage>()
        memoryCache.countLimit = maxMemoryCacheCount
        memoryCache.totalCostLimit = maxMemoryCacheCost

        // Initialize disk cache directory with fallback to temp directory
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            diskCacheDirectory = cachesDir.appendingPathComponent("ProfileImageCache", isDirectory: true)
        } else {
            // Fallback to temp directory if caches unavailable (extremely rare)
            diskCacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ProfileImageCache", isDirectory: true)
            logger.warning("Caches directory unavailable, using temp directory for image cache")
        }

        // Create disk cache directory if needed
        if !FileManager.default.fileExists(atPath: diskCacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create disk cache directory: \(error.localizedDescription)")
            }
        }

        // Clean old disk cache entries on init (async to not block startup)
        Task.detached(priority: .background) {
            await self.cleanExpiredDiskCache()
        }
    }

    /// Get cached image for a key
    /// Checks L1 (memory) first, then L2 (disk)
    func get(_ key: String) -> UIImage? {
        let cacheKey = key as NSString

        // L1: Check memory cache first
        if let memoryImage = memoryCache.object(forKey: cacheKey) {
            trackedKeys.insert(key)
            return memoryImage
        }

        // L2: Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            // Promote to memory cache for faster future access
            let cost = estimateImageCost(diskImage)
            memoryCache.setObject(diskImage, forKey: cacheKey, cost: cost)
            trackedKeys.insert(key)
            return diskImage
        }

        return nil
    }

    /// Store image in cache (both L1 memory and L2 disk)
    func set(_ key: String, image: UIImage) {
        let cacheKey = key as NSString
        let cost = estimateImageCost(image)

        // L1: Store in memory cache
        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        trackedKeys.insert(key)

        // L2: Store to disk asynchronously
        Task.detached(priority: .background) {
            await self.saveToDisk(key: key, image: image)
        }
    }

    /// Remove image from cache (both L1 and L2)
    func remove(_ key: String) {
        let cacheKey = key as NSString

        // Remove from memory
        memoryCache.removeObject(forKey: cacheKey)
        trackedKeys.remove(key)

        // Remove from disk
        let fileURL = diskCacheURL(for: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Clear all cached images (both L1 and L2)
    func clear() {
        // Clear memory cache
        memoryCache.removeAllObjects()
        trackedKeys.removeAll()

        // Clear disk cache
        do {
            let files = try FileManager.default.contentsOfDirectory(at: diskCacheDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
            logger.info("🗑️ Cleared all cached images (memory + disk)")
        } catch {
            logger.error("Failed to clear disk cache: \(error.localizedDescription)")
        }
    }

    /// Clear all profile images from cache
    /// Useful when refreshing friend data to force reload
    func clearProfileImages() {
        remove(keys: trackedKeys.filter { $0.hasPrefix("profile_") })
    }

    /// Clear all recipe images from cache
    /// Useful when refreshing recipe data to force reload
    func clearRecipeImages() {
        remove(keys: trackedKeys.filter { $0.hasPrefix("recipe_") || $0.hasPrefix("image_") })
    }

    /// Generate cache key for user profile image
    static func profileImageKey(userId: UUID) -> String {
        return "profile_\(userId.uuidString)"
    }

    /// Generate cache key for recipe image
    static func recipeImageKey(recipeId: UUID, variant: String = "default") -> String {
        return "recipe_\(recipeId.uuidString)_\(variant)"
    }

    /// Generate cache key for collection cover image
    static func collectionImageKey(collectionId: UUID) -> String {
        return "collection_\(collectionId.uuidString)"
    }

    // MARK: - Private Helpers

    /// Generate disk cache URL for a key using MD5 hash
    private func diskCacheURL(for key: String) -> URL {
        let hash = md5Hash(key)
        return diskCacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// Generate MD5 hash of a string for use as filename
    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Estimate memory cost of an image in bytes
    private func estimateImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func remove(keys: some Sequence<String>) {
        var removedCount = 0
        for key in keys {
            memoryCache.removeObject(forKey: key as NSString)
            trackedKeys.remove(key)
            try? FileManager.default.removeItem(at: diskCacheURL(for: key))
            removedCount += 1
        }

        if removedCount > 0 {
            logger.info("🗑️ Cleared \(removedCount) cached images")
        }
    }

    /// Load image from disk cache
    private func loadFromDisk(key: String) -> UIImage? {
        let fileURL = diskCacheURL(for: key)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    /// Save image to disk cache
    private func saveToDisk(key: String, image: UIImage) async {
        let fileURL = diskCacheURL(for: key)

        // Compress to JPEG for smaller file size
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Don't log - disk write failures are not critical
        }
    }

    /// Clean expired entries from disk cache
    private func cleanExpiredDiskCache() async {
        let fileManager = FileManager.default
        let expirationDate = Date().addingTimeInterval(-maxDiskCacheAge)

        do {
            let files = try fileManager.contentsOfDirectory(
                at: diskCacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )

            var removedCount = 0
            for fileURL in files {
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes?[.modificationDate] as? Date,
                   modificationDate < expirationDate {
                    try? fileManager.removeItem(at: fileURL)
                    removedCount += 1
                }
            }

            if removedCount > 0 {
                logger.info("🧹 Cleaned \(removedCount) expired images from disk cache")
            }
        } catch {
            // Ignore errors during cleanup
        }
    }
}

private extension UIImage {
    var cacheCost: Int {
        guard let cgImage else {
            return 1
        }

        return cgImage.bytesPerRow * cgImage.height
    }
}
