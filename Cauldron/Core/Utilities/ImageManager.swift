//
//  ImageManager.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import UIKit
import SwiftUI
import CloudKit

/// Manages recipe image storage and retrieval
actor ImageManager {
    private let imageDirectoryURL: URL
    private let cloudKitService: CloudKitService

    init(cloudKitService: CloudKitService) {
        self.cloudKitService = cloudKitService

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.imageDirectoryURL = documentsURL.appendingPathComponent("RecipeImages", isDirectory: true)

        // Ensure directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try? fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }
    }
    
    /// Save image and return filename
    func saveImage(_ image: UIImage, recipeId: UUID) throws -> String {
        // Ensure directory exists (in case it was deleted)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: imageDirectoryURL.path) {
            try fileManager.createDirectory(at: imageDirectoryURL, withIntermediateDirectories: true)
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw ImageError.compressionFailed
        }
        
        let filename = "\(recipeId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        
        try imageData.write(to: fileURL)
        return filename
    }
    
    /// Load image from filename
    func loadImage(filename: String) -> UIImage? {
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }
    
    /// Delete image file
    func deleteImage(filename: String) {
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Get full file URL for a filename
    func imageURL(for filename: String) -> URL {
        imageDirectoryURL.appendingPathComponent(filename)
    }
    
    /// Download image from URL and save it
    func downloadAndSaveImage(from url: URL, recipeId: UUID) async throws -> String {
        // Download the image
        let (data, response) = try await URLSession.shared.data(from: url)

        // Verify it's an image
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let mimeType = httpResponse.mimeType,
              mimeType.hasPrefix("image/") else {
            throw ImageError.downloadFailed
        }

        // Convert to UIImage
        guard let image = UIImage(data: data) else {
            throw ImageError.invalidImageData
        }

        // Save it
        return try await saveImage(image, recipeId: recipeId)
    }

    // MARK: - Cloud Sync Methods

    /// Upload image to CloudKit
    /// - Parameters:
    ///   - recipeId: The recipe ID this image belongs to
    ///   - database: The database to upload to (private or public)
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadImageToCloud(recipeId: UUID, database: CKDatabase) async throws -> String {
        // Load image data from local storage
        let filename = "\(recipeId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let imageData = try? Data(contentsOf: fileURL) else {
            throw ImageError.saveFailed
        }

        // Upload to CloudKit
        return try await cloudKitService.uploadImageAsset(recipeId: recipeId, imageData: imageData, to: database)
    }

    /// Download image from CloudKit and save locally
    /// - Parameters:
    ///   - recipeId: The recipe ID to download image for
    ///   - database: The database to download from (private or public)
    /// - Returns: The local filename, or nil if no image exists
    func downloadImageFromCloud(recipeId: UUID, database: CKDatabase) async throws -> String? {
        // Download from CloudKit
        guard let imageData = try await cloudKitService.downloadImageAsset(recipeId: recipeId, from: database) else {
            return nil
        }

        // Convert to UIImage
        guard let image = UIImage(data: imageData) else {
            throw ImageError.invalidImageData
        }

        // Save locally
        let filename = try await saveImage(image, recipeId: recipeId)
        return filename
    }

    /// Copy image from one recipe to another
    /// - Parameters:
    ///   - sourceId: The recipe ID to copy from
    ///   - targetId: The recipe ID to copy to
    /// - Returns: The filename of the copied image, or nil if source doesn't exist
    func copyImageForRecipe(from sourceId: UUID, to targetId: UUID) throws -> String? {
        let sourceFilename = "\(sourceId.uuidString).jpg"
        let targetFilename = "\(targetId.uuidString).jpg"

        let sourceURL = imageDirectoryURL.appendingPathComponent(sourceFilename)
        let targetURL = imageDirectoryURL.appendingPathComponent(targetFilename)

        // Check if source exists
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        // Copy file
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        return targetFilename
    }

    /// Get modification date of local image file
    /// - Parameter recipeId: The recipe ID
    /// - Returns: The modification date, or nil if file doesn't exist
    func getImageModificationDate(recipeId: UUID) -> Date? {
        let filename = "\(recipeId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }

        return modificationDate
    }

    /// Check if image exists locally
    /// - Parameter recipeId: The recipe ID
    /// - Returns: True if image file exists
    func imageExists(recipeId: UUID) -> Bool {
        let filename = "\(recipeId.uuidString).jpg"
        let fileURL = imageDirectoryURL.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Optimize image for CloudKit upload
    /// - Parameters:
    ///   - image: The image to optimize
    ///   - maxSizeBytes: Maximum size in bytes (default: 10MB for CloudKit)
    /// - Returns: Optimized image data
    /// - Throws: ImageError if optimization fails or image is too large
    func optimizeImageForUpload(_ image: UIImage, maxSizeBytes: Int = 10_000_000) throws -> Data {
        let compressionThreshold = 5_000_000 // 5MB - compress if larger

        // Try 80% quality compression first
        if let data = image.jpegData(compressionQuality: 0.8) {
            if data.count <= compressionThreshold {
                return data
            }
            if data.count <= maxSizeBytes {
                return data
            }
        }

        // Try 60% compression
        if let compressedData = image.jpegData(compressionQuality: 0.6),
           compressedData.count <= maxSizeBytes {
            return compressedData
        }

        // If still too large, resize and compress
        let maxDimension: CGFloat = 2000
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height, 1.0)

        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            if let resizedImage = resizedImage,
               let compressedData = resizedImage.jpegData(compressionQuality: 0.8),
               compressedData.count <= maxSizeBytes {
                return compressedData
            }
        }

        throw ImageError.compressionFailed
    }

    /// Delete image by recipe ID
    /// - Parameter recipeId: The recipe ID
    func deleteImage(recipeId: UUID) {
        let filename = "\(recipeId.uuidString).jpg"
        deleteImage(filename: filename)
    }
}

enum ImageError: Error {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
}
