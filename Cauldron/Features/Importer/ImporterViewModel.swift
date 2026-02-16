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
            return normalizedURLInput() != nil
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

    func normalizedURLInput() -> URL? {
        let trimmedInput = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return nil
        }

        if let detected = firstURL(in: trimmedInput), isSupportedWebURL(detected) {
            return detected
        }

        let candidate = candidateURLString(from: trimmedInput)
        guard let url = URL(string: candidate), isSupportedWebURL(url), url.host != nil else {
            return nil
        }

        return url
    }

    func preloadImportedRecipe(_ recipe: Recipe, sourceInfo: String) {
        importedRecipe = recipe
        self.sourceInfo = sourceInfo
        isSuccess = true
        isLoading = false
        errorMessage = nil
        ocrErrorMessage = nil
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
        guard let normalizedURL = normalizedURLInput() else {
            throw ParsingError.invalidURL
        }

        let normalizedURLString = normalizedURL.absoluteString
        urlString = normalizedURLString

        // Detect platform and route to appropriate parser
        let platform = PlatformDetector.detect(from: normalizedURLString)

        var recipe: Recipe

        switch platform {
        case .youtube:
            recipe = try await dependencies.socialParser.parse(
                from: normalizedURLString,
                platform: .youtube
            )

        case .instagram:
            recipe = try await dependencies.socialParser.parse(
                from: normalizedURLString,
                platform: .instagram
            )

        case .tiktok:
            recipe = try await dependencies.socialParser.parse(
                from: normalizedURLString,
                platform: .tiktok
            )

        case .recipeWebsite, .unknown:
            // Use HTML parser for structured recipe sites
            // The HTML parser will use schema.org JSON-LD when available, then fall back to heuristics
            recipe = try await dependencies.htmlParser.parse(from: normalizedURLString)
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

    private func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return match.url
    }

    private func candidateURLString(from input: String) -> String {
        if input.contains("://") {
            return input
        }

        let bareHostPattern = #"^[A-Za-z0-9.-]+\.[A-Za-z]{2,}([/:?#].*)?$"#
        if input.range(of: bareHostPattern, options: .regularExpression) != nil {
            return "https://\(input)"
        }

        return input
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
