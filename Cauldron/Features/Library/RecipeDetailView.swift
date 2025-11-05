//
//  RecipeDetailView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import os

/// Detailed view of a recipe
struct RecipeDetailView: View {
    let recipe: Recipe
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showSessionConflictAlert = false
    @State private var scaleFactor: Double = 1.0
    @State private var localIsFavorite: Bool
    @State private var scalingWarnings: [ScalingWarning] = []
    @State private var showingToast = false
    @State private var recipeWasDeleted = false
    @State private var showDeleteConfirmation = false
    @State private var isConvertingToCopy = false
    @State private var showConvertSuccess = false
    @State private var recipeOwner: User?
    @State private var isLoadingOwner = false
    @State private var hasOwnedCopy = false
    @State private var showReferenceRemovedToast = false
    @State private var showingVisibilityPicker = false
    @State private var currentVisibility: RecipeVisibility
    @State private var isChangingVisibility = false
    @State private var showingCollectionPicker = false

    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        self._localIsFavorite = State(initialValue: recipe.isFavorite)
        self._currentVisibility = State(initialValue: recipe.visibility)
    }
    
    private var scaledResult: ScaledRecipe {
        RecipeScaler.scale(recipe, by: scaleFactor)
    }
    
    private var scaledRecipe: Recipe {
        scaledResult.recipe
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Hero Image - Stretches to top
                    if let imageURL = recipe.imageURL {
                        HeroRecipeImageView(imageURL: imageURL)
                            .ignoresSafeArea(edges: .top)
                    }

                    // Content sections
                    VStack(alignment: .leading, spacing: 20) {
                        // Header
                        headerSection

                        // Ingredients
                        ingredientsSection

                        // Steps
                        stepsSection

                        // Nutrition
                        if let nutrition = recipe.nutrition, nutrition.hasData {
                            nutritionSection(nutrition)
                        }

                        // Notes
                        if let notes = recipe.notes, !notes.isEmpty {
                            notesSection(notes)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, recipe.imageURL != nil ? 0 : 20)
                    .padding(.bottom, 100) // Add padding for the button
                }
            }

            // Liquid Glass Cook Button
            HStack {
                Spacer()

                Button {
                    handleCookButtonTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.body)

                        Text("Cook")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(.orange).interactive(), in: Capsule())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: localIsFavorite ? "star.fill" : "star")
                        .foregroundStyle(localIsFavorite ? .yellow : .primary)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if recipe.isOwnedByCurrentUser() {
                    // Owned recipe menu
                    Menu {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Label("Edit Recipe", systemImage: "pencil")
                        }

                        Button {
                            showingVisibilityPicker = true
                        } label: {
                            Label("Change Visibility", systemImage: currentVisibility.icon)
                        }

                        Button {
                            Task {
                                await addToGroceryList()
                            }
                        } label: {
                            Label("Add to Grocery List", systemImage: "cart.badge.plus")
                        }

                        Button {
                            showingCollectionPicker = true
                        } label: {
                            Label("Add to Collection", systemImage: "folder.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Recipe", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                } else {
                    // Referenced recipe menu (read-only)
                    Menu {
                        Button {
                            Task {
                                await addToGroceryList()
                            }
                        } label: {
                            Label("Add to Grocery List", systemImage: "cart.badge.plus")
                        }

                        Button {
                            showingCollectionPicker = true
                        } label: {
                            Label("Add to Collection", systemImage: "folder.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Recipe", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteRecipe()
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(recipe.title)\"? This cannot be undone.")
        }
        .alert("Recipe Already Cooking", isPresented: $showSessionConflictAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End & Start New") {
                Task {
                    await dependencies.cookModeCoordinator.startPendingRecipe()
                }
            }
        } message: {
            if let currentRecipe = dependencies.cookModeCoordinator.currentRecipe {
                Text("End '\(currentRecipe.title)' to start cooking '\(recipe.title)'?")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            RecipeEditorView(
                dependencies: dependencies,
                recipe: recipe,
                onDelete: {
                    recipeWasDeleted = true
                }
            )
        }
        .onChange(of: recipeWasDeleted) { _, wasDeleted in
            if wasDeleted {
                dismiss()
            }
        }
        .sheet(isPresented: $showingVisibilityPicker) {
            RecipeVisibilityPickerSheet(
                currentVisibility: $currentVisibility,
                isChanging: $isChangingVisibility,
                onSave: { newVisibility in
                    await changeVisibility(to: newVisibility)
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingCollectionPicker) {
            AddToCollectionSheet(recipe: recipe, dependencies: dependencies)
                .presentationDetents([.medium, .large])
        }
        .toast(isShowing: $showingToast, icon: "cart.fill.badge.plus", message: "Added to grocery list")
        .toast(isShowing: $showReferenceRemovedToast, icon: "bookmark.slash", message: "Reference removed")
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                if let time = recipe.displayTime {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.cauldronOrange)
                        Text(time)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.2")
                        .foregroundColor(.cauldronOrange)
                    Text(recipe.yields)
                }

                Spacer()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags) { tag in
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
                    .padding(.trailing, 1)
                }
                .frame(height: 30)
            }
            
            // Scale picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe Scale")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                Picker("Scale", selection: $scaleFactor) {
                    Text("½×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("3×").tag(3.0)
                }
                .pickerStyle(.segmented)
                
                // Scaling warnings
                if !scaledResult.warnings.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(scaledResult.warnings) { warning in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: warning.icon)
                                    .foregroundColor(warning.color)
                                    .font(.caption)
                                
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(warning.color.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .cardStyle()
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ingredients")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(scaledRecipe.ingredients) { ingredient in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.cauldronOrange)
                        .padding(.top, 6)
                        .fixedSize()

                    Text(ingredient.displayString)
                        .font(.body)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }
    
    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Instructions")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(recipe.steps) { step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(step.index + 1)")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.cauldronOrange)
                        .clipShape(Circle())
                        .fixedSize()

                    VStack(alignment: .leading, spacing: 8) {
                        Text(step.text)
                            .font(.body)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)

                        if let timer = step.timers.first {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
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
    
    private func notesSection(_ notes: String) -> some View {
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
    
    private func handleCookButtonTap() {
        // Check if different recipe is already cooking
        if dependencies.cookModeCoordinator.isActive,
           let currentRecipe = dependencies.cookModeCoordinator.currentRecipe,
           currentRecipe.id != recipe.id {
            // Show conflict alert
            dependencies.cookModeCoordinator.pendingRecipe = recipe
            showSessionConflictAlert = true
        } else {
            // Start cooking
            Task {
                await dependencies.cookModeCoordinator.startCooking(recipe)
            }
        }
    }

    private func addToGroceryList() async {
        do {
            // Convert ingredients to the format needed
            let items: [(name: String, quantity: Quantity?)] = scaledRecipe.ingredients.map {
                ($0.name, $0.quantity)
            }

            try await dependencies.groceryRepository.addItemsFromRecipe(
                recipeID: recipe.id.uuidString,
                recipeName: recipe.title,
                items: items
            )

            AppLogger.general.info("Added \(items.count) ingredients to grocery list from '\(recipe.title)'")

            // Show toast notification
            withAnimation {
                showingToast = true
            }
        } catch {
            AppLogger.general.error("Failed to add ingredients to grocery list: \(error.localizedDescription)")
        }
    }
    
    
    private func toggleFavorite() {
        Task {
            do {
                try await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                localIsFavorite.toggle()
            } catch {
                AppLogger.general.error("Failed to toggle favorite: \(error.localizedDescription)")
            }
        }
    }

    private func deleteRecipe() async {
        do {
            try await dependencies.recipeRepository.delete(id: recipe.id)
            AppLogger.general.info("Deleted recipe: \(recipe.title)")
            recipeWasDeleted = true
        } catch {
            AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
        }
    }

    private func loadRecipeOwner(_ ownerId: UUID) async {
        isLoadingOwner = true
        defer { isLoadingOwner = false }

        do {
            recipeOwner = try await dependencies.cloudKitService.fetchUser(byUserId: ownerId)
            AppLogger.general.info("Loaded recipe owner: \(recipeOwner?.displayName ?? "unknown")")
        } catch {
            AppLogger.general.warning("Failed to load recipe owner: \(error.localizedDescription)")
            // Don't show error to user - just don't display the profile link
        }
    }

    private func checkForOwnedCopy() async {
        guard let userId = CurrentUserSession.shared.userId else {
            return
        }

        do {
            hasOwnedCopy = try await dependencies.recipeRepository.hasSimilarRecipe(
                title: recipe.title,
                ownerId: userId,
                ingredientCount: recipe.ingredients.count
            )
            AppLogger.general.info("Owned copy check: \(hasOwnedCopy) for recipe '\(recipe.title)'")
        } catch {
            AppLogger.general.error("Failed to check for owned copy: \(error.localizedDescription)")
        }
    }

    private func changeVisibility(to newVisibility: RecipeVisibility) async {
        isChangingVisibility = true
        defer { isChangingVisibility = false }

        do {
            // Update the recipe's visibility in the repository
            try await dependencies.recipeRepository.updateVisibility(
                id: recipe.id,
                visibility: newVisibility
            )

            // Update local state
            currentVisibility = newVisibility

            AppLogger.general.info("Changed recipe '\(recipe.title)' visibility to \(newVisibility.displayName)")

            // Dismiss the sheet
            showingVisibilityPicker = false
        } catch {
            AppLogger.general.error("Failed to change visibility: \(error.localizedDescription)")
            // TODO: Show error to user
        }
    }
}

// MARK: - Recipe Visibility Picker Sheet

struct RecipeVisibilityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var currentVisibility: RecipeVisibility
    @Binding var isChanging: Bool
    let onSave: (RecipeVisibility) async -> Void

    @State private var selectedVisibility: RecipeVisibility

    init(
        currentVisibility: Binding<RecipeVisibility>,
        isChanging: Binding<Bool>,
        onSave: @escaping (RecipeVisibility) async -> Void
    ) {
        self._currentVisibility = currentVisibility
        self._isChanging = isChanging
        self.onSave = onSave
        self._selectedVisibility = State(initialValue: currentVisibility.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Visibility", selection: $selectedVisibility) {
                        ForEach(RecipeVisibility.allCases, id: \.self) { visibility in
                            Label(visibility.displayName, systemImage: visibility.icon)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    VStack(spacing: 8) {
                        Image(systemName: "eye")
                            .font(.system(size: 40))
                            .foregroundColor(.cauldronOrange)

                        Text("Choose who can see this recipe")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                    .textCase(nil)
                }

                Section {
                    Text(selectedVisibility.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Description")
                }
            }
            .navigationTitle("Recipe Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await onSave(selectedVisibility)
                        }
                    } label: {
                        if isChanging {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "checkmark")
                        }
                    }
                    .disabled(isChanging || selectedVisibility == currentVisibility)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecipeDetailView(
            recipe: Recipe(
                title: "Sample Recipe",
                ingredients: [
                    Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup)),
                    Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup))
                ],
                steps: [
                    CookStep(index: 0, text: "Mix dry ingredients", timers: []),
                    CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30)])
                ]
            ),
            dependencies: .preview()
        )
    }
}

