//
//  RecipeEditorView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os

/// Manual recipe editor for creating/editing recipes
struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: RecipeEditorViewModel
    @State private var showingImageOptions = false
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    @State private var showDeleteConfirmation = false

    let onDelete: (() -> Void)?
    let onSaveAndDismiss: (() -> Void)?

    init(dependencies: DependencyContainer, recipe: Recipe? = nil, onDelete: (() -> Void)? = nil, onSaveAndDismiss: (() -> Void)? = nil, isImporting: Bool = false) {
        _viewModel = StateObject(wrappedValue: RecipeEditorViewModel(dependencies: dependencies, existingRecipe: recipe, isImporting: isImporting))
        self.onDelete = onDelete
        self.onSaveAndDismiss = onSaveAndDismiss
    }
    
    var body: some View {
        NavigationStack {
            Form {
                imageSection
                basicInfoSection
                notesSection
                tagsSection
                ingredientsSection
                stepsSection
                nutritionSection
                deleteSection
                errorSection
            }
            .navigationTitle(viewModel.isEditing ? "Edit Recipe" : "New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark") {
                        // Prevent race condition by setting isSaving immediately
                        guard !viewModel.isSaving else { return }
                        viewModel.isSaving = true

                        Task {
                            if await viewModel.save() {
                                dismiss()
                                // Call callback if provided (used during import flow)
                                onSaveAndDismiss?()
                            } else {
                                viewModel.isSaving = false
                            }
                        }
                    }
                    .disabled(!viewModel.canSave || viewModel.isSaving)
                }
            }
            .sheet(isPresented: $showingImagePicker) {
                ImagePicker(image: $viewModel.selectedImage, sourceType: imagePickerSourceType)
            }
            .confirmationDialog("Add Recipe Image", isPresented: $showingImageOptions) {
                Button("Choose from Library") {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }
                
                Button("Take Photo") {
                    imagePickerSourceType = .camera
                    showingImagePicker = true
                }
                
                if viewModel.selectedImage != nil {
                    Button("Remove Image", role: .destructive) {
                        viewModel.selectedImage = nil
                    }
                }
                
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Select how you'd like to add an image to your recipe")
            }
            .alert("Delete Recipe?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteRecipe()
                }
            } message: {
                Text("Are you sure you want to delete this recipe? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Sections
    
    private var imageSection: some View {
        Section {
            if let image = viewModel.selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .clipped()
                
                // Change/Remove image button
                Button {
                    showingImageOptions = true
                } label: {
                    HStack {
                        Image(systemName: "photo.badge.plus")
                        Text("Change Image")
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.cauldronOrange.opacity(0.1))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            } else {
                // Tappable placeholder
                Button {
                    showingImageOptions = true
                } label: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.cauldronOrange.opacity(0.6))
                                Text("Tap to Add Image")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Choose from library or take a photo")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Recipe Image")
        }
    }
    
    private var basicInfoSection: some View {
        Section("Recipe Details") {
            TextField("Recipe Title", text: $viewModel.title)
            TextField("Yields (e.g., 4 servings)", text: $viewModel.yields)

            HStack {
                Text("Total Time")
                Spacer()
                TextField("Minutes", value: $viewModel.totalMinutes, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("min")
                    .foregroundColor(.secondary)
            }

            // Visibility dropdown
            Picker("Visibility", selection: $viewModel.visibility) {
                ForEach(RecipeVisibility.allCases, id: \.self) { visibility in
                    Label(visibility.displayName, systemImage: visibility.icon)
                        .tag(visibility)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var notesSection: some View {
        Section("Notes (Optional)") {
            TextEditor(text: $viewModel.notes)
                .frame(minHeight: 60)
        }
    }
    
    private var tagsSection: some View {
        Section("Tags") {
            VStack(alignment: .leading, spacing: 16) {
                selectedTagsSummary

                // Cuisine
                CategorySelectionRow(
                    title: "Cuisine",
                    icon: "map",
                    options: RecipeCategory.all(in: .cuisine),
                    selected: $viewModel.selectedTags,
                    horizontalPadding: 0
                )
                
                // Dietary
                CategorySelectionRow(
                    title: "Diet",
                    icon: "leaf",
                    options: RecipeCategory.all(in: .dietary),
                    selected: $viewModel.selectedTags,
                    horizontalPadding: 0
                )
                
                // Other
                CategorySelectionRow(
                    title: "Other",
                    icon: "tag",
                    options: RecipeCategory.all(in: .other),
                    selected: $viewModel.selectedTags,
                    horizontalPadding: 0
                )
                
                // Meal Type
                CategorySelectionRow(
                    title: "Meal",
                    icon: "fork.knife",
                    options: RecipeCategory.all(in: .mealType),
                    selected: $viewModel.selectedTags,
                    horizontalPadding: 0
                )
            }
            .padding(.vertical, 8)
        }
    }

    private var selectedTagsSummary: some View {
        Group {
            if !viewModel.selectedTags.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Selected", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.cauldronOrange)
                        .textCase(.uppercase)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(viewModel.selectedTags.sorted(by: { $0.tagValue < $1.tagValue })) { tag in
                                TagView(tag.tagValue, isSelected: true, onRemove: {
                                    withAnimation {
                                        _ = viewModel.selectedTags.remove(tag)
                                    }
                                })
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Divider()
            }
        }
    }
    
    private var ingredientsSection: some View {
        Section {
            ForEach(viewModel.ingredients.indices, id: \.self) { index in
                IngredientEditorRow(
                    ingredient: $viewModel.ingredients[index],
                    onDelete: { viewModel.deleteIngredient(at: index) }
                )
            }
            
            Button {
                viewModel.addIngredient()
            } label: {
                Label("Add Ingredient", systemImage: "plus.circle.fill")
                    .foregroundColor(.cauldronOrange)
            }
        } header: {
            Text("Ingredients")
        }
    }
    
    private var stepsSection: some View {
        Section {
            ForEach(viewModel.steps.indices, id: \.self) { index in
                StepEditorRow(
                    step: $viewModel.steps[index],
                    index: index,
                    onDelete: { viewModel.deleteStep(at: index) },
                    onAddTimer: { viewModel.addTimer(to: index) }
                )
            }
            
            Button {
                viewModel.addStep()
            } label: {
                Label("Add Step", systemImage: "plus.circle.fill")
                    .foregroundColor(.cauldronOrange)
            }
        } header: {
            Text("Steps")
        }
    }
    
    private var nutritionSection: some View {
        Section("Nutrition (Optional)") {
            NutritionEditorView(nutrition: $viewModel.nutrition)
        }
    }
    
    @ViewBuilder
    private var deleteSection: some View {
        if viewModel.isEditing {
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Recipe", systemImage: "trash")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }
    
    private func deleteRecipe() {
        Task {
            guard let recipe = viewModel.existingRecipe else { return }
            do {
                // Delete from local database
                try await viewModel.dependencies.recipeRepository.delete(id: recipe.id)

                // Delete from CloudKit if it was synced
                if recipe.cloudRecordName != nil {
                    do {
                        try await viewModel.dependencies.recipeSyncService.deleteRecipeFromCloud(recipe)
                        AppLogger.general.info("Recipe deleted from CloudKit: \(recipe.title)")
                    } catch {
                        AppLogger.general.warning("Failed to delete from CloudKit (continuing): \(error.localizedDescription)")
                    }
                }

                // Notify parent view that recipe was deleted
                onDelete?()

                dismiss()
            } catch {
                AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Ingredient Editor Row

struct IngredientEditorRow: View {
    @Binding var ingredient: IngredientInput
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Ingredient name
            TextField("Ingredient", text: $ingredient.name)
                .frame(minWidth: 100)
            
            // Quantity
            TextField("Amt", text: $ingredient.quantityText)
                .frame(width: 50)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            
            // Unit picker
            Picker("Unit", selection: $ingredient.unit) {
                ForEach(UnitKind.allCases, id: \.self) { unit in
                    Text(unit.compactDisplayName).tag(unit)
                }
            }
            .frame(width: 80)
            .labelsHidden()
            
            // Delete button
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundColor(.red)
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
        }
        .font(.body)
    }
}

// MARK: - Step Editor Row

struct StepEditorRow: View {
    @Binding var step: StepInput
    let index: Int
    let onDelete: () -> Void
    let onAddTimer: () -> Void
    @State private var hasTimer: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Step \(index + 1)")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
            }
            
            TextEditor(text: $step.text)
                .frame(minHeight: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            
            // Timer toggle
            Toggle(isOn: Binding(
                get: { !step.timers.isEmpty },
                set: { enabled in
                    if enabled && step.timers.isEmpty {
                        onAddTimer()
                    } else if !enabled {
                        step.timers.removeAll()
                    }
                }
            )) {
                Label("Add Timer", systemImage: "timer")
                    .font(.subheadline)
            }
            .toggleStyle(.switch)
            .padding(.vertical, 4)
            
            // Show only the first timer (limit to one timer per step)
            if let timerIndex = step.timers.indices.first {
                TimerEditorRow(timer: $step.timers[timerIndex])
                    .padding(.leading, 4)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Timer Editor Row

enum TimeUnit: String, CaseIterable {
    case seconds = "sec"
    case minutes = "min"
    case hours = "hr"
    
    var multiplier: Int {
        switch self {
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        }
    }
}

struct TimerEditorRow: View {
    @Binding var timer: TimerInput
    @State private var selectedUnit: TimeUnit = .minutes
    @State private var displayValue: Int = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .foregroundColor(.secondary)
                .imageScale(.medium)
            
            TextField("Time", value: $displayValue, format: .number)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .multilineTextAlignment(.center)
                .onChange(of: displayValue) { oldValue, newValue in
                    timer.seconds = newValue * selectedUnit.multiplier
                }
            
            Spacer()

            Picker("Unit", selection: $selectedUnit) {
                ForEach(TimeUnit.allCases, id: \.self) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .onChange(of: selectedUnit) { oldValue, newValue in
                // Convert current seconds to new unit
                displayValue = timer.seconds / newValue.multiplier
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .onAppear {
            // Initialize display value based on seconds
            if timer.seconds >= 3600 && timer.seconds % 3600 == 0 {
                selectedUnit = .hours
                displayValue = timer.seconds / 3600
            } else if timer.seconds >= 60 && timer.seconds % 60 == 0 {
                selectedUnit = .minutes
                displayValue = timer.seconds / 60
            } else {
                selectedUnit = .seconds
                displayValue = timer.seconds
            }
        }
    }
}

// MARK: - Nutrition Editor

struct NutritionEditorView: View {
    @Binding var nutrition: NutritionInput
    
    var body: some View {
        VStack(spacing: 12) {
            nutritionField("Calories", value: $nutrition.calories)
            nutritionField("Protein (g)", value: $nutrition.protein)
            nutritionField("Fat (g)", value: $nutrition.fat)
            nutritionField("Carbs (g)", value: $nutrition.carbohydrates)
        }
    }
    
    private func nutritionField(_ label: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

#Preview {
    RecipeEditorView(dependencies: .preview())
}
