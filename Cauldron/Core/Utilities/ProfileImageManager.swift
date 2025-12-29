//
//  ProfileImageManager.swift
//  Cauldron
//
//  Manages profile image storage and retrieval
//

import Foundation
import UIKit
import SwiftUI
import CloudKit
import os

/// Manages profile image storage and retrieval
actor ProfileImageManager {
    private let imageDirectoryURL: URL
    private let cloudKitService: CloudKitService

    init(cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService

        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Unable to access documents directory")
        }
        self.imageDirectoryURL = documentsURL.appendingPathComponent("ProfileImages", isDirectory: true)

        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try? fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }
    }

    /// Save profile image and return local URL
    func saveImage(_ image: UIImage, userId: UUID) throws -> URL {
        // Ensure directory exists (in case it was deleted)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }

        // Optimize and compress image
        let optimizedData = try optimizeImageForUpload(image)

        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        try optimizedData.write(to: fileURL)
        AppLogger.general.info("✅ Saved profile image for user \(userId) at \(fileURL.path)")
        return fileURL
    }

    /// Load image from user ID
    func loadImage(userId: UUID) -> UIImage? {
        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }

    /// Delete profile image file
    func deleteImage(userId: UUID) {
        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
        AppLogger.general.info("🗑️ Deleted profile image for user \(userId)")
    }

    /// Get full file URL for a user ID
    func imageURL(for userId: UUID) -> URL {
        let filename = "\(userId.uuidString).jpg"
        return imageDirectoryURL.appendingPathComponent(filename)
    }

    /// Check if profile image exists locally
    func imageExists(userId: UUID) -> Bool {
        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Get modification date of local image file
    func getImageModificationDate(userId: UUID) -> Date? {
        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return modificationDate
    }

    // MARK: - Cloud Sync Methods

    /// Upload profile image to CloudKit
    /// - Parameter userId: The user ID this image belongs to
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageToCloud(userId: UUID) async throws -> String {
        // Load image data from local storage
        let filename = "\(userId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw ProfileImageError.saveFailed
        }

        AppLogger.general.info("☁️ Uploading profile image to CloudKit for user \(userId)")

        // Upload to CloudKit (always to public database for profiles)
        return try await cloudKitService.uploadUserProfileImage(userId: userId, imageData: imageData)
    }

    /// Download profile image from CloudKit and save locally
    /// - Parameter userId: The user ID to download image for
    /// - Returns: The local URL, or nil if no image exists
    func downloadImageFromCloud(userId: UUID) async throws -> URL? {
        AppLogger.general.info("☁️ Downloading profile image from CloudKit for user \(userId)")

        // Download from CloudKit (always from public database for profiles)
        guard let imageData = try await cloudKitService.downloadUserProfileImage(userId: userId) else {
            AppLogger.general.info("No profile image found in CloudKit for user \(userId)")
            return nil
        }

        // Convert to UIImage
        guard let image = UIImage(data: imageData) else {
            throw ProfileImageError.invalidImageData
        }

        // Save locally
        let fileURL = try await saveImage(image, userId: userId)
        AppLogger.general.info("✅ Downloaded and saved profile image for user \(userId)")
        return fileURL
    }

    /// Delete profile image from CloudKit
    /// - Parameter userId: The user ID to delete image for
    func deleteImageFromCloud(userId: UUID) async throws {
        AppLogger.general.info("☁️ Deleting profile image from CloudKit for user \(userId)")
        try await cloudKitService.deleteUserProfileImage(userId: userId)
    }

    // MARK: - Helper Methods

    /// Optimize image for CloudKit upload
    /// - Parameters:
    ///   - image: The image to optimize
    ///   - maxSizeBytes: Maximum size in bytes (default: 10MB for CloudKit)
    /// - Returns: Optimized image data
    /// - Throws: ProfileImageError if optimization fails
    private func optimizeImageForUpload(_ image: UIImage, maxSizeBytes: Int = 10_000_000) throws -> Data {
        // Profile images should be smaller - target 1MB max
        let targetSize = 1_000_000

        // Resize to max 800x800 for profile images
        let maxDimension: CGFloat = 800
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

        throw ProfileImageError.compressionFailed
    }
}

enum ProfileImageError: Error {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
}
