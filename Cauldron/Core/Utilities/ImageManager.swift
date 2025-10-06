//
//  ImageManager.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import UIKit
import SwiftUI

/// Manages recipe image storage and retrieval
actor ImageManager {
    static let shared = ImageManager()
    
    private let imageDirectoryURL: URL
    
    private init() {
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
}

enum ImageError: Error {
    case compressionFailed
    case saveFailed
    case downloadFailed
    case invalidImageData
}
