//
//  RecipeEditorViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftUI
import PhotosUI
import os
import Combine

// MARK: - Input Models

struct IngredientInput: Identifiable {
    let id = UUID()
    var name: String = ""
    var quantityText: String = ""  // Supports fractions like "1/2" or decimals like "1.5"
    var unit: UnitKind = .cup
    
    // Parse quantity text to handle fractions and decimals
    var parsedQuantity: Double? {
        guard !quantityText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        
        // Handle fractions like "1/2", "1/4", "2/3"
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            if parts.count == 2,
               let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
               let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
               denominator != 0 {
                return numerator / denominator
            }
        }
        
        // Handle mixed numbers like "1 1/2" (1 and a half)
        if trimmed.contains(" ") {
            let parts = trimmed.split(separator: " ")
            if parts.count == 2,
               let whole = Double(parts[0].trimmingCharacters(in: .whitespaces)) {
                let fractionPart = String(parts[1].trimmingCharacters(in: .whitespaces))
                if fractionPart.contains("/") {
                    let fracParts = fractionPart.split(separator: "/")
                    if fracParts.count == 2,
                       let numerator = Double(fracParts[0].trimmingCharacters(in: .whitespaces)),
                       let denominator = Double(fracParts[1].trimmingCharacters(in: .whitespaces)),
                       denominator != 0 {
                        return whole + (numerator / denominator)
                    }
                }
            }
        }
        
        // Handle regular decimals
        return Double(trimmed)
    }
}

struct StepInput: Identifiable {
    let id = UUID()
    var text: String = ""
    var timers: [TimerInput] = []
}

struct TimerInput: Identifiable {
    let id = UUID()
    var seconds: Int = 60
    var label: String = "Timer"
}

struct NutritionInput {
    var calories: Double? = nil
    var protein: Double? = nil
    var fat: Double? = nil
    var carbohydrates: Double? = nil
}

// MARK: - ViewModel

@MainActor
class RecipeEditorViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var yields: String = "4 servings"
    @Published var totalMinutes: Int? = nil
    @Published var tagsInput: String = ""
    @Published var notes: String = ""
    @Published var ingredients: [IngredientInput] = [IngredientInput()]
    @Published var steps: [StepInput] = [StepInput()]
    @Published var nutrition: NutritionInput = NutritionInput()
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var selectedImage: UIImage?
    @Published var imageFilename: String?
    @Published var visibility: RecipeVisibility = .privateRecipe
    
    let dependencies: DependencyContainer
    let existingRecipe: Recipe?
    
    var isEditing: Bool { existingRecipe != nil }
    
    var tags: [String] {
        tagsInput
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    var canSave: Bool {
        !title.isEmpty &&
        ingredients.contains(where: { !$0.name.isEmpty }) &&
        steps.contains(where: { !$0.text.isEmpty })
    }
    
    init(dependencies: DependencyContainer, existingRecipe: Recipe? = nil) {
        self.dependencies = dependencies
        self.existingRecipe = existingRecipe
        
        if let recipe = existingRecipe {
            loadFromRecipe(recipe)
        }
    }
    
    private func loadFromRecipe(_ recipe: Recipe) {
        title = recipe.title
        yields = recipe.yields
        totalMinutes = recipe.totalMinutes
        tagsInput = recipe.tags.map { $0.name }.joined(separator: ", ")
        notes = recipe.notes ?? ""
        visibility = recipe.visibility
        
        // Load existing image if available
        if let imageURL = recipe.imageURL {
            imageFilename = imageURL.lastPathComponent
            Task {
                let result = await RecipeImageService.shared.loadImage(from: imageURL)
                if case .success(let image) = result {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            }
        }
        
        ingredients = recipe.ingredients.map { ingredient in
            var input = IngredientInput()
            input.name = ingredient.name
            
            if let quantity = ingredient.quantity {
                input.quantityText = String(format: "%.2f", quantity.value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                input.unit = quantity.unit
            }
            
            return input
        }
        
        steps = recipe.steps.map { step in
            var input = StepInput()
            input.text = step.text
            input.timers = step.timers.map { timer in
                TimerInput(seconds: timer.seconds, label: timer.label)
            }
            return input
        }
        
        if let recipeNutrition = recipe.nutrition {
            nutrition.calories = recipeNutrition.calories
            nutrition.protein = recipeNutrition.protein
            nutrition.fat = recipeNutrition.fat
            nutrition.carbohydrates = recipeNutrition.carbohydrates
        }
    }
    
    func addIngredient() {
        ingredients.append(IngredientInput())
    }
    
    func deleteIngredient(at index: Int) {
        ingredients.remove(at: index)
    }
    
    func addStep() {
        steps.append(StepInput())
    }
    
    func deleteStep(at index: Int) {
        steps.remove(at: index)
    }
    
    func addTimer(to stepIndex: Int) {
        guard steps.indices.contains(stepIndex) else { return }
        // Only add a timer if there isn't one already (limit to one timer per step)
        if steps[stepIndex].timers.isEmpty {
            steps[stepIndex].timers.append(TimerInput())
        }
    }
    
    func save() async -> Bool {
        guard canSave else {
            errorMessage = "Please fill in all required fields"
            return false
        }

        // Note: isSaving is set in the button action to prevent race condition
        // It will be reset there on failure, and on success the view will dismiss

        do {
            var recipe = try buildRecipe()

            // Handle image if selected
            if let image = selectedImage {
                let filename = try await ImageManager.shared.saveImage(image, recipeId: recipe.id)
                let imageURL = await ImageManager.shared.imageURL(for: filename)
                recipe = recipe.withImageURL(imageURL)
            }

            // Save to local database (CloudKit sync happens automatically in repository)
            if isEditing {
                try await dependencies.recipeRepository.update(recipe)
            } else {
                try await dependencies.recipeRepository.create(recipe)
            }

            AppLogger.general.info("Recipe saved: \(recipe.title)")

            return true

        } catch {
            errorMessage = "Failed to save recipe: \(error.localizedDescription)"
            AppLogger.general.error("Failed to save recipe: \(error.localizedDescription)")
            return false
        }
    }
    
    private func buildRecipe() throws -> Recipe {
        // Build ingredients
        let recipeIngredients = ingredients
            .filter { !$0.name.isEmpty }
            .map { input -> Ingredient in
                let quantity = input.parsedQuantity.map { Quantity(value: $0, unit: input.unit) }
                return Ingredient(name: input.name, quantity: quantity, note: nil)
            }
        
        guard !recipeIngredients.isEmpty else {
            throw RecipeEditorError.noIngredients
        }
        
        // Build steps
        let recipeSteps = steps
            .filter { !$0.text.isEmpty }
            .enumerated()
            .map { index, input -> CookStep in
                let timers = input.timers.map { TimerSpec(seconds: $0.seconds, label: $0.label) }
                return CookStep(index: index, text: input.text, timers: timers)
            }
        
        guard !recipeSteps.isEmpty else {
            throw RecipeEditorError.noSteps
        }
        
        // Build tags
        let recipeTags = tags.map { Tag(name: $0) }
        
        // Build nutrition
        let recipeNutrition: Nutrition?
        if nutrition.calories != nil || nutrition.protein != nil || nutrition.fat != nil || nutrition.carbohydrates != nil {
            recipeNutrition = Nutrition(
                calories: nutrition.calories,
                protein: nutrition.protein,
                fat: nutrition.fat,
                carbohydrates: nutrition.carbohydrates
            )
        } else {
            recipeNutrition = nil
        }
        
        // Create or update recipe
        if let existing = existingRecipe {
            return Recipe(
                id: existing.id,
                title: title,
                ingredients: recipeIngredients,
                steps: recipeSteps,
                yields: yields,
                totalMinutes: totalMinutes,
                tags: recipeTags,
                nutrition: recipeNutrition,
                sourceURL: existing.sourceURL,
                sourceTitle: existing.sourceTitle,
                notes: notes.isEmpty ? nil : notes,
                imageURL: existing.imageURL,
                isFavorite: existing.isFavorite,
                visibility: visibility,
                ownerId: existing.ownerId ?? CurrentUserSession.shared.userId,
                cloudRecordName: existing.cloudRecordName,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        } else {
            return Recipe(
                title: title,
                ingredients: recipeIngredients,
                steps: recipeSteps,
                yields: yields,
                totalMinutes: totalMinutes,
                tags: recipeTags,
                nutrition: recipeNutrition,
                notes: notes.isEmpty ? nil : notes,
                visibility: visibility,
                ownerId: CurrentUserSession.shared.userId
            )
        }
    }
}

enum RecipeEditorError: LocalizedError {
    case noIngredients
    case noSteps
    
    var errorDescription: String? {
        switch self {
        case .noIngredients:
            return "Recipe must have at least one ingredient"
        case .noSteps:
            return "Recipe must have at least one step"
        }
    }
}


