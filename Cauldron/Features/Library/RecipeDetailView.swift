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
    @State private var showingCookMode = false
    @State private var showingEditSheet = false
    @State private var scaleFactor: Double = 1.0
    @State private var localIsFavorite: Bool
    @State private var scalingWarnings: [ScalingWarning] = []
    @State private var showingShareSheet = false
    @State private var showingToast = false
    @State private var recipeWasDeleted = false
    @State private var showDeleteConfirmation = false
    @State private var isConvertingToCopy = false
    @State private var showConvertSuccess = false
    @State private var recipeOwner: User?
    @State private var isLoadingOwner = false
    @State private var hasOwnedCopy = false
    @State private var showReferenceRemovedToast = false

    init(recipe: Recipe, dependencies: DependencyContainer) {
        self.recipe = recipe
        self.dependencies = dependencies
        self._localIsFavorite = State(initialValue: recipe.isFavorite)
    }
    
    private var scaledResult: ScaledRecipe {
        RecipeScaler.scale(recipe, by: scaleFactor)
    }
    
    private var scaledRecipe: Recipe {
        scaledResult.recipe
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Hero Image
                        if let imageURL = recipe.imageURL,
                           let image = loadImage(filename: imageURL.lastPathComponent) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width - 32, height: 300)
                                .clipped()
                                .cornerRadius(16)
                                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }

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
                    .frame(width: geometry.size.width - 32, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100) // Add padding for the button
                }
            }

            // Liquid Glass Cook Button
            HStack {
                Spacer()

                Button {
                    showingCookMode = true
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
                    .background(Capsule())
                    .glassEffect(.regular.tint(.orange).interactive())
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
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
                            showingShareSheet = true
                        } label: {
                            Label("Share Recipe", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            Task {
                                await addToGroceryList()
                            }
                        } label: {
                            Label("Add to Grocery List", systemImage: "cart.badge.plus")
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
                            Task {
                                await convertToCopy()
                            }
                        } label: {
                            if isConvertingToCopy {
                                Label("Converting...", systemImage: "doc.on.doc")
                            } else if hasOwnedCopy {
                                Label("Already Have a Copy", systemImage: "checkmark.circle.fill")
                            } else {
                                Label("Make a Copy", systemImage: "doc.on.doc")
                            }
                        }
                        .disabled(isConvertingToCopy || hasOwnedCopy)

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Remove Reference", systemImage: "bookmark.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            if recipe.isOwnedByCurrentUser() {
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteRecipe()
                    }
                }
            } else {
                Button("Remove Reference", role: .destructive) {
                    Task {
                        await deleteReference()
                    }
                }
            }
        } message: {
            if recipe.isOwnedByCurrentUser() {
                Text("Are you sure you want to delete \"\(recipe.title)\"? This cannot be undone.")
            } else {
                Text("This will remove the recipe reference from your collection. The original recipe will remain in the owner's collection.")
            }
        }
        .sheet(isPresented: $showingCookMode) {
            CookModeView(recipe: recipe, dependencies: dependencies)
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
        .sheet(isPresented: $showingShareSheet) {
            ShareRecipeView(recipe: recipe, dependencies: dependencies)
        }
        .toast(isShowing: $showingToast, icon: "cart.fill.badge.plus", message: "Added to grocery list")
        .toast(isShowing: $showReferenceRemovedToast, icon: "bookmark.slash", message: "Reference removed")
        .task {
            // Load recipe owner info if this is a reference
            if recipe.isReference, let ownerId = recipe.ownerId {
                await loadRecipeOwner(ownerId)
                // Check if user already has a copy of this recipe
                await checkForOwnedCopy()
            }
        }
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

            // Reference indicator banner
            if recipe.isReference {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.0))

                        Text("Recipe Reference")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("View-only. Tap the menu to make an editable copy.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    // Owner profile link button
                    if let owner = recipeOwner {
                        NavigationLink(destination: UserProfileView(user: owner, dependencies: dependencies)) {
                            HStack(spacing: 6) {
                                Image(systemName: "person.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.0))

                                Text("View \(owner.displayName)'s profile")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.0))

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if isLoadingOwner {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading owner info...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.5, green: 0.0, blue: 0.0).opacity(0.1))
                .cornerRadius(8)
            }

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

                        if !step.timers.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
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
    
    private func loadImage(filename: String) -> UIImage? {
        // Synchronous load for SwiftUI - consider caching for performance
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsURL.appendingPathComponent("RecipeImages").appendingPathComponent(filename)
        
        guard let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }
        return UIImage(data: imageData)
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

    /// Delete a recipe reference (bookmark to a shared recipe)
    ///
    /// This handles two scenarios:
    /// 1. Recipe was explicitly saved via "Add to My Recipes" - A RecipeReference record exists in CloudKit
    ///    → Delete the RecipeReference record, show toast, dismiss view
    ///
    /// 2. Recipe is being viewed from Sharing tab but was never saved - No RecipeReference exists
    ///    → This happens when viewing public recipes from cached queries
    ///    → Gracefully handle by just dismissing the view (nothing to delete)
    ///
    /// This method ensures we don't show errors to users when they try to remove recipes
    /// they're just browsing (as opposed to recipes they've explicitly saved).
    private func deleteReference() async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot delete reference - no current user")
            return
        }

        do {
            try await dependencies.recipeReferenceManager.deleteReference(
                for: recipe.id,
                userId: userId
            )
            AppLogger.general.info("Deleted recipe reference: \(recipe.title)")

            // Notify other views that a reference was removed
            NotificationCenter.default.post(name: NSNotification.Name("RecipeReferenceRemoved"), object: nil)

            // Show toast
            withAnimation {
                showReferenceRemovedToast = true
            }

            // Dismiss after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch RecipeReferenceError.referenceNotFound {
            // No RecipeReference found. This could mean:
            // 1. User is browsing a public recipe (never saved) - just dismiss
            // 2. Recipe is an orphaned local copy (exists in local DB but not as a reference) - delete it

            // Check if this recipe exists in local storage
            do {
                let localRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id)
                if localRecipe != nil {
                    // This is an orphaned local recipe - delete it from local storage
                    AppLogger.general.info("Found orphaned local recipe \(recipe.title) - deleting from local storage")
                    try await dependencies.recipeRepository.delete(id: recipe.id)

                    // Notify other views
                    NotificationCenter.default.post(name: NSNotification.Name("RecipeReferenceRemoved"), object: nil)

                    // Show toast
                    withAnimation {
                        showReferenceRemovedToast = true
                    }

                    // Dismiss after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                    }
                } else {
                    // Recipe only exists in PUBLIC database (browsing scenario) - just dismiss
                    AppLogger.general.info("No reference to delete for recipe \(recipe.title) - dismissing view")
                    NotificationCenter.default.post(name: NSNotification.Name("RecipeReferenceRemoved"), object: nil)
                    dismiss()
                }
            } catch {
                // Failed to check local storage - just dismiss gracefully
                AppLogger.general.warning("Could not check local storage for recipe: \(error.localizedDescription)")
                NotificationCenter.default.post(name: NSNotification.Name("RecipeReferenceRemoved"), object: nil)
                dismiss()
            }
        } catch {
            AppLogger.general.error("Failed to delete reference: \(error.localizedDescription)")
            // Show error to user in future enhancement
        }
    }

    private func convertToCopy() async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot convert to copy - no current user")
            return
        }

        isConvertingToCopy = true
        defer { isConvertingToCopy = false }

        do {
            let ownedCopy = try await dependencies.recipeReferenceManager.convertReferenceToOwnedCopyAndDeleteReference(
                recipe: recipe,
                currentUserId: userId
            )
            AppLogger.general.info("Converted reference to owned copy: \(ownedCopy.title)")

            // Show success state
            showConvertSuccess = true

            // Dismiss and navigate to the new copy
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            AppLogger.general.error("Failed to convert to copy: \(error.localizedDescription)")
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

