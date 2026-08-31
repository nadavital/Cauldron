//
//  ImageCache.swift
//  Cauldron
//
//  Two-tier cache for images: L1 (memory) + L2 (disk) for persistence across app launches
//

import UIKit
import os
import CryptoKit

nonisolated private final class ImageCacheDiskCoordinator: @unchecked Sendable {
    private let diskQueue = DispatchQueue(
        label: "com.cauldron.image-cache.disk",
        qos: .utility
    )
    private let generationLock = NSLock()
    private var generations: [String: UInt] = [:]
    private var pendingWriteGenerations: [String: UInt] = [:]
    private var cacheEpoch: UInt = 0

    func generation(for key: String, advancing: Bool = false) -> UInt {
        generationLock.withLock {
            if advancing {
                generations[key, default: 0] &+= 1
                pendingWriteGenerations[key] = nil
            }
            return generations[key, default: 0]
        }
    }

    func isCurrent(_ generation: UInt, for key: String) -> Bool {
        generationLock.withLock { generations[key, default: 0] == generation }
    }

    func readToken(for key: String) -> (generation: UInt, epoch: UInt) {
        generationLock.withLock {
            (generations[key, default: 0], cacheEpoch)
        }
    }

    func isCurrent(_ token: (generation: UInt, epoch: UInt), for key: String) -> Bool {
        generationLock.withLock {
            generations[key, default: 0] == token.generation && cacheEpoch == token.epoch
        }
    }

    func beginWrite(for key: String) -> UInt {
        generationLock.withLock {
            generations[key, default: 0] &+= 1
            let generation = generations[key, default: 0]
            pendingWriteGenerations[key] = generation
            return generation
        }
    }

    func isWritePending(for key: String) -> Bool {
        generationLock.withLock { pendingWriteGenerations[key] != nil }
    }

    func finishWrite(_ generation: UInt, for key: String) {
        generationLock.withLock {
            guard pendingWriteGenerations[key] == generation else { return }
            pendingWriteGenerations[key] = nil
        }
    }

    func performDiskOperation<T: Sendable>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                continuation.resume(returning: operation())
            }
        }
    }

    func enqueueDiskOperation(_ operation: @escaping @Sendable () -> Void) {
        diskQueue.async(execute: operation)
    }

    func enqueueDiskOperationIfCurrent(
        _ generation: UInt,
        for key: String,
        operation: @escaping @Sendable () -> Void
    ) {
        diskQueue.async { [self] in
            guard isCurrent(generation, for: key) else { return }
            operation()
        }
    }

    func invalidate(_ keys: some Sequence<String>) {
        generationLock.withLock {
            for key in keys {
                generations[key, default: 0] &+= 1
                pendingWriteGenerations[key] = nil
            }
        }
    }

    func invalidateAllReads() {
        generationLock.withLock {
            cacheEpoch &+= 1
        }
    }
}

/// Shared two-tier cache for loaded images
/// L1: In-memory NSCache with size limits
/// L2: Persistent disk cache in Library/Caches/
class ImageCache {
    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage>
    private let diskCacheDirectory: URL
    private var trackedKeys = Set<String>()
    private let trackedKeysLock = NSLock()
    private let diskCoordinator = ImageCacheDiskCoordinator()

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
        let diskCoordinator = diskCoordinator
        diskCoordinator.enqueueDiskOperation {
            Self.cleanExpiredDiskCache(
                in: diskCacheDirectory,
                maxDiskCacheAge: maxDiskCacheAge
            )
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
        let readToken = diskCoordinator.readToken(for: key)
        guard !diskCoordinator.isWritePending(for: key) else { return nil }
        let diskCoordinator = diskCoordinator
        let diskImage = await diskCoordinator.performDiskOperation {
            Self.loadFromDisk(at: fileURL)
        }

        guard let diskImage,
              !diskCoordinator.isWritePending(for: key),
              diskCoordinator.isCurrent(readToken, for: key) else {
            return nil
        }

        memoryCache.setObject(diskImage, forKey: key as NSString, cost: estimateImageCost(diskImage))
        track(key)
        return diskImage
    }

    func set(_ key: String, image: UIImage) {
        let generation = diskCoordinator.beginWrite(for: key)
        let cacheKey = key as NSString
        let cost = estimateImageCost(image)

        memoryCache.setObject(image, forKey: cacheKey, cost: cost)
        track(key)

        let fileURL = diskCacheURL(for: key)
        let diskCoordinator = diskCoordinator
        Task.detached(priority: .background) {
            guard let data = image.jpegData(compressionQuality: 0.8) else {
                diskCoordinator.finishWrite(generation, for: key)
                return
            }
            diskCoordinator.enqueueDiskOperationIfCurrent(generation, for: key) {
                defer { diskCoordinator.finishWrite(generation, for: key) }
                try? FileManager.default.removeItem(at: fileURL)
                Self.saveToDisk(data: data, at: fileURL)
            }
        }
    }

    func remove(_ key: String) {
        let generation = diskCoordinator.generation(for: key, advancing: true)
        memoryCache.removeObject(forKey: key as NSString)
        untrack(key)
        let fileURL = diskCacheURL(for: key)
        diskCoordinator.enqueueDiskOperationIfCurrent(generation, for: key) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func clear() {
        diskCoordinator.invalidateAllReads()
        diskCoordinator.invalidate(trackedKeysSnapshot())
        memoryCache.removeAllObjects()
        replaceTrackedKeys(with: Set<String>())

        let diskCacheDirectory = diskCacheDirectory
        let logger = logger
        diskCoordinator.enqueueDiskOperation {
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
    }

    func clearProfileImages() {
        remove(keys: trackedKeysSnapshot().filter { $0.hasPrefix("profile_") })
    }

    func clearRecipeImages() {
        remove(keys: trackedKeysSnapshot().filter { $0.hasPrefix("recipe_") || $0.hasPrefix("image_") })
    }

    /// Remove every rendered size for one recipe. CloudKit may replace an
    /// asset in place, so record names alone are not sufficient cache keys.
    func clearRecipeImages(for recipeID: UUID) {
        let prefix = "recipe_\(recipeID.uuidString)_"
        var keys = Set(trackedKeysSnapshot().filter { $0.hasPrefix(prefix) })
        for variant in ["hero", "card", "thumbnail", "collectionTile", "preview", "full"] {
            keys.insert(Self.recipeImageKey(recipeId: recipeID, variant: variant))
        }
        remove(keys: keys)
    }

    /// Test/support barrier for callers that must observe completed disk work.
    /// Production rendering never waits on this path.
    func waitForPendingDiskOperations() async {
        await diskCoordinator.performDiskOperation { () }
    }

    nonisolated static func profileImageKey(userId: UUID) -> String {
        "profile_\(userId.uuidString)"
    }

    nonisolated static func profileImageKey(for photo: ProfileAvatarRepresentation.PhotoIdentity) -> String {
        let digest = SHA256.hash(data: Data(photo.cacheIdentity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "profile_\(photo.ownerID.uuidString)_\(digest)"
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
        let keys = Array(keys)
        let generations = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, diskCoordinator.generation(for: key, advancing: true))
        })
        for key in keys {
            memoryCache.removeObject(forKey: key as NSString)
            untrack(key)
            let fileURL = diskCacheURL(for: key)
            if let generation = generations[key] {
                diskCoordinator.enqueueDiskOperationIfCurrent(generation, for: key) {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }

        if !keys.isEmpty {
            logger.info("🗑️ Cleared \(keys.count) cached images")
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

    private nonisolated static func saveToDisk(data: Data, at fileURL: URL) {
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
