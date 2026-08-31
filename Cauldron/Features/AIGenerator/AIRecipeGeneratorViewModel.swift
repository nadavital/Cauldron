//
//  AIRecipeGeneratorViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/14/25.
//

import Foundation
import SwiftUI
import os
import FoundationModels

@MainActor
@Observable
final class AIRecipeGeneratorViewModel {
    var prompt: String = ""
    var selectedCuisines: Set<RecipeCategory> = []
    var selectedDiets: Set<RecipeCategory> = []
    var selectedTimes: Set<RecipeCategory> = []
    var selectedTypes: Set<RecipeCategory> = []
    var additionalNotes: String = ""
    var useCategoryMode: Bool = true
    var isGenerating: Bool = false
    var isSaving: Bool = false
    var partialRecipe: GeneratedRecipe.PartiallyGenerated?
    var generatedRecipe: Recipe?
    var errorMessage: String?
    var generationProgress: GenerationProgress = .idle

    let dependencies: DependencyContainer
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

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

    #if DEBUG
    /// Deterministic, complete output used only by the App Store screenshot route.
    /// Keeping it in the real view model lets the capture exercise the same
    /// completed-state UI and Save action as an actual generation.
    func seedScreenshotPreview() {
        prompt = "a bright weeknight dinner with pantry ingredients"
        generatedRecipe = GeneratedRecipe(
            title: "Crispy Lemon Chickpeas",
            yields: "4 servings",
            totalMinutes: 25,
            ingredients: [
                GeneratedIngredient(name: "chickpeas", quantityValue: 2, quantityUnit: "can", note: "drained"),
                GeneratedIngredient(name: "lemon", quantityValue: 1, quantityUnit: "piece", note: "zested and juiced"),
                GeneratedIngredient(name: "garlic", quantityValue: 2, quantityUnit: "clove", note: "thinly sliced"),
                GeneratedIngredient(name: "Greek yogurt", quantityValue: 0.5, quantityUnit: "cup", note: nil),
                GeneratedIngredient(name: "fresh herbs", quantityValue: 1, quantityUnit: "cup", note: "roughly chopped")
            ],
            steps: [
                GeneratedStep(text: "Crisp the chickpeas in olive oil until deeply golden.", timerSeconds: 600),
                GeneratedStep(text: "Add garlic, lemon zest, and a pinch of chili flakes.", timerSeconds: nil),
                GeneratedStep(text: "Spoon over yogurt and finish with herbs and lemon juice.", timerSeconds: nil)
            ],
            notes: "Flexible, fast, and built from pantry staples."
        ).toRecipe(withTags: [Tag(name: "Quick"), Tag(name: "Vegetarian")])
        generationProgress = .complete
    }
    #endif

    var canGenerate: Bool {
        if isGenerating { return false }

        // Can generate if either prompt is filled OR categories are selected
        return !prompt.trimmed.isEmpty || hasSelectedCategories
    }

    func primaryActionState(isAvailable: Bool) -> AIRecipePrimaryActionState {
        if isSaving { return .saving }
        if isGenerating { return .generating }
        if generatedRecipe != nil { return .save }
        return .generate(isEnabled: isAvailable && canGenerate)
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
        let generationID = UUID()
        activeGenerationID = generationID

        generationTask = Task { [generationID] in
            defer {
                if self.activeGenerationID == generationID {
                    self.isGenerating = false
                    self.generationTask = nil
                }
            }

            do {
                let stream = dependencies.foundationModelsService.generateRecipe(from: generationPrompt)

                for try await partial in stream {
                    guard !Task.isCancelled, self.activeGenerationID == generationID else { return }

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
                    AppLogger.general.info("Recipe generation completed: \(recipe.title)")
                } else {
                    self.errorMessage = "Recipe generation finished without enough recipe details. Try adding a little more guidance."
                    self.generationProgress = .failed
                    AppLogger.general.error("Recipe generation completed without a valid final recipe")
                }

            } catch is CancellationError {
                guard self.activeGenerationID == generationID else { return }
                self.generationProgress = .idle
            } catch {
                guard self.activeGenerationID == generationID else { return }
                self.errorMessage = error.localizedDescription
                self.generationProgress = .failed
                AppLogger.general.error("Recipe generation failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
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

            guard let userId = CurrentUserSession.shared.userId else {
                errorMessage = "You must be signed in to save recipes."
                return false
            }

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
                ownerId: userId
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
        guard !fullIngredients.isEmpty, !fullSteps.isEmpty else {
            return nil
        }
        
        // Combine AI-generated tags with selected categories
        // Note: AI no longer generates tags to save context, so we rely on selected categories
        
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
