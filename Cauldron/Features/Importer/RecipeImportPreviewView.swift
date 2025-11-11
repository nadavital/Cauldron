//
//  RecipeImportPreviewView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI
import os

/// Preview and edit imported recipe before saving
struct RecipeImportPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let importedRecipe: Recipe
    let dependencies: DependencyContainer
    let sourceInfo: String
    let onSave: () -> Void  // Callback when recipe is saved
    
    @State private var editedRecipe: Recipe
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showingEditSheet = false
    
    init(importedRecipe: Recipe, dependencies: DependencyContainer, sourceInfo: String, onSave: @escaping () -> Void = {}) {
        self.importedRecipe = importedRecipe
        self.dependencies = dependencies
        self.sourceInfo = sourceInfo
        self.onSave = onSave
        self._editedRecipe = State(initialValue: importedRecipe)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Image - Card style
                    if let imageURL = editedRecipe.imageURL {
                        HeroRecipeImageView(imageURL: imageURL, recipeImageService: dependencies.recipeImageService)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        // Source info with link button
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.cauldronOrange)
                                Text(sourceInfo)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            // Source URL button if available
                            if let sourceURL = editedRecipe.sourceURL {
                                Button {
                                    UIApplication.shared.open(sourceURL)
                                } label: {
                                    HStack {
                                        Image(systemName: "link.circle.fill")
                                        Text("View Original Recipe")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "arrow.up.right")
                                    }
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.cauldronOrange)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(Color.cauldronSecondaryBackground)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    
                    // Recipe details
                    VStack(alignment: .leading, spacing: 16) {
                        // Title
                        Text(editedRecipe.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Meta info
                        HStack(spacing: 16) {
                            if let time = editedRecipe.displayTime {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .foregroundColor(.cauldronOrange)
                                    Text(time)
                                }
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "person.2")
                                    .foregroundColor(.cauldronOrange)
                                Text(editedRecipe.yields)
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        
                        // Tags
                        if !editedRecipe.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(editedRecipe.tags) { tag in
                                        Text(tag.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.cauldronOrange.opacity(0.15))
                                            .foregroundColor(.cauldronOrange)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Ingredients
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Ingredients")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(editedRecipe.ingredients) { ingredient in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(.cauldronOrange)
                                        .padding(.top, 6)
                                        .fixedSize()
                                    
                                    Text(ingredient.displayString)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .lineLimit(nil)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .cardStyle()
                    .padding(.horizontal)
                    
                    // Steps
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Instructions")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(editedRecipe.steps) { step in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(step.index + 1)")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color.cauldronOrange)
                                        .clipShape(Circle())
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(step.text)
                                            .font(.body)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        
                                        if !step.timers.isEmpty {
                                            HStack {
                                                ForEach(step.timers) { timer in
                                                    Label(timer.displayDuration, systemImage: "timer")
                                                        .font(.caption)
                                                        .foregroundColor(.cauldronOrange)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.cauldronOrange.opacity(0.1))
                                                        .cornerRadius(6)
                                                }
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .cardStyle()
                    .padding(.horizontal)
                    
                    // Nutrition (if any)
                    if let nutrition = editedRecipe.nutrition, nutrition.hasData {
                        nutritionSection(nutrition)
                            .padding(.horizontal)
                    }
                    
                    // Notes (if any)
                    if let notes = editedRecipe.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Notes")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            // Detect and make URLs clickable
                            if let attributedString = makeLinksClickable(notes) {
                                Text(attributedString)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .tint(.cauldronOrange)
                            } else {
                                Text(notes)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .cardStyle()
                        .padding(.horizontal)
                    }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                }
            }
            .navigationTitle("Preview Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit", systemImage: "pencil") {
                        showingEditSheet = true
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        // Prevent race condition by setting isSaving immediately
                        guard !isSaving else { return }
                        isSaving = true

                        Task {
                            await saveRecipe()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                RecipeEditorView(
                    dependencies: dependencies,
                    recipe: editedRecipe,
                    onSaveAndDismiss: {
                        // When editor saves during import, dismiss the entire import flow
                        onSave()
                        dismiss()
                    },
                    isImporting: true
                )
            }
            .alert("Recipe Saved!", isPresented: $showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Your recipe has been saved to your library.")
            }
        }
    }
    
    private func nutritionSection(_ nutrition: Nutrition) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nutrition")
                .font(.title2)
                .fontWeight(.bold)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let calories = nutrition.calories {
                    nutritionItem(label: "Calories", value: "\(Int(calories))")
                }
                if let protein = nutrition.protein {
                    nutritionItem(label: "Protein", value: "\(Int(protein))g")
                }
                if let carbs = nutrition.carbohydrates {
                    nutritionItem(label: "Carbs", value: "\(Int(carbs))g")
                }
                if let fat = nutrition.fat {
                    nutritionItem(label: "Fat", value: "\(Int(fat))g")
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    private func nutritionItem(label: String, value: String) -> some View {
        VStack {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cauldronOrange.opacity(0.1))
        .cornerRadius(8)
    }
    
    
    private func saveRecipe() async {
        // Note: isSaving is set in the button action to prevent race condition
        // It will be reset on error, and on success the view will dismiss

        do {
            // Add source URL to notes and ownerId for CloudKit sync
            var recipeToSave = editedRecipe
            let userId = CurrentUserSession.shared.userId

            if let sourceURL = editedRecipe.sourceURL {
                let sourceNote = "\n\nSource: \(sourceURL.absoluteString)"
                if let existingNotes = recipeToSave.notes {
                    recipeToSave = Recipe(
                        id: recipeToSave.id,
                        title: recipeToSave.title,
                        ingredients: recipeToSave.ingredients,
                        steps: recipeToSave.steps,
                        yields: recipeToSave.yields,
                        totalMinutes: recipeToSave.totalMinutes,
                        tags: recipeToSave.tags,
                        nutrition: recipeToSave.nutrition,
                        sourceURL: recipeToSave.sourceURL,
                        sourceTitle: recipeToSave.sourceTitle,
                        notes: existingNotes + sourceNote,
                        imageURL: recipeToSave.imageURL,
                        isFavorite: recipeToSave.isFavorite,
                        ownerId: userId,  // Add ownerId for CloudKit sync
                        createdAt: recipeToSave.createdAt,
                        updatedAt: recipeToSave.updatedAt
                    )
                } else {
                    recipeToSave = Recipe(
                        id: recipeToSave.id,
                        title: recipeToSave.title,
                        ingredients: recipeToSave.ingredients,
                        steps: recipeToSave.steps,
                        yields: recipeToSave.yields,
                        totalMinutes: recipeToSave.totalMinutes,
                        tags: recipeToSave.tags,
                        nutrition: recipeToSave.nutrition,
                        sourceURL: recipeToSave.sourceURL,
                        sourceTitle: recipeToSave.sourceTitle,
                        notes: "Source: \(sourceURL.absoluteString)",
                        imageURL: recipeToSave.imageURL,
                        isFavorite: recipeToSave.isFavorite,
                        ownerId: userId,  // Add ownerId for CloudKit sync
                        createdAt: recipeToSave.createdAt,
                        updatedAt: recipeToSave.updatedAt
                    )
                }
            } else if userId != nil {
                // No source URL but still need to add ownerId
                recipeToSave = Recipe(
                    id: recipeToSave.id,
                    title: recipeToSave.title,
                    ingredients: recipeToSave.ingredients,
                    steps: recipeToSave.steps,
                    yields: recipeToSave.yields,
                    totalMinutes: recipeToSave.totalMinutes,
                    tags: recipeToSave.tags,
                    nutrition: recipeToSave.nutrition,
                    sourceURL: recipeToSave.sourceURL,
                    sourceTitle: recipeToSave.sourceTitle,
                    notes: recipeToSave.notes,
                    imageURL: recipeToSave.imageURL,
                    isFavorite: recipeToSave.isFavorite,
                    ownerId: userId,
                    createdAt: recipeToSave.createdAt,
                    updatedAt: recipeToSave.updatedAt
                )
            }

            // Save to repository (CloudKit sync happens automatically)
            try await dependencies.recipeRepository.create(recipeToSave)
            AppLogger.parsing.info("Successfully saved imported recipe: \(recipeToSave.title)")

            // Call the callback to notify parent view
            onSave()

            // Dismiss this view
            dismiss()

        } catch {
            AppLogger.parsing.error("Failed to save recipe: \(error.localizedDescription)")
            isSaving = false
        }
    }
    
    private func makeLinksClickable(_ text: String) -> AttributedString? {
        var attributedString = AttributedString(text)
        
        // Regular expression to detect URLs
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        
        guard let matches = matches, !matches.isEmpty else {
            return nil
        }
        
        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let url = match.url {
                let startIndex = attributedString.characters.index(attributedString.startIndex, offsetBy: match.range.location)
                let endIndex = attributedString.characters.index(startIndex, offsetBy: match.range.length)
                let attributedRange = startIndex..<endIndex
                
                attributedString[attributedRange].link = url
                attributedString[attributedRange].foregroundColor = .cauldronOrange
                attributedString[attributedRange].underlineStyle = .single
            }
        }
        
        return attributedString
    }
}

#Preview {
    RecipeImportPreviewView(
        importedRecipe: Recipe(
            title: "Chocolate Chip Cookies",
            ingredients: [
                Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
                Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup))
            ],
            steps: [
                CookStep(index: 0, text: "Mix ingredients"),
                CookStep(index: 1, text: "Bake at 350°F for 12 minutes")
            ]
        ),
        dependencies: .preview(),
        sourceInfo: "Imported from allrecipes.com"
    )
}
