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
    var additionalQuantities: [AdditionalQuantityInput] = []
    // Section is now handled by the parent container
    
    // Parse quantity text to handle fractions, decimals, and ranges
    var parsedValues: (value: Double, upperValue: Double?)? {
        QuantityTextParser.parse(quantityText)
    }
}

struct AdditionalQuantityInput: Identifiable {
    let id = UUID()
    var quantityText: String = ""
    var unit: UnitKind = .cup

    var parsedValues: (value: Double, upperValue: Double?)? {
        QuantityTextParser.parse(quantityText)
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
@Observable final class RecipeEditorViewModel {
    var title: String = ""
    var yields: String = "4 servings"
    var totalMinutes: Int? = nil
    var selectedTags: Set<RecipeCategory> = []
    var notes: String = ""

    // Grouped Sections
    var ingredientSections: [IngredientSectionInput] = [IngredientSectionInput(name: "", ingredients: [IngredientInput()])]
    var stepSections: [StepSectionInput] = [StepSectionInput(name: "", steps: [StepInput()])]

    var nutrition: NutritionInput = NutritionInput()
    var errorMessage: String?
    var isSaving: Bool = false
    var selectedImage: UIImage?
    var imageFilename: String?
    var visibility: RecipeVisibility = .publicRecipe
    private(set) var didUserChangeImageSelection: Bool = false

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
    
    var relatedRecipes: [Recipe] = []
    var availableRecipes: [Recipe] = []
    var isRelatedRecipesPickerPresented: Bool = false
    private var unresolvedRelatedRecipeIds: [UUID] = []
    
    func loadAvailableRecipes() async {
        do {
            let all = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await dependencies.recipeRepository.fetchAll(),
                currentUserId: CurrentUserSession.shared.userId
            )
            // Filter out self if editing
            await MainActor.run {
                availableRecipes = all.filter { $0.id != existingRecipe?.id }
            }
        } catch {
            AppLogger.general.error("Failed to load available recipes: \(error.localizedDescription)")
        }
    }
    
    func toggleRelatedRecipe(_ recipe: Recipe) {
        let referenceID = recipe.relatedGraphReferenceID
        if relatedRecipes.contains(where: { $0.id == recipe.id }) {
            relatedRecipes.removeAll(where: { $0.id == recipe.id })
            unresolvedRelatedRecipeIds.removeAll { $0 == referenceID || $0 == recipe.id }
        } else {
            relatedRecipes.append(recipe)
            unresolvedRelatedRecipeIds.removeAll { $0 == referenceID || $0 == recipe.id }
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

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    private func loadFromRecipe(_ recipe: Recipe) {
        title = recipe.title
        yields = recipe.yields
        totalMinutes = recipe.totalMinutes
        unresolvedRelatedRecipeIds = recipe.relatedRecipeIds
        
        // Load tags by matching them to RecipeCategory
        selectedTags = Set(recipe.tags.compactMap { tag in
            RecipeCategory.match(string: tag.name)
        })
        
        notes = recipe.notes ?? ""
        visibility = recipe.visibility
        
        Task {
            if !recipe.relatedRecipeIds.isEmpty {
                do {
                    let localResolution = try await dependencies.recipeRepository.resolveLocalRelatedRecipes(
                        referenceIds: recipe.relatedRecipeIds,
                        includePreviews: true
                    )
                    let resolvedRelated = localResolution.recipes

                    await MainActor.run {
                        self.relatedRecipes = resolvedRelated
                        let resolvedReferenceIDs = Set(resolvedRelated.map(\.relatedGraphReferenceID))
                        self.unresolvedRelatedRecipeIds = recipe.relatedRecipeIds.filter { !resolvedReferenceIDs.contains($0) }
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
                let result = await dependencies.recipeImageService.loadImage(
                    forRecipeId: recipe.id,
                    localURL: imageURL,
                    ownerId: recipe.ownerId
                )
                if case .success(let image) = result {
                    await MainActor.run {
                        self.setLoadedImage(image)
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
                    input.quantityText = formatQuantityText(quantity)
                    input.unit = quantity.unit
                }

                input.additionalQuantities = ingredient.additionalQuantities.map { quantity in
                    var additional = AdditionalQuantityInput()
                    additional.quantityText = formatQuantityText(quantity)
                    additional.unit = quantity.unit
                    return additional
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
            let didChangeImageSelection = didUserChangeImageSelection

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

            recipe = finalizeSourceTracking(for: recipe, didChangeImageSelection: didChangeImageSelection)

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

                let additionalQuantities: [Quantity] = input.additionalQuantities.compactMap { additional in
                    guard let parsed = additional.parsedValues else { return nil }
                    return Quantity(value: parsed.value, upperValue: parsed.upperValue, unit: additional.unit)
                }
                
                recipeIngredients.append(Ingredient(
                    name: input.name,
                    quantity: quantity,
                    additionalQuantities: additionalQuantities,
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
        let relatedIds = relatedRecipeIdsForSave()
        
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
            let draftRecipe = Recipe(
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
                cloudImageRecordName: existing.cloudImageRecordName,
                imageModifiedAt: existing.imageModifiedAt,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                originalRecipeId: existing.originalRecipeId,
                originalCreatorId: existing.originalCreatorId,
                originalCreatorName: existing.originalCreatorName,
                savedAt: existing.savedAt,
                sourceRecipeUpdatedAt: existing.sourceRecipeUpdatedAt,
                followsSourceUpdates: existing.followsSourceUpdates,
                relatedRecipeIds: relatedIds,
                isPreview: existing.isPreview
            )

            guard existing.originalRecipeId != nil else {
                return draftRecipe
            }

            let shouldContinueFollowing = existing.isFollowingSourceUpdates &&
                !draftRecipe.hasEditableDifferences(comparedTo: existing)

            return draftRecipe.withSourceTracking(
                sourceRecipeUpdatedAt: existing.sourceRecipeUpdatedAt ?? existing.savedAt ?? existing.updatedAt,
                followsSourceUpdates: shouldContinueFollowing
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

    private func formatQuantityText(_ quantity: Quantity) -> String {
        let lowerFormatted = String(format: "%.2f", quantity.value)
            .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)

        if let upper = quantity.upperValue {
            let upperFormatted = String(format: "%.2f", upper)
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
            return "\(lowerFormatted)-\(upperFormatted)"
        }

        return lowerFormatted
    }

    private func relatedRecipeIdsForSave() -> [UUID] {
        let selfReferenceID = existingRecipe?.relatedGraphReferenceID ?? existingRecipe?.id
        let candidateIDs = unresolvedRelatedRecipeIds + relatedRecipes.map(\.relatedGraphReferenceID)
        var seen = Set<UUID>()

        return candidateIDs.compactMap { id in
            guard id != selfReferenceID, seen.insert(id).inserted else {
                return nil
            }
            return id
        }
    }

    func updateSelectedImageFromUser(_ image: UIImage?) {
        selectedImage = image
        didUserChangeImageSelection = true
    }

    func removeSelectedImage() {
        selectedImage = nil
        didUserChangeImageSelection = true
    }

    private func setLoadedImage(_ image: UIImage) {
        selectedImage = image
    }

    private func finalizeSourceTracking(for recipe: Recipe, didChangeImageSelection: Bool) -> Recipe {
        guard let existingRecipe,
              existingRecipe.originalRecipeId != nil else {
            return recipe
        }

        let shouldContinueFollowing = recipe.isFollowingSourceUpdates && !didChangeImageSelection
        let sourceVersion = existingRecipe.sourceRecipeUpdatedAt ?? existingRecipe.savedAt ?? existingRecipe.updatedAt

        return recipe.withSourceTracking(
            sourceRecipeUpdatedAt: sourceVersion,
            followsSourceUpdates: shouldContinueFollowing
        )
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
