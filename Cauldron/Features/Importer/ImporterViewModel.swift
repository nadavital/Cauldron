//
//  ImporterViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import Combine
import SwiftUI
import UIKit
import os

@MainActor
@Observable final class ImporterViewModel {
    var importType: ImportType = .url
    var urlString = ""
    var textInput = ""
    var isLoading = false
    var isSuccess = false
    var errorMessage: String?
    var importedRecipe: Recipe?
    var sourceInfo: String?
    var selectedOCRImage: UIImage?
    var isProcessingOCR = false
    var ocrErrorMessage: String?

    let dependencies: DependencyContainer
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    var canImport: Bool {
        switch importType {
        case .url:
            return !urlString.trimmed.isEmpty
        case .text:
            return !textInput.trimmed.isEmpty
        case .image:
            return selectedOCRImage != nil
        }
    }

    func preloadURL(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return
        }

        importType = .url
        urlString = url.absoluteString
    }
    
    func importRecipe() async {
        isLoading = true
        errorMessage = nil
        ocrErrorMessage = nil
        isSuccess = false
        importedRecipe = nil
        sourceInfo = nil
        defer { isLoading = false }
        
        do {
            var recipe: Recipe
            var source: String
            
            switch importType {
            case .url:
                recipe = try await importFromURL()
                source = "Imported from \(urlString)"
            case .text:
                recipe = try await importFromText()
                source = "Imported from text"
            case .image:
                recipe = try await importFromImage()
                source = "Imported from image"
            }
            
            // Validate recipe
            guard recipe.isValid else {
                errorMessage = "Recipe is incomplete or invalid"
                return
            }
            
            // Set imported recipe and source for preview
            importedRecipe = recipe
            sourceInfo = source
            isSuccess = true
            
            AppLogger.parsing.info("Successfully imported recipe: \(recipe.title)")
            
        } catch {
            if ocrErrorMessage == nil {
                errorMessage = error.localizedDescription
            }
            AppLogger.parsing.error("Failed to import recipe: \(error.localizedDescription)")
        }
    }
    
    private func importFromURL() async throws -> Recipe {
        // Detect platform and route to appropriate parser
        let platform = PlatformDetector.detect(from: urlString)

        var recipe: Recipe

        switch platform {
        case .youtube:
            // Use YouTube-specific parser for video descriptions
            recipe = try await dependencies.youtubeParser.parse(from: urlString)

        case .instagram:
            // Use Instagram-specific parser for post captions
            recipe = try await dependencies.instagramParser.parse(from: urlString)

        case .tiktok:
            // Use TikTok-specific parser for video descriptions
            recipe = try await dependencies.tiktokParser.parse(from: urlString)

        case .recipeWebsite, .unknown:
            // Use HTML parser for structured recipe sites
            // The HTML parser will use schema.org JSON-LD when available, then fall back to heuristics
            recipe = try await dependencies.htmlParser.parse(from: urlString)
        }

        // Download and save image if recipe has an imageURL
        if let imageURL = recipe.imageURL {
            do {
                let imageFilename = try await dependencies.imageManager.downloadAndSaveImage(from: imageURL, recipeId: recipe.id)
                // Store the full file URL to the locally saved image
                let localImageURL = await dependencies.imageManager.imageURL(for: imageFilename)
                recipe = recipe.withImageURL(localImageURL)
                AppLogger.parsing.info("Successfully downloaded recipe image to: \(localImageURL.path)")
            } catch {
                AppLogger.parsing.warning("Failed to download recipe image: \(error.localizedDescription)")
                // Continue without image - non-fatal error
                // Keep the original URL as fallback for remote loading
            }
        }

        return recipe
    }
    
    private func importFromText() async throws -> Recipe {
        // Use text parser directly
        return try await dependencies.textParser.parse(from: textInput)
    }

    private func importFromImage() async throws -> Recipe {
        guard let image = selectedOCRImage else {
            throw ImporterError.noImageSelected
        }

        isProcessingOCR = true
        ocrErrorMessage = nil
        defer { isProcessingOCR = false }

        do {
            let extractedText = try await dependencies.recipeOCRService.extractText(from: image)
            AppLogger.parsing.info("OCR extraction succeeded with \(extractedText.count) chars")
            return try await dependencies.textParser.parse(from: extractedText)
        } catch {
            ocrErrorMessage = error.localizedDescription
            AppLogger.parsing.error("OCR extraction failed: \(error.localizedDescription)")
            throw error
        }
    }
}

private enum ImporterError: LocalizedError {
    case noImageSelected

    var errorDescription: String? {
        switch self {
        case .noImageSelected:
            return "Select a recipe image before importing."
        }
    }
}
