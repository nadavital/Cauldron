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
    let initialRecipe: Recipe
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State private var recipe: Recipe
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
    @State private var isSavingRecipe = false
    @State private var showSaveSuccessToast = false
    @State private var isCheckingDuplicates = false
    @State private var originalCreator: User?
    @State private var isLoadingCreator = false
    @State private var imageRefreshID = UUID() // Force image refresh

    // Recipe update sync state
    @State private var originalRecipe: Recipe?
    @State private var isCheckingForUpdates = false
    @State private var hasUpdates = false
    @State private var isUpdatingRecipe = false
    @State private var showUpdateSuccessToast = false

    // Error handling
    @State private var showErrorAlert = false
    @State private var errorMessage: String?

    // External sharing
    @State private var showShareSheet = false
    @State private var shareLink: ShareableLink?
    @State private var isGeneratingShareLink = false

    // Shared context
    let sharedBy: User?
    let sharedAt: Date?

    init(recipe: Recipe, dependencies: DependencyContainer, sharedBy: User? = nil, sharedAt: Date? = nil) {
        self.initialRecipe = recipe
        self.dependencies = dependencies
        self.sharedBy = sharedBy
        self.sharedAt = sharedAt
        self._recipe = State(initialValue: recipe)
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
                    if recipe.imageURL != nil || recipe.cloudImageRecordName != nil {
                        HeroRecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                            .ignoresSafeArea(edges: .top)
                            .id("\(recipe.imageURL?.absoluteString ?? "no-url")-\(recipe.id)-\(imageRefreshID)") // Force refresh when image URL or refresh ID changes
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
        .refreshable {
            // Only check for updates if this is a copied recipe
            if recipe.originalRecipeId != nil {
                await checkForRecipeUpdates()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if recipe.visibility == .publicRecipe {
                    Button {
                        Task {
                            await generateShareLink()
                        }
                    } label: {
                        if isGeneratingShareLink {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingShareLink)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await addToGroceryList()
                    }
                } label: {
                    Image(systemName: "cart.badge.plus")
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
                            showingCollectionPicker = true
                        } label: {
                            Label("Add to Collection", systemImage: "folder.badge.plus")
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Recipe", systemImage: "trash")
                                .foregroundStyle(.red)
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
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
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
        .onChange(of: showingEditSheet) { _, isPresented in
            // Refresh recipe data when edit sheet is dismissed
            if !isPresented {
                Task {
                    await refreshRecipe()
                }
            }
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
        .sheet(isPresented: $showShareSheet) {
            if let link = shareLink {
                ShareSheet(items: [link])
            }
        }
        .toast(isShowing: $showingToast, icon: "cart.fill.badge.plus", message: "Added to grocery list")
        .toast(isShowing: $showReferenceRemovedToast, icon: "bookmark.slash", message: "Reference removed")
        .toast(isShowing: $showSaveSuccessToast, icon: "checkmark.circle.fill", message: "Saved to your recipes")
        .toast(isShowing: $showUpdateSuccessToast, icon: "arrow.triangle.2.circlepath", message: "Recipe updated successfully")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated"))) { notification in
            // Refresh recipe when it's updated (e.g., CloudKit metadata added after image upload)
            // Only refresh if this is the same recipe (or if no specific recipe ID was provided)
            if let updatedRecipeId = notification.object as? UUID {
                if updatedRecipeId == recipe.id {
                    Task {
                        await refreshRecipe()
                    }
                }
            } else {
                // No specific recipe ID - refresh anyway (for backwards compatibility)
                Task {
                    await refreshRecipe()
                }
            }
        }
        .task {
            // Check for duplicates when viewing someone else's recipe
            if !recipe.isOwnedByCurrentUser() {
                await checkForOwnedCopy()

                // Load owner info for proper attribution when saving
                if let ownerId = recipe.ownerId {
                    await loadRecipeOwner(ownerId)
                }
            }

            // Load original creator for saved recipes to enable profile link
            if let creatorId = recipe.originalCreatorId {
                await loadOriginalCreator(creatorId)
            }

            // Check for updates if this is a copied recipe
            if recipe.originalRecipeId != nil {
                await checkForRecipeUpdates()
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
                
                if recipe.isOwnedByCurrentUser() || hasOwnedCopy {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: localIsFavorite ? "star.fill" : "star")
                            .foregroundStyle(localIsFavorite ? .yellow : .secondary)
                            .font(.title3)
                    }


                }
            }
            .foregroundColor(.secondary)

            if !recipe.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recipe.tags) { tag in
                            NavigationLink(destination: ExploreTagView(tag: tag, dependencies: dependencies)) {
                                TagView(tag)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 1)
                }
                .frame(height: 34)
            }

            // Shared By Banner
            if let user = sharedBy {
                NavigationLink {
                    UserProfileView(user: user, dependencies: dependencies)
                } label: {
                    HStack {
                        ProfileAvatar(user: user, size: 32, dependencies: dependencies)
                        
                        Text("Shared by \(user.displayName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color(uiColor: .tertiaryLabel))
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Attribution for saved recipes
            if let creatorName = recipe.originalCreatorName {
                Group {
                    if let creator = originalCreator {
                        NavigationLink {
                            UserProfileView(user: creator, dependencies: dependencies)
                        } label: {
                            attributionContent(creatorName: creatorName, showChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        attributionContent(creatorName: creatorName, showChevron: false)
                    }
                }
            }

            // Updates Available Banner
            if hasUpdates {
                Button {
                    Task {
                        await updateRecipeCopy()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Update Available")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)

                            Text("The original recipe has been updated")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if isUpdatingRecipe {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingRecipe)
            }

            // Settings Row (Visibility & Scale)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Visibility Picker (Only for owned recipes)
                    if recipe.isOwnedByCurrentUser() {
                        Menu {
                            Picker("Visibility", selection: Binding(
                                get: { currentVisibility },
                                set: { newValue in
                                    Task {
                                        await changeVisibility(to: newValue)
                                    }
                                }
                            )) {
                                ForEach([RecipeVisibility.publicRecipe, RecipeVisibility.privateRecipe], id: \.self) { visibility in
                                    Label(visibility.displayName, systemImage: visibility.icon)
                                        .tag(visibility)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: currentVisibility.icon)
                                Text(currentVisibility.displayName)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.15))
                            .foregroundColor(.cauldronOrange)
                            .clipShape(Capsule())
                        }
                    }

                    // Save Button (For non-owned recipes)
                    if !recipe.isOwnedByCurrentUser() {
                        Button {
                            Task {
                                await saveRecipeToLibrary()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isSavingRecipe {
                                    ProgressView()
                                        .tint(.cauldronOrange)
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else if hasOwnedCopy {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                } else {
                                    Image(systemName: "bookmark")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                }
                                
                                Text(hasOwnedCopy ? "Saved" : "Save")
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.15))
                            .foregroundColor(.cauldronOrange)
                            .clipShape(Capsule())
                        }
                        .disabled(isSavingRecipe || hasOwnedCopy || isCheckingDuplicates)
                    }

                    // Scale Picker
                    Menu {
                        Picker("Scale", selection: $scaleFactor) {
                            Text("½×").tag(0.5)
                            Text("1×").tag(1.0)
                            Text("2×").tag(2.0)
                            Text("3×").tag(3.0)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("\(scaleFactor.formatted())x")
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cauldronOrange.opacity(0.15))
                        .foregroundColor(.cauldronOrange)
                        .clipShape(Capsule())
                    }
                }
                
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

    @ViewBuilder
    private func attributionContent(creatorName: String, showChevron: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .foregroundColor(.cauldronOrange)

            VStack(alignment: .leading, spacing: 3) {
                Text("Recipe by \(creatorName)")
                    .font(.subheadline)
                    .foregroundColor(.primary)

                if let savedDate = recipe.savedAt {
                    Text("Saved \(savedDate.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Show loading or chevron
            if isLoadingCreator {
                ProgressView()
                    .scaleEffect(0.8)
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.cauldronOrange.opacity(0.08))
        .cornerRadius(10)
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ingredients", systemImage: "basket")
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
            Label("Instructions", systemImage: "list.number")
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
            Label("Nutrition", systemImage: "chart.bar.fill")
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
            Label("Notes", systemImage: "note.text")
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

    private func generateShareLink() async {
        isGeneratingShareLink = true

        do {
            let link = try await dependencies.externalShareService.shareRecipe(recipe)
            shareLink = link
            showShareSheet = true
        } catch {
            errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            showErrorAlert = true
            AppLogger.general.error("Failed to generate share link: \(error.localizedDescription)")
        }

        isGeneratingShareLink = false
    }

    private func refreshRecipe() async {
        do {
            // Fetch the latest version of the recipe from the database
            if let updatedRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id) {
                recipe = updatedRecipe
                localIsFavorite = updatedRecipe.isFavorite
                currentVisibility = updatedRecipe.visibility

                // Force image view to refresh by changing its ID
                // This is necessary because the view is behind a sheet and might not detect URL changes
                imageRefreshID = UUID()

                AppLogger.general.info("✅ Refreshed recipe: \(updatedRecipe.title)")
            }
        } catch {
            AppLogger.general.error("Failed to refresh recipe: \(error.localizedDescription)")
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

    private func loadOriginalCreator(_ creatorId: UUID) async {
        isLoadingCreator = true
        defer { isLoadingCreator = false }

        do {
            originalCreator = try await dependencies.cloudKitService.fetchUser(byUserId: creatorId)
            AppLogger.general.info("Loaded original creator: \(originalCreator?.displayName ?? "unknown")")
        } catch {
            AppLogger.general.warning("Failed to load original creator: \(error.localizedDescription)")
            // Don't show error to user - attribution will still show name without profile link
        }
    }

    private func saveRecipeToLibrary() async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot save recipe - no current user")
            return
        }

        isSavingRecipe = true
        defer { isSavingRecipe = false }

        do {
            // Create a copy of the recipe owned by the current user
            let copiedRecipe = recipe.withOwner(
                userId,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipeOwner?.displayName
            )

            try await dependencies.recipeRepository.create(copiedRecipe)
            AppLogger.general.info("✅ Saved recipe to library: \(recipe.title)")

            // Notify other views
            NotificationCenter.default.post(name: NSNotification.Name("RecipeAdded"), object: nil)

            // Update state and switch to the new recipe immediately
            // This ensures the UI transitions from "Save" button to Visibility Picker
            withAnimation {
                recipe = copiedRecipe
                currentVisibility = copiedRecipe.visibility
                localIsFavorite = copiedRecipe.isFavorite
                hasOwnedCopy = true
                showSaveSuccessToast = true
            }
        } catch {
            AppLogger.general.error("❌ Failed to save recipe: \(error.localizedDescription)")
            errorMessage = "Failed to save recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func checkForOwnedCopy() async {
        guard let userId = CurrentUserSession.shared.userId else {
            return
        }

        isCheckingDuplicates = true
        defer { isCheckingDuplicates = false }

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
            
            // CRITICAL: Update the recipe object itself so the toolbar updates immediately
            withAnimation {
                recipe = Recipe(
                    id: recipe.id,
                    title: recipe.title,
                    ingredients: recipe.ingredients,
                    steps: recipe.steps,
                    yields: recipe.yields,
                    totalMinutes: recipe.totalMinutes,
                    tags: recipe.tags,
                    nutrition: recipe.nutrition,
                    sourceURL: recipe.sourceURL,
                    sourceTitle: recipe.sourceTitle,
                    notes: recipe.notes,
                    imageURL: recipe.imageURL,
                    isFavorite: recipe.isFavorite,
                    visibility: newVisibility, // Update visibility
                    ownerId: recipe.ownerId,
                    cloudRecordName: recipe.cloudRecordName,
                    cloudImageRecordName: recipe.cloudImageRecordName,
                    imageModifiedAt: recipe.imageModifiedAt,
                    createdAt: recipe.createdAt,
                    updatedAt: Date(), // Update timestamp
                    originalRecipeId: recipe.originalRecipeId,
                    originalCreatorId: recipe.originalCreatorId,
                    originalCreatorName: recipe.originalCreatorName,
                    savedAt: recipe.savedAt
                )
            }

            AppLogger.general.info("Changed recipe '\(recipe.title)' visibility to \(newVisibility.displayName)")

            // Dismiss the sheet
            showingVisibilityPicker = false
        } catch {
            AppLogger.general.error("Failed to change visibility: \(error.localizedDescription)")
            errorMessage = "Failed to change visibility: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    // MARK: - Recipe Update Sync

    /// Check if the original recipe has been updated since this copy was saved
    private func checkForRecipeUpdates() async {
        // Only check for updates if this is a copied recipe
        guard let originalRecipeId = recipe.originalRecipeId,
              let originalOwnerId = recipe.originalCreatorId else {
            return
        }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            // Fetch the original recipe from CloudKit public database
            let original = try await dependencies.cloudKitService.fetchPublicRecipe(
                recipeId: originalRecipeId,
                ownerId: originalOwnerId
            )

            originalRecipe = original

            // Check if the original has been updated after this copy was saved
            if let savedAt = recipe.savedAt,
               original.updatedAt > savedAt {
                hasUpdates = true
                AppLogger.general.info("🔄 Updates available for recipe '\(recipe.title)': original updated at \(original.updatedAt), saved at \(savedAt)")
            } else {
                hasUpdates = false
                AppLogger.general.info("✅ Recipe '\(recipe.title)' is up to date")
            }
        } catch {
            AppLogger.general.error("❌ Failed to check for recipe updates: \(error.localizedDescription)")
            // Silently fail - user can manually refresh later
            hasUpdates = false
        }
    }

    /// Update the local copy with changes from the original recipe
    private func updateRecipeCopy() async {
        guard let original = originalRecipe else {
            AppLogger.general.error("Cannot update recipe - original not loaded")
            return
        }

        isUpdatingRecipe = true
        defer { isUpdatingRecipe = false }

        do {
            // Create an updated copy preserving the local recipe's ID and attribution
            let updatedRecipe = Recipe(
                id: recipe.id, // Keep the same ID
                title: original.title,
                ingredients: original.ingredients,
                steps: original.steps,
                yields: original.yields,
                totalMinutes: original.totalMinutes,
                tags: original.tags,
                nutrition: original.nutrition,
                sourceURL: original.sourceURL,
                sourceTitle: original.sourceTitle,
                notes: original.notes,
                imageURL: original.imageURL,
                isFavorite: recipe.isFavorite, // Preserve local favorite status
                visibility: recipe.visibility, // Preserve local visibility
                ownerId: recipe.ownerId, // Keep current owner
                cloudRecordName: recipe.cloudRecordName,
                cloudImageRecordName: recipe.cloudImageRecordName,
                imageModifiedAt: recipe.imageModifiedAt,
                createdAt: recipe.createdAt, // Preserve original creation date
                updatedAt: Date(), // Update timestamp
                originalRecipeId: recipe.originalRecipeId, // Preserve link to original
                originalCreatorId: recipe.originalCreatorId,
                originalCreatorName: recipe.originalCreatorName,
                savedAt: Date() // Update the "saved at" timestamp
            )

            // Save the updated recipe
            try await dependencies.recipeRepository.update(updatedRecipe)

            AppLogger.general.info("✅ Successfully updated recipe '\(recipe.title)' from original")

            // Clear the update flag
            hasUpdates = false

            // Show success toast
            withAnimation {
                showUpdateSuccessToast = true
            }

            // Notify other views that the recipe was updated
            NotificationCenter.default.post(name: NSNotification.Name("RecipeUpdated"), object: nil)
        } catch {
            AppLogger.general.error("❌ Failed to update recipe: \(error.localizedDescription)")
            errorMessage = "Failed to update recipe: \(error.localizedDescription)"
            showErrorAlert = true
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

