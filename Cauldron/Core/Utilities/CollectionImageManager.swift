//
//  CollectionImageManager.swift
//  Cauldron
//
//  Manages collection cover image storage and retrieval
//

import Foundation
import UIKit
import SwiftUI
import CloudKit
import os

/// Manages collection cover image storage and retrieval
actor CollectionImageManager {
    private let imageDirectoryURL: URL
    private let cloudKitService: CloudKitService

    init(cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
        }
        self.imageDirectoryURL = documentsURL.appendingPathComponent("CollectionImages", isDirectory: true)

        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try? fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }
    }

    /// Save collection cover image and return local URL
    func saveImage(_ image: UIImage, collectionId: UUID) throws -> URL {
        // Ensure directory exists (in case it was deleted)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }

        // Optimize and compress image
        let optimizedData = try optimizeImageForUpload(image)

        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        try optimizedData.write(to: fileURL)
        AppLogger.general.info("✅ Saved collection cover image for \(collectionId) at \(fileURL.path)")
        return fileURL
    }

    /// Load image from collection ID
    func loadImage(collectionId: UUID) -> UIImage? {
        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }

    /// Delete collection cover image file and clear from cache
    func deleteImage(collectionId: UUID) {
        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)

        // Clear from ImageCache to prevent stale image display
        Task { @MainActor in
            let cacheKey = ImageCache.collectionImageKey(collectionId: collectionId)
            ImageCache.shared.remove(cacheKey)
        }
    }

    /// Get full file URL for a collection ID
    func imageURL(for collectionId: UUID) -> URL {
        let filename = "\(collectionId.uuidString).jpg"
        return imageDirectoryURL.appendingPathComponent(filename)
    }

    /// Check if collection cover image exists locally
    func imageExists(collectionId: UUID) -> Bool {
        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get modification date of local image file
    func getImageModificationDate(collectionId: UUID) -> Date? {
        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return modificationDate
    }

    // MARK: - Cloud Sync Methods

    /// Upload collection cover image to CloudKit
    /// - Parameter collectionId: The collection ID this image belongs to
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageToCloud(collectionId: UUID) async throws -> String {
        // Load image data from local storage
        let filename = "\(collectionId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw CollectionImageError.saveFailed
        }

        AppLogger.general.info("☁️ Uploading collection cover image to CloudKit for \(collectionId)")

        // Upload to CloudKit
        return try await cloudKitService.uploadCollectionCoverImage(collectionId: collectionId, imageData: imageData)
    }

    /// Download collection cover image from CloudKit and save locally
    /// - Parameter collectionId: The collection ID to download image for
    /// - Returns: The local URL, or nil if no image exists
    func downloadImageFromCloud(collectionId: UUID) async throws -> URL? {
        AppLogger.general.info("☁️ Downloading collection cover image from CloudKit for \(collectionId)")

        // Download from CloudKit
        guard let imageData = try await cloudKitService.downloadCollectionCoverImage(collectionId: collectionId) else {
            AppLogger.general.info("No collection cover image found in CloudKit for \(collectionId)")
            return nil
        }

        // Convert to UIImage
        guard let image = UIImage(data: imageData) else {
            throw CollectionImageError.invalidImageData
        }

        // Save locally
        let fileURL = try await saveImage(image, collectionId: collectionId)
        AppLogger.general.info("✅ Downloaded and saved collection cover image for \(collectionId)")
        return fileURL
    }

    // MARK: - Helper Methods

    /// Optimize image for CloudKit upload
    /// - Parameters:
    ///   - image: The image to optimize
    ///   - maxSizeBytes: Maximum size in bytes (default: 10MB for CloudKit)
    /// - Returns: Optimized image data
    /// - Throws: CollectionImageError if optimization fails
    private func optimizeImageForUpload(_ image: UIImage, maxSizeBytes: Int = 10_000_000) throws -> Data {
        // Collection covers can be slightly larger than profile images - target 2MB max
        let targetSize = 2_000_000

        // Resize to max 1200x1200 for collection covers (larger than profile images)
        let maxDimension: CGFloat = 1200
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
            if data.count <= targetSize {
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

        throw CollectionImageError.compressionFailed
    }
}

enum CollectionImageError: Error {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
}
