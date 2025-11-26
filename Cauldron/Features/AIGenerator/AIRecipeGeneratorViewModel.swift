//
//  AIRecipeGeneratorViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/14/25.
//

import Foundation
import SwiftUI
import Combine
import os
import FoundationModels

@MainActor
class AIRecipeGeneratorViewModel: ObservableObject {
    @Published var prompt: String = ""
    @Published var selectedCuisines: Set<RecipeCategory> = []
    @Published var selectedDiets: Set<RecipeCategory> = []
    @Published var selectedTimes: Set<RecipeCategory> = []
    @Published var selectedTypes: Set<RecipeCategory> = []
    @Published var additionalNotes: String = ""
    @Published var useCategoryMode: Bool = true
    @Published var isGenerating: Bool = false
    @Published var isSaving: Bool = false
    @Published var partialRecipe: GeneratedRecipe.PartiallyGenerated?
    @Published var generatedRecipe: Recipe?
    @Published var errorMessage: String?
    @Published var generationProgress: GenerationProgress = .idle

    let dependencies: DependencyContainer
    private var generationTask: Task<Void, Never>?

    enum GenerationProgress {
        case idle
        case generatingTitle
        case generatingIngredients
        case generatingSteps
        case complete
        case failed

        var description: String {
            switch self {
            case .idle:
                return ""
            case .generatingTitle:
                return "Generating recipe title..."
            case .generatingIngredients:
                return "Adding ingredients..."
            case .generatingSteps:
                return "Writing instructions..."
            case .complete:
                return "Recipe complete!"
            case .failed:
                return "Generation failed"
            }
        }

        var systemImage: String {
            switch self {
            case .idle:
                return "wand.and.stars"
            case .generatingTitle:
                return "text.cursor"
            case .generatingIngredients:
                return "list.bullet"
            case .generatingSteps:
                return "list.number"
            case .complete:
                return "checkmark.circle.fill"
            case .failed:
                return "xmark.circle.fill"
            }
        }
    }

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var canGenerate: Bool {
        if isGenerating { return false }

        // Can generate if either prompt is filled OR categories are selected
        return !prompt.trimmed.isEmpty || hasSelectedCategories
    }

    var hasSelectedCategories: Bool {
        !selectedCuisines.isEmpty || !selectedDiets.isEmpty ||
        !selectedTimes.isEmpty || !selectedTypes.isEmpty
    }

    var selectedCategoriesSummary: String {
        let allCategories = Array(selectedCuisines) + Array(selectedDiets) +
                           Array(selectedTimes) + Array(selectedTypes)
        return allCategories.map { $0.displayName }.joined(separator: ", ")
    }

    var allSelectedCategories: [RecipeCategory] {
        Array(selectedCuisines) + Array(selectedDiets) +
        Array(selectedTimes) + Array(selectedTypes)
    }

    func removeCategory(_ category: RecipeCategory) {
        switch category.section {
        case .cuisine:
            selectedCuisines.remove(category)
        case .dietary:
            selectedDiets.remove(category)
        case .other:
            selectedTimes.remove(category)
        case .mealType:
            selectedTypes.remove(category)
        }
    }

    private var generationPrompt: String {
        var instructions: [String] = []

        // Add selected categories with explicit instruction
        if !selectedCuisines.isEmpty {
            let cuisines = selectedCuisines.map { $0.displayName }.joined(separator: " and ")
            instructions.append("Create an AUTHENTIC \(cuisines) recipe.")
        }
        
        if !selectedDiets.isEmpty {
            let diets = selectedDiets.map { $0.displayName }.joined(separator: " and ")
            instructions.append("It must be \(diets).")
        }
        
        if !selectedTimes.isEmpty {
             let times = selectedTimes.map { $0.displayName }.joined(separator: " and ")
             instructions.append("It should be \(times).")
        }
        
        if !selectedTypes.isEmpty {
            let types = selectedTypes.map { $0.displayName }.joined(separator: " and ")
            instructions.append("It is a \(types) dish.")
        }

        // Add prompt/notes
        if !prompt.trimmed.isEmpty {
            instructions.append("Additional requirements: \(prompt.trimmed)")
        }
        
        // Fallback if nothing selected
        if instructions.isEmpty {
            return "Create a delicious recipe."
        }

        return instructions.joined(separator: " ")
    }

    func checkAvailability() async -> Bool {
        return await dependencies.foundationModelsService.isAvailable
    }

    func generateRecipe() {
        guard canGenerate else { return }

        isGenerating = true
        errorMessage = nil
        partialRecipe = nil
        generatedRecipe = nil
        generationProgress = .generatingTitle

        // Cancel any existing generation
        generationTask?.cancel()

        generationTask = Task {
            do {
                let stream = dependencies.foundationModelsService.generateRecipe(from: generationPrompt)

                for try await partial in stream {
                    guard !Task.isCancelled else { break }

                    // Store the partial recipe for UI updates
                    self.partialRecipe = partial

                    // Update progress based on what's been generated
                    self.updateProgress(for: partial)
                }

                // When stream completes, convert final partial to full recipe
                if let final = partialRecipe, let fullRecipe = convertPartialToFullRecipe(final) {
                    // Build tags from selected categories
                    let selectedCategoryTags = allSelectedCategories.map { Tag(name: $0.tagValue) }

                    let recipe = fullRecipe.toRecipe(withTags: selectedCategoryTags)
                    self.generatedRecipe = recipe
                    self.generationProgress = .complete
                    self.isGenerating = false
                    AppLogger.general.info("Recipe generation completed: \(recipe.title)")
                }

            } catch {
                self.errorMessage = error.localizedDescription
                self.generationProgress = .failed
                self.isGenerating = false
                AppLogger.general.error("Recipe generation failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        isGenerating = false
        generationProgress = .idle
    }

    func regenerate() {
        generateRecipe()
    }

    func saveRecipe() async -> Bool {
        guard let recipe = generatedRecipe else {
            errorMessage = "No recipe to save"
            return false
        }

        // Note: isSaving is set in the button action to prevent race condition
        // It will be reset there on failure, and on success the view will dismiss

        do {
            // Add source note
            let sourceNote = "Generated by Apple Intelligence"
            let notesWithSource = if let existingNotes = recipe.notes {
                "\(existingNotes)\n\n\(sourceNote)"
            } else {
                sourceNote
            }

            // Get current user ID for CloudKit sync
            let userId = CurrentUserSession.shared.userId

            let recipeToSave = Recipe(
                id: recipe.id,
                title: recipe.title,
                ingredients: recipe.ingredients,
                steps: recipe.steps,
                yields: recipe.yields,
                totalMinutes: recipe.totalMinutes,
                tags: recipe.tags,
                nutrition: recipe.nutrition,
                notes: notesWithSource,
                ownerId: userId  // Set ownerId so recipe syncs to CloudKit
            )

            // Save to repository (CloudKit sync happens automatically)
            try await dependencies.recipeRepository.create(recipeToSave)
            AppLogger.general.info("AI-generated recipe saved: \(recipe.title)")

            // Notify other views that a recipe was added
            NotificationCenter.default.post(name: .recipeAdded, object: nil)

            return true
        } catch {
            errorMessage = "Failed to save recipe: \(error.localizedDescription)"
            AppLogger.general.error("Failed to save AI-generated recipe: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func updateProgress(for partial: GeneratedRecipe.PartiallyGenerated) {
        // Check what fields have been populated
        if partial.title != nil && (partial.ingredients?.isEmpty ?? true) && (partial.steps?.isEmpty ?? true) {
            generationProgress = .generatingIngredients
        } else if !(partial.ingredients?.isEmpty ?? true) && (partial.steps?.isEmpty ?? true) {
            generationProgress = .generatingSteps
        } else if !(partial.steps?.isEmpty ?? true) {
            generationProgress = .generatingSteps
        }
    }

    /// Convert PartiallyGenerated to full GeneratedRecipe (filling in defaults for missing fields)
    private func convertPartialToFullRecipe(_ partial: GeneratedRecipe.PartiallyGenerated) -> GeneratedRecipe? {
        // Ensure we have at least the minimum required fields
        guard let title = partial.title,
              let ingredients = partial.ingredients, !ingredients.isEmpty,
              let steps = partial.steps, !steps.isEmpty else {
            return nil
        }

        // Convert partial ingredients to full ingredients
        let fullIngredients = ingredients.compactMap { partialIng -> GeneratedIngredient? in
            guard let name = partialIng.name else { return nil }
            return GeneratedIngredient(
                name: name,
                quantityValue: partialIng.quantityValue,
                quantityUnit: partialIng.quantityUnit,
                note: partialIng.note
            )
        }

        // Convert partial steps to full steps
        let fullSteps = steps.compactMap { partialStep -> GeneratedStep? in
            guard let text = partialStep.text else { return nil }
            return GeneratedStep(text: text, timerSeconds: partialStep.timerSeconds)
        }
        
        // Combine AI-generated tags with selected categories
        // Note: AI no longer generates tags to save context, so we rely on selected categories
        
        // Add selected categories as tags
        let selectedCategoryTags = (Array(selectedCuisines) + Array(selectedDiets) +
                                  Array(selectedTimes) + Array(selectedTypes))
            .map { $0.tagValue }
        
        // Deduplicate
        let uniqueTags = Array(Set(selectedCategoryTags))

        return GeneratedRecipe(
            title: title,
            yields: partial.yields ?? "4 servings",
            totalMinutes: partial.totalMinutes,
            ingredients: fullIngredients,
            steps: fullSteps,
            notes: partial.notes
        )
    }
}
