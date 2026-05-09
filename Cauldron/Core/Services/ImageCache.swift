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
class ImageCache {
    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage>
    private let diskCacheDirectory: URL
    private var trackedKeys = Set<String>()
    private let trackedKeysLock = NSLock()

    private let logger = Logger(subsystem: "com.cauldron", category: "ImageCache")

    private let maxMemoryCacheCount = 100
    private let maxMemoryCacheCost = 50 * 1024 * 1024
    private let maxDiskCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        memoryCache = NSCache<NSString, UIImage>()
        memoryCache.countLimit = maxMemoryCacheCount
        memoryCache.totalCostLimit = maxMemoryCacheCost

        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            diskCacheDirectory = cachesDir.appendingPathComponent("ProfileImageCache", isDirectory: true)
        } else {
            diskCacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ProfileImageCache", isDirectory: true)
            logger.warning("Caches directory unavailable, using temp directory for image cache")
        }

        if !FileManager.default.fileExists(atPath: diskCacheDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: diskCacheDirectory, withIntermediateDirectories: true)
            } catch {
                logger.error("Failed to create disk cache directory: \(error.localizedDescription)")
            }
        }

        let diskCacheDirectory = diskCacheDirectory
        let maxDiskCacheAge = maxDiskCacheAge
        Task.detached(priority: .background) {
            Self.cleanExpiredDiskCache(in: diskCacheDirectory, maxDiskCacheAge: maxDiskCacheAge)
        }
    }

    /// Immediate lookup for render-critical callers. Memory only.
    func get(_ key: String) -> UIImage? {
        let cacheKey = key as NSString
        if let memoryImage = memoryCache.object(forKey: cacheKey) {
            track(key)
            return memoryImage
        }
        return nil
    }

    /// Async cache lookup that can promote a disk hit back into memory.
    func load(_ key: String) async -> UIImage? {
        if let cachedImage = get(key) {
            return cachedImage
        }

        return await getFromDisk(key)
    }

    /// Load a cached image from disk on a background queue and promote it to memory.
    func getFromDisk(_ key: String) async -> UIImage? {
        let fileURL = diskCacheURL(for: key)
        let diskImage = await Task.detached(priority: .utility) {
            Self.loadFromDisk(at: fileURL)
        }.value

        guard let diskImage else {
            return nil
        }

        memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateImageCost(diskImage))
        track(key)
        return diskImage
    }

    func set(_ key: String, image: UIImage) {
        let cacheKey = key as NSString
        let cost = estimateImageCost(image)

        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        track(key)

        let fileURL = diskCacheURL(for: key)
        Task.detached(priority: .background) {
            Self.saveToDisk(image: image, at: fileURL)
        }
    }

    func remove(_ key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        untrack(key)
        try? FileManager.default.removeItem(at: diskCacheURL(for: key))
    }

    func clear() {
        memoryCache.removeAllObjects()
        replaceTrackedKeys(with: Set<String>())

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

    func clearProfileImages() {
        remove(keys: trackedKeysSnapshot().filter { $0.hasPrefix("profile_") })
    }

    func clearRecipeImages() {
        remove(keys: trackedKeysSnapshot().filter { $0.hasPrefix("recipe_") || $0.hasPrefix("image_") })
    }

    nonisolated static func profileImageKey(userId: UUID) -> String {
        "profile_\(userId.uuidString)"
    }

    nonisolated static func recipeImageKey(recipeId: UUID, variant: String = "default") -> String {
        "recipe_\(recipeId.uuidString)_\(variant)"
    }

    nonisolated static func collectionImageKey(collectionId: UUID) -> String {
        "collection_\(collectionId.uuidString)"
    }

    private func diskCacheURL(for key: String) -> URL {
        let hash = md5Hash(key)
        return diskCacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func estimateImageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func remove(keys: some Sequence<String>) {
        var removedCount = 0
        for key in keys {
            memoryCache.removeObject(forKey: key as NSString)
            untrack(key)
            try? FileManager.default.removeItem(at: diskCacheURL(for: key))
            removedCount += 1
        }

        if removedCount > 0 {
            logger.info("🗑️ Cleared \(removedCount) cached images")
        }
    }

    private func track(_ key: String) {
        trackedKeysLock.lock()
        trackedKeys.insert(key)
        trackedKeysLock.unlock()
    }

    private func untrack(_ key: String) {
        trackedKeysLock.lock()
        trackedKeys.remove(key)
        trackedKeysLock.unlock()
    }

    private func trackedKeysSnapshot() -> [String] {
        trackedKeysLock.lock()
        let keys = Array(trackedKeys)
        trackedKeysLock.unlock()
        return keys
    }

    private func replaceTrackedKeys(with keys: Set<String>) {
        trackedKeysLock.lock()
        trackedKeys = keys
        trackedKeysLock.unlock()
    }

    private nonisolated static func loadFromDisk(at fileURL: URL) -> UIImage? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return autoreleasepool {
            guard let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) else {
                return nil
            }
            return image
        }
    }

    private nonisolated static func saveToDisk(image: UIImage, at fileURL: URL) {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Disk write failures are non-fatal.
        }
    }

    private nonisolated static func cleanExpiredDiskCache(in diskCacheDirectory: URL, maxDiskCacheAge: TimeInterval) {
        let fileManager = FileManager.default
        let expirationDate = Date().addingTimeInterval(-maxDiskCacheAge)

        do {
            let files = try fileManager.contentsOfDirectory(
                at: diskCacheDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )

            for fileURL in files {
                let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path)
                if let modificationDate = attributes?[.modificationDate] as? Date,
                   modificationDate < expirationDate {
                    try? fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
            // Ignore cleanup errors.
        }
    }
}
