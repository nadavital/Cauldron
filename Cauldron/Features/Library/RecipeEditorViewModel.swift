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

struct IngredientSectionInput: Identifiable {
    let id = UUID()
    var name: String = ""
    var ingredients: [IngredientInput] = []
}

struct StepSectionInput: Identifiable {
    let id = UUID()
    var name: String = ""
    var steps: [StepInput] = []
}

struct IngredientInput: Identifiable {
    let id = UUID()
    var name: String = ""
    var quantityText: String = ""  // Supports fractions like "1/2", decimals "1.5", and ranges "1-2"
    var unit: UnitKind = .cup
    // Section is now handled by the parent container
    
    // Parse quantity text to handle fractions, decimals, and ranges
    var parsedValues: (value: Double, upperValue: Double?)? {
        guard !quantityText.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        
        let trimmed = quantityText.trimmingCharacters(in: .whitespaces)
        
        // Handle Range: "1-2" or "1 - 2"
        if trimmed.contains("-") {
             let components = trimmed.components(separatedBy: "-")
             if components.count == 2,
                let lower = parseSingleValue(components[0]),
                let upper = parseSingleValue(components[1]) {
                 return (lower, upper)
             }
        }
        
        // Handle Single Value
        if let val = parseSingleValue(trimmed) {
            return (val, nil)
        }
        
        return nil
    }
    
    private func parseSingleValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        
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
    // Section is now handled by the parent container
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
    @Published var selectedTags: Set<RecipeCategory> = []
    @Published var notes: String = ""
    
    // Grouped Sections
    @Published var ingredientSections: [IngredientSectionInput] = [IngredientSectionInput(name: "", ingredients: [IngredientInput()])]
    @Published var stepSections: [StepSectionInput] = [StepSectionInput(name: "", steps: [StepInput()])]
    
    @Published var nutrition: NutritionInput = NutritionInput()
    @Published var errorMessage: String?
    @Published var isSaving: Bool = false
    @Published var selectedImage: UIImage?
    @Published var imageFilename: String?
    @Published var visibility: RecipeVisibility = .publicRecipe
    
    let dependencies: DependencyContainer
    let existingRecipe: Recipe?
    let isImporting: Bool  // True when editing during import flow

    var isEditing: Bool { existingRecipe != nil && !isImporting }
    
    func toggleTag(_ category: RecipeCategory) {
        if selectedTags.contains(category) {
            selectedTags.remove(category)
        } else {
            selectedTags.insert(category)
        }
    }
    
    var canSave: Bool {
        !title.isEmpty &&
        ingredientSections.contains { section in
            section.ingredients.contains { !$0.name.isEmpty }
        } &&
        stepSections.contains { section in
            section.steps.contains { !$0.text.isEmpty }
        }
    }
    
    @Published var relatedRecipes: [Recipe] = []
    @Published var availableRecipes: [Recipe] = []
    @Published var isRelatedRecipesPickerPresented: Bool = false
    
    func loadAvailableRecipes() async {
        do {
            let all = try await dependencies.recipeRepository.fetchAll()
            // Filter out self if editing
            await MainActor.run {
                availableRecipes = all.filter { $0.id != existingRecipe?.id }
            }
        } catch {
            AppLogger.general.error("Failed to load available recipes: \(error.localizedDescription)")
        }
    }
    
    func toggleRelatedRecipe(_ recipe: Recipe) {
        if relatedRecipes.contains(where: { $0.id == recipe.id }) {
            relatedRecipes.removeAll(where: { $0.id == recipe.id })
        } else {
            relatedRecipes.append(recipe)
        }
    }
    
    init(dependencies: DependencyContainer, existingRecipe: Recipe? = nil, isImporting: Bool = false) {
        self.dependencies = dependencies
        self.existingRecipe = existingRecipe
        self.isImporting = isImporting

        if let recipe = existingRecipe {
            loadFromRecipe(recipe)
        }
    }
    
    private func loadFromRecipe(_ recipe: Recipe) {
        title = recipe.title
        yields = recipe.yields
        totalMinutes = recipe.totalMinutes
        
        // Load tags by matching them to RecipeCategory
        selectedTags = Set(recipe.tags.compactMap { tag in
            RecipeCategory.match(string: tag.name)
        })
        
        notes = recipe.notes ?? ""
        visibility = recipe.visibility
        
        Task {
            if !recipe.relatedRecipeIds.isEmpty {
                do {
                    let related = try await dependencies.recipeRepository.fetch(ids: recipe.relatedRecipeIds)
                    await MainActor.run {
                        self.relatedRecipes = related
                    }
                } catch {
                    AppLogger.general.error("Failed to load related recipes: \(error.localizedDescription)")
                }
            }
        }
        
        // Load existing image if available
        if let imageURL = recipe.imageURL {
            imageFilename = imageURL.lastPathComponent
            Task {
                let result = await dependencies.recipeImageService.loadImage(from: imageURL)
                if case .success(let image) = result {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            }
        }
        
        // Group Ingredients
        let groupedIngredients = Dictionary(grouping: recipe.ingredients) { $0.section ?? "" }
        
        // Sort sections: Empty ("") goes first (Main), then others by appearance order in original list or alphabetical
        // To preserve order, we can iterate through the original list and pick up sections as we see them
        var sections: [String] = []
        var seenSections = Set<String>()
        
        // If there are ingredients without sections, ensure "" is first
        if groupedIngredients[""] != nil {
            sections.append("")
            seenSections.insert("")
        }
        
        for ingredient in recipe.ingredients {
            let section = ingredient.section ?? ""
            if !seenSections.contains(section) {
                sections.append(section)
                seenSections.insert(section)
            }
        }
        
        ingredientSections = sections.map { sectionName in
            let ingredients = groupedIngredients[sectionName] ?? []
            let inputIngredients = ingredients.map { ingredient -> IngredientInput in
                var input = IngredientInput()
                input.name = ingredient.name
                
                if let quantity = ingredient.quantity {
                    let lowerFormatted = String(format: "%.2f", quantity.value).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                    
                    if let upper = quantity.upperValue {
                        let upperFormatted = String(format: "%.2f", upper).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
                        input.quantityText = "\(lowerFormatted)-\(upperFormatted)"
                    } else {
                         input.quantityText = lowerFormatted
                    }
                    
                    input.unit = quantity.unit
                }
                return input
            }
            return IngredientSectionInput(name: sectionName, ingredients: inputIngredients)
        }
        
        // Use default section if empty
        if ingredientSections.isEmpty {
            ingredientSections = [IngredientSectionInput(name: "", ingredients: [IngredientInput()])]
        }
        
        // Group Steps
        let groupedSteps = Dictionary(grouping: recipe.steps) { $0.section ?? "" }
        
        var stepSectionNames: [String] = []
        var seenStepSections = Set<String>()
        
        if groupedSteps[""] != nil {
            stepSectionNames.append("")
            seenStepSections.insert("")
        }
        
        for step in recipe.steps {
            let section = step.section ?? ""
            if !seenStepSections.contains(section) {
                stepSectionNames.append(section)
                seenStepSections.insert(section)
            }
        }
        
        stepSections = stepSectionNames.map { sectionName in
            let steps = groupedSteps[sectionName] ?? []
            let inputSteps = steps.map { step -> StepInput in
                var input = StepInput()
                input.text = step.text
                input.timers = step.timers.map { timer in
                    TimerInput(seconds: timer.seconds, label: timer.label)
                }
                return input
            }
            return StepSectionInput(name: sectionName, steps: inputSteps)
        }
        
        if stepSections.isEmpty {
            stepSections = [StepSectionInput(name: "", steps: [StepInput()])]
        }
        
        if let recipeNutrition = recipe.nutrition {
            nutrition.calories = recipeNutrition.calories
            nutrition.protein = recipeNutrition.protein
            nutrition.fat = recipeNutrition.fat
            nutrition.carbohydrates = recipeNutrition.carbohydrates
        }
    }
    
    // MARK: - Section Management
    
    func addIngredientSection() {
        ingredientSections.append(IngredientSectionInput(name: "", ingredients: [IngredientInput()]))
    }
    
    func removeIngredientSection(id: UUID) {
        if let index = ingredientSections.firstIndex(where: { $0.id == id }) {
            ingredientSections.remove(at: index)
        }
    }
    
    // START: Safe Section Binding Helpers
    func getIngredientSection(id: UUID) -> IngredientSectionInput {
        guard let section = ingredientSections.first(where: { $0.id == id }) else {
            return IngredientSectionInput()
        }
        return section
    }
    
    func updateIngredientSection(_ section: IngredientSectionInput) {
        guard let index = ingredientSections.firstIndex(where: { $0.id == section.id }) else { return }
        ingredientSections[index] = section
    }
    // END: Safe Section Binding Helpers
    
    // Deprecated index-based removal
    func removeIngredientSection(at index: Int) {
        if ingredientSections.indices.contains(index) {
            ingredientSections.remove(at: index)
        }
    }
    
    func addIngredient(to sectionIndex: Int) {
        guard ingredientSections.indices.contains(sectionIndex) else { return }
        ingredientSections[sectionIndex].ingredients.append(IngredientInput())
    }
    
    func deleteIngredient(id: UUID, in sectionID: UUID) {
        guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }) else { return }
        
        if let rowIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == id }) {
            ingredientSections[sectionIndex].ingredients.remove(at: rowIndex)
            
            // Auto-remove empty section if it's not the only one
            if ingredientSections[sectionIndex].ingredients.isEmpty && ingredientSections.count > 1 {
                removeIngredientSection(id: sectionID)
            }
        }
    }
    
    // START: Safe Binding Helpers
    func getIngredient(id: UUID, in sectionID: UUID) -> IngredientInput {
        guard let section = ingredientSections.first(where: { $0.id == sectionID }),
              let ingredient = section.ingredients.first(where: { $0.id == id }) else {
            return IngredientInput()
        }
        return ingredient
    }
    
    func updateIngredient(_ ingredient: IngredientInput, in sectionID: UUID) {
        guard let sectionIndex = ingredientSections.firstIndex(where: { $0.id == sectionID }),
              let rowIndex = ingredientSections[sectionIndex].ingredients.firstIndex(where: { $0.id == ingredient.id }) else {
            return
        }
        ingredientSections[sectionIndex].ingredients[rowIndex] = ingredient
    }
    // END: Safe Binding Helpers
    
    // Kept for compatibility but should be unused
    func deleteIngredient(at indexPath: IndexPath) {
        guard ingredientSections.indices.contains(indexPath.section),
              ingredientSections[indexPath.section].ingredients.indices.contains(indexPath.row) else { return }
        let sectionID = ingredientSections[indexPath.section].id
        let ingredientID = ingredientSections[indexPath.section].ingredients[indexPath.row].id
        deleteIngredient(id: ingredientID, in: sectionID)
    }
    
    func addStepSection() {
        stepSections.append(StepSectionInput(name: "", steps: [StepInput()]))
    }
    
    func removeStepSection(id: UUID) {
        if let index = stepSections.firstIndex(where: { $0.id == id }) {
            stepSections.remove(at: index)
        }
    }

    // START: Safe Section Binding Helpers
    func getStepSection(id: UUID) -> StepSectionInput {
        guard let section = stepSections.first(where: { $0.id == id }) else {
            return StepSectionInput()
        }
        return section
    }
    
    func updateStepSection(_ section: StepSectionInput) {
        guard let index = stepSections.firstIndex(where: { $0.id == section.id }) else { return }
        stepSections[index] = section
    }
    // END: Safe Section Binding Helpers

    // Deprecated index-based removal
    func removeStepSection(at index: Int) {
        if stepSections.indices.contains(index) {
            stepSections.remove(at: index)
        }
    }
    
    func addStep(to sectionIndex: Int) {
        guard stepSections.indices.contains(sectionIndex) else { return }
        stepSections[sectionIndex].steps.append(StepInput())
    }
    
    func deleteStep(id: UUID, in sectionID: UUID) {
        guard let sectionIndex = stepSections.firstIndex(where: { $0.id == sectionID }) else { return }
        
        if let rowIndex = stepSections[sectionIndex].steps.firstIndex(where: { $0.id == id }) {
            stepSections[sectionIndex].steps.remove(at: rowIndex)
            
            // Auto-remove empty section if it's not the only one
            if stepSections[sectionIndex].steps.isEmpty && stepSections.count > 1 {
                removeStepSection(id: sectionID)
            }
        }
    }
    
    // START: Safe Binding Helpers
    func getStep(id: UUID, in sectionID: UUID) -> StepInput {
        guard let section = stepSections.first(where: { $0.id == sectionID }),
              let step = section.steps.first(where: { $0.id == id }) else {
            return StepInput()
        }
        return step
    }
    
    func updateStep(_ step: StepInput, in sectionID: UUID) {
        guard let sectionIndex = stepSections.firstIndex(where: { $0.id == sectionID }),
              let rowIndex = stepSections[sectionIndex].steps.firstIndex(where: { $0.id == step.id }) else {
            return
        }
        stepSections[sectionIndex].steps[rowIndex] = step
    }
    // END: Safe Binding Helpers

    // Kept for compatibility but should be unused
    func deleteStep(at indexPath: IndexPath) {
        guard stepSections.indices.contains(indexPath.section),
              stepSections[indexPath.section].steps.indices.contains(indexPath.row) else { return }
        let sectionID = stepSections[indexPath.section].id
        let stepID = stepSections[indexPath.section].steps[indexPath.row].id
        deleteStep(id: stepID, in: sectionID)
    }
    
    func addTimer(to stepIndexPath: IndexPath) {
        guard stepSections.indices.contains(stepIndexPath.section),
              stepSections[stepIndexPath.section].steps.indices.contains(stepIndexPath.row) else { return }
        
        // Only add timer if not exists
        if stepSections[stepIndexPath.section].steps[stepIndexPath.row].timers.isEmpty {
            stepSections[stepIndexPath.section].steps[stepIndexPath.row].timers.append(TimerInput())
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

            // Handle image changes
            if let image = selectedImage {
                // New or changed image - save it
                let filename = try await dependencies.imageManager.saveImage(image, recipeId: recipe.id)
                let imageURL = await dependencies.imageManager.imageURL(for: filename)
                recipe = recipe.withImageURL(imageURL)

                // Cache the image immediately for optimistic UI updates
                // This ensures the new image appears instantly in all views
                let cacheKey = ImageCache.recipeImageKey(recipeId: recipe.id)
                await MainActor.run {
                    ImageCache.shared.set(cacheKey, image: image)
                }
            } else if existingRecipe?.imageURL != nil && selectedImage == nil {
                // Image was removed (existing recipe had image, but selectedImage is nil and wasn't loaded)
                // Clear the image URL so it gets deleted from CloudKit
                recipe = recipe.withImageURL(nil)

                // Clear the cached image as well
                let cacheKey = ImageCache.recipeImageKey(recipeId: recipe.id)
                await MainActor.run {
                    ImageCache.shared.remove(cacheKey)
                }
            }

            // Save to local database (CloudKit sync happens automatically in repository)
            // Check if recipe actually exists in database, not just if existingRecipe is set
            // This handles the case where an imported recipe is edited before being saved
            let recipeExists = await dependencies.recipeRepository.recipeExists(id: recipe.id)

            if recipeExists {
                try await dependencies.recipeRepository.update(recipe)
                // Notify other views that the recipe was updated
                NotificationCenter.default.post(name: NSNotification.Name("RecipeUpdated"), object: nil)
            } else {
                try await dependencies.recipeRepository.create(recipe)
                // Notify other views that a recipe was added
                NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)
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
        // Flatten ingredients from sections
        var recipeIngredients: [Ingredient] = []
        
        for section in ingredientSections {
            let sectionName = section.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : section.name.trimmingCharacters(in: .whitespaces)
            
            for input in section.ingredients where !input.name.isEmpty {
                let quantity: Quantity?
                if let parsed = input.parsedValues {
                    quantity = Quantity(value: parsed.value, upperValue: parsed.upperValue, unit: input.unit)
                } else {
                    quantity = nil
                }
                
                recipeIngredients.append(Ingredient(
                    name: input.name,
                    quantity: quantity,
                    note: nil,
                    section: sectionName
                ))
            }
        }
        
        guard !recipeIngredients.isEmpty else {
            throw RecipeEditorError.noIngredients
        }
        
        // Flatten steps from sections
        var recipeSteps: [CookStep] = []
        var stepIndex = 0
        
        for section in stepSections {
            let sectionName = section.name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : section.name.trimmingCharacters(in: .whitespaces)
            
            for input in section.steps where !input.text.isEmpty {
                let timers = input.timers.map { TimerSpec(seconds: $0.seconds, label: $0.label) }
                
                recipeSteps.append(CookStep(
                    index: stepIndex,
                    text: input.text,
                    timers: timers,
                    section: sectionName
                ))
                stepIndex += 1
            }
        }
        
        guard !recipeSteps.isEmpty else {
            throw RecipeEditorError.noSteps
        }
        
        // Build tags
        let recipeTags = selectedTags.map { Tag(name: $0.tagValue) }
        
        // Build related recipe IDs
        let relatedIds = relatedRecipes.map { $0.id }
        
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
                updatedAt: Date(),
                originalRecipeId: existing.originalRecipeId,
                originalCreatorId: existing.originalCreatorId,
                originalCreatorName: existing.originalCreatorName,
                savedAt: existing.savedAt,
                relatedRecipeIds: relatedIds
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
                ownerId: CurrentUserSession.shared.userId,
                relatedRecipeIds: relatedIds
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


