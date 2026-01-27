//
//  EntityImageManager.swift
//  Cauldron
//
//  Generic image manager that handles local storage and CloudKit sync
//  for entity images (profiles, collections, etc.)
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

/// Generic actor for managing entity images with local storage and CloudKit sync.
///
/// This replaces the duplicate code in ProfileImageManager and CollectionImageManager
/// with a single, configurable implementation.
///
/// Usage:
/// ```swift
/// let profileManager = EntityImageManager<User>(
///     directoryName: "ProfileImages",
///     maxDimension: 800,
///     targetSizeBytes: 1_000_000,
///     cloudService: userCloudService
/// )
/// ```
actor EntityImageManager<Entity: ImageManageable> {
    private let imageDirectoryURL: URL
    private let directoryName: String
    private let maxDimension: CGFloat
    private let targetSizeBytes: Int
    private let logger: Logger

    // Cloud upload/download closures (dependency injection)
    private let uploadToCloud: ((UUID, Data) async throws -> String)?
    private let downloadFromCloud: ((UUID) async throws -> Data?)?
    private let deleteFromCloud: ((UUID) async throws -> Void)?

    /// Initialize with configuration
    /// - Parameters:
    ///   - directoryName: Name of directory to store images (e.g., "ProfileImages")
    ///   - maxDimension: Maximum width/height for image resizing
    ///   - targetSizeBytes: Target file size for compression
    ///   - uploadToCloud: Optional closure to upload image to CloudKit
    ///   - downloadFromCloud: Optional closure to download image from CloudKit
    ///   - deleteFromCloud: Optional closure to delete image from CloudKit
    init(
        directoryName: String,
        maxDimension: CGFloat = 800,
        targetSizeBytes: Int = 1_000_000,
        uploadToCloud: ((UUID, Data) async throws -> String)? = nil,
        downloadFromCloud: ((UUID) async throws -> Data?)? = nil,
        deleteFromCloud: ((UUID) async throws -> Void)? = nil
    ) {
        self.directoryName = directoryName
        self.maxDimension = maxDimension
        self.targetSizeBytes = targetSizeBytes
        self.uploadToCloud = uploadToCloud
        self.downloadFromCloud = downloadFromCloud
        self.deleteFromCloud = deleteFromCloud
        self.logger = Logger(subsystem: "com.cauldron", category: "EntityImageManager-\(directoryName)")

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
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

    /// Save image locally by entity ID
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
        logger.info("✅ Saved image for entity \(entityId) at \(fileURL.path)")
        return fileURL
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

        logger.info("☁️ Uploading image to CloudKit for entity \(entityId)")
        return try await uploadToCloud(entityId, imageData)
    }

    /// Download image from CloudKit and save locally
    /// - Parameter entityId: The entity ID to download image for
    /// - Returns: The local URL, or nil if no image exists
    func downloadImageFromCloud(entityId: UUID) async throws -> URL? {
        guard let downloadFromCloud = downloadFromCloud else {
            throw EntityImageError.cloudNotConfigured
        }

        logger.info("☁️ Downloading image from CloudKit for entity \(entityId)")

        guard let imageData = try await downloadFromCloud(entityId) else {
            logger.info("No image found in CloudKit for entity \(entityId)")
            return nil
        }

        // Convert to UIImage
        guard let image = UIImage(data: imageData) else {
            throw EntityImageError.invalidImageData
        }

        // Save locally
        let fileURL = try await saveImage(image, entityId: entityId)
        logger.info("✅ Downloaded and saved image for entity \(entityId)")
        return fileURL
    }

    /// Delete image from CloudKit
    func deleteImageFromCloud(entityId: UUID) async throws {
        guard let deleteFromCloud = deleteFromCloud else {
            throw EntityImageError.cloudNotConfigured
        }

        logger.info("☁️ Deleting image from CloudKit for entity \(entityId)")
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

enum EntityImageError: Error {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
    case cloudNotConfigured
}

// MARK: - ImageManageable Conformances

extension User: ImageManageable {}

extension Collection: ImageManageable {}

// MARK: - Convenience Type Aliases

/// Profile image manager using generic EntityImageManager
typealias ProfileImageManagerNew = EntityImageManager<User>

/// Collection cover image manager using generic EntityImageManager
typealias CollectionImageManagerNew = EntityImageManager<Collection>

// MARK: - Factory Functions

/// Create a profile image manager with UserCloudService integration
func createProfileImageManager(userService: UserCloudService) -> EntityImageManager<User> {
    EntityImageManager<User>(
        directoryName: "ProfileImages",
        maxDimension: 800,
        targetSizeBytes: 1_000_000,
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
func createCollectionImageManager(collectionService: CollectionCloudService) -> EntityImageManager<Collection> {
    EntityImageManager<Collection>(
        directoryName: "CollectionImages",
        maxDimension: 1200,
        targetSizeBytes: 2_000_000,
        uploadToCloud: { collectionId, data in
            try await collectionService.uploadCollectionCoverImage(collectionId: collectionId, imageData: data)
        },
        downloadFromCloud: { collectionId in
            try await collectionService.downloadCollectionCoverImage(collectionId: collectionId)
        },
        deleteFromCloud: nil  // Collection images are deleted when the collection is deleted
    )
}
