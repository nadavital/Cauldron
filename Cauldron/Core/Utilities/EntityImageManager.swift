//
//  EntityImageManager.swift
//  Cauldron
//
//  Unified image manager that handles local storage and CloudKit sync
//  for all entity images (recipes, profiles, collections).
//
//  This eliminates duplication between ImageManager, ProfileImageManager,
//  and CollectionImageManager by providing a single, configurable implementation.
//

import Foundation
import UIKit
import SwiftUI
import CloudKit
import os

// MARK: - ImageManageable Protocol

/// Protocol for entities that can have managed images
protocol ImageManageable: Sendable {
    var id: UUID { get }
}

// MARK: - EntityImageManager

/// Unified actor for managing entity images with local storage and CloudKit sync.
///
/// This replaces the duplicate code in ImageManager, ProfileImageManager, and
/// CollectionImageManager with a single, configurable implementation.
///
/// Usage:
/// ```swift
/// let profileManager = EntityImageManager<User>(
///     directoryName: "ProfileImages",
///     maxDimension: 800,
///     targetSizeBytes: 1_000_000,
///     cloudUpload: { id, data in try await userService.uploadProfileImage(userId: id, imageData: data) },
///     cloudDownload: { id in try await userService.downloadProfileImage(userId: id) }
/// )
/// ```
actor EntityImageManager<Entity: ImageManageable> {
    private let imageDirectoryURL: URL
    private let directoryName: String
    private let maxDimension: CGFloat
    private let targetSizeBytes: Int
    private let logger: Logger

    /// Optional cache key generator for ImageCache integration
    private let cacheKeyGenerator: ((UUID) -> String)?

    /// Track in-flight downloads to prevent duplicate requests
    private var inFlightDownloads: [UUID: Task<URL?, Error>] = [:]

    /// Track in-flight database-aware downloads (key: "entityId-public" or "entityId-private")
    private var inFlightDatabaseDownloads: [String: Task<String?, Error>] = [:]

    /// Cache for "not found" results to avoid repeated CloudKit lookups
    /// Key: "entityId-public" or "entityId-private", Value: timestamp when cached
    private var notFoundCache: [String: Date] = [:]

    /// How long to cache "not found" results (5 minutes)
    private let notFoundCacheDuration: TimeInterval = 300

    // Cloud upload/download closures (dependency injection)
    private let uploadToCloud: ((UUID, Data) async throws -> String)?
    private let downloadFromCloud: ((UUID) async throws -> Data?)?
    private let deleteFromCloud: ((UUID) async throws -> Void)?

    // Database-aware cloud operations for recipes
    private let uploadToCloudWithDatabase: ((UUID, Data, Bool) async throws -> String)?
    private let downloadFromCloudWithDatabase: ((UUID, Bool) async throws -> Data?)?

    /// Initialize with configuration
    /// - Parameters:
    ///   - directoryName: Name of directory to store images (e.g., "ProfileImages")
    ///   - maxDimension: Maximum width/height for image resizing
    ///   - targetSizeBytes: Target file size for compression
    ///   - cacheKeyGenerator: Optional closure to generate cache keys for ImageCache
    ///   - uploadToCloud: Optional closure to upload image to CloudKit
    ///   - downloadFromCloud: Optional closure to download image from CloudKit
    ///   - deleteFromCloud: Optional closure to delete image from CloudKit
    ///   - uploadToCloudWithDatabase: Optional closure for database-aware uploads (recipes)
    ///   - downloadFromCloudWithDatabase: Optional closure for database-aware downloads (recipes)
    init(
        directoryName: String,
        maxDimension: CGFloat = 800,
        targetSizeBytes: Int = 1_000_000,
        cacheKeyGenerator: ((UUID) -> String)? = nil,
        uploadToCloud: ((UUID, Data) async throws -> String)? = nil,
        downloadFromCloud: ((UUID) async throws -> Data?)? = nil,
        deleteFromCloud: ((UUID) async throws -> Void)? = nil,
        uploadToCloudWithDatabase: ((UUID, Data, Bool) async throws -> String)? = nil,
        downloadFromCloudWithDatabase: ((UUID, Bool) async throws -> Data?)? = nil
    ) {
        self.directoryName = directoryName
        self.maxDimension = maxDimension
        self.targetSizeBytes = targetSizeBytes
        self.cacheKeyGenerator = cacheKeyGenerator
        self.uploadToCloud = uploadToCloud
        self.downloadFromCloud = downloadFromCloud
        self.deleteFromCloud = deleteFromCloud
        self.uploadToCloudWithDatabase = uploadToCloudWithDatabase
        self.downloadFromCloudWithDatabase = downloadFromCloudWithDatabase
        self.logger = Logger(subsystem: "com.cauldron", category: "EntityImageManager-\(directoryName)")

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            // Use a fallback instead of fatalError for robustness
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
            self.imageDirectoryURL = tempURL
            self.logger.error("Unable to access documents directory, using temp: \(tempURL.path)")
            return
        }
        self.imageDirectoryURL = documentsURL.appendingPathComponent(directoryName, isDirectory: true)

        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try? fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Local Storage

    /// Save image locally and return the file URL
    func saveImage(_ image: UIImage, for entity: Entity) throws -> URL {
        try saveImage(image, entityId: entity.id)
    }

    /// Save image locally by entity ID and return URL
    func saveImage(_ image: UIImage, entityId: UUID) throws -> URL {
        // Ensure directory exists (in case it was deleted)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }

        // Optimize and compress image
        let optimizedData = try optimizeImageForUpload(image)

        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        try optimizedData.write(to: fileURL)
        return fileURL
    }

    /// Save image locally by entity ID and return filename (for recipe compatibility)
    func saveImageReturningFilename(_ image: UIImage, entityId: UUID) throws -> String {
        let url = try saveImage(image, entityId: entityId)
        return url.lastPathComponent
    }

    /// Load image for an entity
    func loadImage(for entity: Entity) -> UIImage? {
        loadImage(entityId: entity.id)
    }

    /// Load image by entity ID
    func loadImage(entityId: UUID) -> UIImage? {
        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }

    /// Delete local image file
    func deleteImage(for entity: Entity) {
        deleteImage(entityId: entity.id)
    }

    /// Delete local image by entity ID
    func deleteImage(entityId: UUID) {
        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)

        // Clear from ImageCache if cache key generator is configured
        if let cacheKeyGenerator = cacheKeyGenerator {
            Task { @MainActor in
                ImageCache.shared.remove(cacheKeyGenerator(entityId))
            }
        }
    }

    /// Get full file URL for an entity
    func imageURL(for entity: Entity) -> URL {
        imageURL(entityId: entity.id)
    }

    /// Get full file URL by entity ID
    func imageURL(entityId: UUID) -> URL {
        let filename = "\(entityId.uuidString).jpg"
        return imageDirectoryURL.appendingPathComponent(filename)
    }

    /// Get full file URL by filename
    func imageURL(for filename: String) -> URL {
        imageDirectoryURL.appendingPathComponent(filename)
    }

    /// Check if image exists locally
    func imageExists(for entity: Entity) -> Bool {
        imageExists(entityId: entity.id)
    }

    /// Check if image exists locally by entity ID
    func imageExists(entityId: UUID) -> Bool {
        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get modification date of local image file
    func getImageModificationDate(for entity: Entity) -> Date? {
        getImageModificationDate(entityId: entity.id)
    }

    /// Get modification date by entity ID
    func getImageModificationDate(entityId: UUID) -> Date? {
        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return modificationDate
    }

    // MARK: - URL Download (for recipes)

    /// Download image from URL and save it locally
    /// - Parameters:
    ///   - url: The URL to download from
    ///   - entityId: The entity ID to save as
    /// - Returns: The filename of the saved image
    func downloadAndSaveImage(from url: URL, entityId: UUID) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let mimeType = httpResponse.mimeType,
              mimeType.hasPrefix("image/") else {
            throw EntityImageError.downloadFailed
        }

        guard let image = UIImage(data: data) else {
            throw EntityImageError.invalidImageData
        }

        return try saveImageReturningFilename(image, entityId: entityId)
    }

    /// Copy image from one entity to another
    /// - Parameters:
    ///   - sourceId: The source entity ID
    ///   - targetId: The target entity ID
    /// - Returns: The filename of the copied image, or nil if source doesn't exist
    func copyImage(from sourceId: UUID, to targetId: UUID) throws -> String? {
        let sourceFilename = "\(sourceId.uuidString).jpg"
        let targetFilename = "\(targetId.uuidString).jpg"

        let sourceURL = imageDirectoryURL.appendingPathComponent(sourceFilename)
        let targetURL = imageDirectoryURL.appendingPathComponent(targetFilename)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        // Remove existing target if present
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        return targetFilename
    }

    // MARK: - Cloud Sync

    /// Upload image to CloudKit
    /// - Parameter entityId: The entity ID this image belongs to
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageToCloud(entityId: UUID) async throws -> String {
        guard let uploadToCloud = uploadToCloud else {
            throw EntityImageError.cloudNotConfigured
        }

        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw EntityImageError.saveFailed
        }

        logger.info("Uploading image to CloudKit for entity \(entityId)")
        return try await uploadToCloud(entityId, imageData)
    }

    /// Upload image to CloudKit with database selection (for recipes)
    /// - Parameters:
    ///   - entityId: The entity ID this image belongs to
    ///   - toPublic: Whether to upload to public database
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageToCloud(entityId: UUID, toPublic: Bool) async throws -> String {
        guard let uploadToCloudWithDatabase = uploadToCloudWithDatabase else {
            throw EntityImageError.cloudNotConfigured
        }

        let filename = "\(entityId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw EntityImageError.saveFailed
        }

        logger.info("Uploading image to CloudKit for entity \(entityId) (public: \(toPublic))")
        return try await uploadToCloudWithDatabase(entityId, imageData, toPublic)
    }

    /// Download image from CloudKit and save locally
    /// - Parameter entityId: The entity ID to download image for
    /// - Returns: The local URL, or nil if no image exists
    ///
    /// This method uses request coalescing - if a download for the same entityId
    /// is already in progress, new requests will await that instead of starting
    /// a duplicate download.
    func downloadImageFromCloud(entityId: UUID) async throws -> URL? {
        let cacheKey = "\(entityId.uuidString)-default"

        // Check "not found" cache first
        if let cachedTime = notFoundCache[cacheKey] {
            let age = Date().timeIntervalSince(cachedTime)
            if age < notFoundCacheDuration {
                return nil
            } else {
                notFoundCache.removeValue(forKey: cacheKey)
            }
        }

        // Check if download is already in progress
        if let existingTask = inFlightDownloads[entityId] {
            logger.debug("Download already in progress for entity \(entityId), awaiting existing task")
            return try await existingTask.value
        }

        guard let downloadFromCloud = downloadFromCloud else {
            throw EntityImageError.cloudNotConfigured
        }

        // Create and store the task IMMEDIATELY to prevent race conditions
        let downloadTask = Task<URL?, Error> { [cacheKey] in
            guard let imageData = try await downloadFromCloud(entityId) else {
                self.notFoundCache[cacheKey] = Date()
                return nil
            }

            guard let image = UIImage(data: imageData) else {
                throw EntityImageError.invalidImageData
            }

            let fileURL = try self.saveImage(image, entityId: entityId)
            return fileURL
        }

        // Store immediately after creation, before awaiting
        inFlightDownloads[entityId] = downloadTask

        do {
            let result = try await downloadTask.value
            inFlightDownloads.removeValue(forKey: entityId)
            return result
        } catch {
            inFlightDownloads.removeValue(forKey: entityId)
            throw error
        }
    }

    /// Clear the "not found" cache for an entity (call after uploading an image)
    func clearNotFoundCache(entityId: UUID) {
        notFoundCache.removeValue(forKey: "\(entityId.uuidString)-default")
        notFoundCache.removeValue(forKey: "\(entityId.uuidString)-public")
        notFoundCache.removeValue(forKey: "\(entityId.uuidString)-private")
    }

    /// Clear all "not found" cache entries (useful after network recovery)
    func clearAllNotFoundCache() {
        notFoundCache.removeAll()
    }

    /// Download image from CloudKit with database selection (for recipes)
    /// - Parameters:
    ///   - entityId: The entity ID to download image for
    ///   - fromPublic: Whether to download from public database
    /// - Returns: The filename, or nil if no image exists
    ///
    /// This method uses request coalescing and "not found" caching to prevent
    /// redundant CloudKit requests.
    func downloadImageFromCloud(entityId: UUID, fromPublic: Bool) async throws -> String? {
        let cacheKey = "\(entityId.uuidString)-\(fromPublic ? "public" : "private")"

        // Check "not found" cache first
        if let cachedTime = notFoundCache[cacheKey] {
            let age = Date().timeIntervalSince(cachedTime)
            if age < notFoundCacheDuration {
                return nil
            } else {
                notFoundCache.removeValue(forKey: cacheKey)
            }
        }

        // Check if download is already in progress
        if let existingTask = inFlightDatabaseDownloads[cacheKey] {
            logger.debug("Download already in progress for entity \(entityId) (public: \(fromPublic)), awaiting existing task")
            return try await existingTask.value
        }

        guard let downloadFromCloudWithDatabase = downloadFromCloudWithDatabase else {
            throw EntityImageError.cloudNotConfigured
        }

        // Create and store the task IMMEDIATELY to prevent race conditions
        // The task must be stored before any suspension point
        let downloadTask = Task<String?, Error> { [cacheKey] in
            guard let imageData = try await downloadFromCloudWithDatabase(entityId, fromPublic) else {
                // Cache the "not found" result
                self.notFoundCache[cacheKey] = Date()
                return nil
            }

            guard let image = UIImage(data: imageData) else {
                throw EntityImageError.invalidImageData
            }

            return try self.saveImageReturningFilename(image, entityId: entityId)
        }

        // Store immediately after creation, before awaiting
        inFlightDatabaseDownloads[cacheKey] = downloadTask

        do {
            let result = try await downloadTask.value
            inFlightDatabaseDownloads.removeValue(forKey: cacheKey)
            return result
        } catch {
            inFlightDatabaseDownloads.removeValue(forKey: cacheKey)
            throw error
        }
    }

    /// Delete image from CloudKit
    func deleteImageFromCloud(entityId: UUID) async throws {
        guard let deleteFromCloud = deleteFromCloud else {
            throw EntityImageError.cloudNotConfigured
        }

        logger.info("Deleting image from CloudKit for entity \(entityId)")
        try await deleteFromCloud(entityId)
    }

    // MARK: - Image Optimization

    /// Optimize image for upload
    /// - Parameter image: The image to optimize
    /// - Returns: Optimized image data
    /// - Throws: EntityImageError if optimization fails
    func optimizeImageForUpload(_ image: UIImage) throws -> Data {
        let maxSizeBytes = 10_000_000 // 10MB absolute max for CloudKit

        // Resize to max dimension
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        var processedImage = image
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            if let resizedImage = UIGraphicsGetImageFromCurrentImageContext() {
                processedImage = resizedImage
            }
            UIGraphicsEndImageContext()
        }

        // Try 80% quality compression first
        if let data = processedImage.jpegData(compressionQuality: 0.8) {
            if data.count <= targetSizeBytes {
                return data
            }
        }

        // Try 60% compression
        if let compressedData = processedImage.jpegData(compressionQuality: 0.6),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        // Try 40% compression as last resort
        if let compressedData = processedImage.jpegData(compressionQuality: 0.4),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        throw EntityImageError.compressionFailed
    }
}

// MARK: - Errors

enum EntityImageError: Error, LocalizedError {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
    case cloudNotConfigured

    var errorDescription: String? {
        switch self {
        case .compressionFailed: return "Failed to compress image"
        case .saveFailed: return "Failed to save image"
        case .downloadFailed: return "Failed to download image"
        case .invalidImageData: return "Invalid image data"
        case .cloudNotConfigured: return "Cloud storage not configured"
        }
    }
}

// MARK: - ImageManageable Conformances

extension User: ImageManageable {}

extension Collection: ImageManageable {}

/// Recipe conformance for EntityImageManager
struct RecipeImageEntity: ImageManageable {
    let id: UUID
}

// MARK: - Type Aliases

/// Recipe image manager
typealias RecipeImageManager = EntityImageManager<RecipeImageEntity>

/// Profile image manager
typealias ProfileImageManagerV2 = EntityImageManager<User>

/// Collection image manager
typealias CollectionImageManagerV2 = EntityImageManager<Collection>

// MARK: - Factory Functions

/// Create a recipe image manager with RecipeCloudService integration
func createRecipeImageManager(recipeService: RecipeCloudService) -> RecipeImageManager {
    RecipeImageManager(
        directoryName: "RecipeImages",
        maxDimension: 2000,
        targetSizeBytes: 5_000_000,
        cacheKeyGenerator: nil,
        uploadToCloud: nil,
        downloadFromCloud: nil,
        deleteFromCloud: nil,
        uploadToCloudWithDatabase: { recipeId, data, toPublic in
            try await recipeService.uploadImageAsset(recipeId: recipeId, imageData: data, toPublic: toPublic)
        },
        downloadFromCloudWithDatabase: { recipeId, fromPublic in
            try await recipeService.downloadImageAsset(recipeId: recipeId, fromPublic: fromPublic)
        }
    )
}

/// Create a profile image manager with UserCloudService integration
func createProfileImageManager(userService: UserCloudService) -> ProfileImageManagerV2 {
    ProfileImageManagerV2(
        directoryName: "ProfileImages",
        maxDimension: 800,
        targetSizeBytes: 1_000_000,
        cacheKeyGenerator: { userId in
            ImageCache.profileImageKey(userId: userId)
        },
        uploadToCloud: { userId, data in
            try await userService.uploadUserProfileImage(userId: userId, imageData: data)
        },
        downloadFromCloud: { userId in
            try await userService.downloadUserProfileImage(userId: userId)
        },
        deleteFromCloud: { userId in
            try await userService.deleteUserProfileImage(userId: userId)
        }
    )
}

/// Create a collection cover image manager with CollectionCloudService integration
func createCollectionImageManager(collectionService: CollectionCloudService) -> CollectionImageManagerV2 {
    CollectionImageManagerV2(
        directoryName: "CollectionImages",
        maxDimension: 1200,
        targetSizeBytes: 2_000_000,
        cacheKeyGenerator: { collectionId in
            ImageCache.collectionImageKey(collectionId: collectionId)
        },
        uploadToCloud: { collectionId, data in
            try await collectionService.uploadCollectionCoverImage(collectionId: collectionId, imageData: data)
        },
        downloadFromCloud: { collectionId in
            try await collectionService.downloadCollectionCoverImage(collectionId: collectionId)
        },
        deleteFromCloud: nil  // Collection images are deleted when the collection is deleted
    )
}

// MARK: - Recipe-Specific Convenience Methods

extension RecipeImageManager {
    /// Save image and return filename (recipe API compatibility)
    func saveImage(_ image: UIImage, recipeId: UUID) throws -> String {
        try saveImageReturningFilename(image, entityId: recipeId)
    }

    /// Load image by recipe ID
    func loadImage(recipeId: UUID) -> UIImage? {
        loadImage(entityId: recipeId)
    }

    /// Delete image by recipe ID
    func deleteImage(recipeId: UUID) {
        deleteImage(entityId: recipeId)
    }

    /// Get image URL for recipe
    func imageURL(recipeId: UUID) -> URL {
        imageURL(entityId: recipeId)
    }

    /// Check if image exists for recipe
    func imageExists(recipeId: UUID) -> Bool {
        imageExists(entityId: recipeId)
    }

    /// Get image modification date for recipe
    func getImageModificationDate(recipeId: UUID) -> Date? {
        getImageModificationDate(entityId: recipeId)
    }

    /// Download and save image from URL for recipe
    func downloadAndSaveImage(from url: URL, recipeId: UUID) async throws -> String {
        try await downloadAndSaveImage(from: url, entityId: recipeId)
    }

    /// Copy image from one recipe to another
    func copyImageForRecipe(from sourceId: UUID, to targetId: UUID) throws -> String? {
        try copyImage(from: sourceId, to: targetId)
    }

    /// Upload image to CloudKit for recipe (database-aware)
    func uploadImageToCloud(recipeId: UUID, toPublic: Bool) async throws -> String {
        try await uploadImageToCloud(entityId: recipeId, toPublic: toPublic)
    }

    /// Download image from CloudKit for recipe (database-aware)
    func downloadImageFromCloud(recipeId: UUID, fromPublic: Bool) async throws -> String? {
        try await downloadImageFromCloud(entityId: recipeId, fromPublic: fromPublic)
    }
}

// MARK: - Profile-Specific Convenience Methods

extension ProfileImageManagerV2 {
    /// Save image for user and return URL
    func saveImage(_ image: UIImage, userId: UUID) throws -> URL {
        try saveImage(image, entityId: userId)
    }

    /// Load image by user ID
    func loadImage(userId: UUID) -> UIImage? {
        loadImage(entityId: userId)
    }

    /// Delete image by user ID
    func deleteImage(userId: UUID) {
        deleteImage(entityId: userId)
    }

    /// Get image URL for user
    func imageURL(for userId: UUID) -> URL {
        imageURL(entityId: userId)
    }

    /// Check if image exists for user
    func imageExists(userId: UUID) -> Bool {
        imageExists(entityId: userId)
    }

    /// Get image modification date for user
    func getImageModificationDate(userId: UUID) -> Date? {
        getImageModificationDate(entityId: userId)
    }

    /// Upload image to CloudKit for user
    func uploadImageToCloud(userId: UUID) async throws -> String {
        try await uploadImageToCloud(entityId: userId)
    }

    /// Download image from CloudKit for user
    func downloadImageFromCloud(userId: UUID) async throws -> URL? {
        try await downloadImageFromCloud(entityId: userId)
    }

    /// Delete image from CloudKit for user
    func deleteImageFromCloud(userId: UUID) async throws {
        try await deleteImageFromCloud(entityId: userId)
    }
}

// MARK: - Collection-Specific Convenience Methods

extension CollectionImageManagerV2 {
    /// Save image for collection and return URL
    func saveImage(_ image: UIImage, collectionId: UUID) throws -> URL {
        try saveImage(image, entityId: collectionId)
    }

    /// Load image by collection ID
    func loadImage(collectionId: UUID) -> UIImage? {
        loadImage(entityId: collectionId)
    }

    /// Delete image by collection ID
    func deleteImage(collectionId: UUID) {
        deleteImage(entityId: collectionId)
    }

    /// Get image URL for collection
    func imageURL(for collectionId: UUID) -> URL {
        imageURL(entityId: collectionId)
    }

    /// Check if image exists for collection
    func imageExists(collectionId: UUID) -> Bool {
        imageExists(entityId: collectionId)
    }

    /// Get image modification date for collection
    func getImageModificationDate(collectionId: UUID) -> Date? {
        getImageModificationDate(entityId: collectionId)
    }

    /// Upload image to CloudKit for collection
    func uploadImageToCloud(collectionId: UUID) async throws -> String {
        try await uploadImageToCloud(entityId: collectionId)
    }

    /// Download image from CloudKit for collection
    func downloadImageFromCloud(collectionId: UUID) async throws -> URL? {
        try await downloadImageFromCloud(entityId: collectionId)
    }
}
