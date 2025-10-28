//
//  ImporterViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import Combine
import SwiftUI
import os

@MainActor
class ImporterViewModel: ObservableObject {
    @Published var importType: ImportType = .url
    @Published var urlString = ""
    @Published var textInput = ""
    @Published var isLoading = false
    @Published var isSuccess = false
    @Published var errorMessage: String?
    @Published var importedRecipe: Recipe?
    @Published var sourceInfo: String?
    
    let dependencies: DependencyContainer
    
    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }
    
    var canImport: Bool {
        switch importType {
        case .url:
            return !urlString.trimmed.isEmpty
        case .text:
            return !textInput.trimmed.isEmpty
        }
    }
    
    func importRecipe() async {
        isLoading = true
        errorMessage = nil
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
            errorMessage = error.localizedDescription
            AppLogger.parsing.error("Failed to import recipe: \(error.localizedDescription)")
        }
    }
    
    private func importFromURL() async throws -> Recipe {
        // Use HTML parser directly (more reliable than AI for structured recipe sites)
        // The HTML parser will use schema.org JSON-LD when available, then fall back to heuristics
        var recipe = try await dependencies.htmlParser.parse(from: urlString)

        // Download and save image if recipe has an imageURL
        if let imageURL = recipe.imageURL {
            do {
                let imageFilename = try await ImageManager.shared.downloadAndSaveImage(from: imageURL, recipeId: recipe.id)
                // Store the full file URL to the locally saved image
                let localImageURL = await ImageManager.shared.imageURL(for: imageFilename)
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
        // Try Foundation Models first
        if let recipe = try await dependencies.foundationModelsService.parseRecipeText(textInput) {
            return recipe
        }
        
        // Fallback to text parser
        return try await dependencies.textParser.parse(from: textInput)
    }
}
