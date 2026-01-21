//
//  RecipeDetailView.swift
//  Cauldron
//

import SwiftUI
import os

struct RecipeDetailView: View {
    let initialRecipe: Recipe
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @State var recipe: Recipe
    @State private var showingEditSheet = false
    @State var showSessionConflictAlert = false
    @State var scaleFactor: Double = 1.0
    @State var localIsFavorite: Bool
    @State var showingToast = false
    @State var recipeWasDeleted = false
    @State private var showDeleteConfirmation = false
    @State var recipeOwner: User?
    @State var isLoadingOwner = false
    @State var hasOwnedCopy = false
    @State private var showReferenceRemovedToast = false
    @State var showingVisibilityPicker = false
    @State var currentVisibility: RecipeVisibility
    @State var isChangingVisibility = false
    @State private var showingCollectionPicker = false
    @State var isSavingRecipe = false
    @State var showSaveSuccessToast = false
    @State var isCheckingDuplicates = false
    @State var showSaveRelatedRecipesPrompt = false
    @State var relatedRecipesToSave: [Recipe] = []
    @State var originalCreator: User?
    @State var isLoadingCreator = false
    @State var relatedRecipes: [Recipe] = []
    @State var imageRefreshID = UUID()

    @State var originalRecipe: Recipe?
    @State var isCheckingForUpdates = false
    @State var hasUpdates = false
    @State var isUpdatingRecipe = false
    @State var showUpdateSuccessToast = false

    @State var showErrorAlert = false
    @State var errorMessage: String?

    @State var showShareSheet = false
    @State var shareLink: ShareableLink?
    @State var isGeneratingShareLink = false

    let sharedBy: User?
    let sharedAt: Date?
    let explicitHighlightedStepIndex: Int?

    init(recipe: Recipe, dependencies: DependencyContainer, sharedBy: User? = nil, sharedAt: Date? = nil, highlightedStepIndex: Int? = nil) {
        self.initialRecipe = recipe
        self.dependencies = dependencies
        self.sharedBy = sharedBy
        self.sharedAt = sharedAt
        self.explicitHighlightedStepIndex = highlightedStepIndex
        self._recipe = State(initialValue: recipe)
        self._localIsFavorite = State(initialValue: recipe.isFavorite)
        self._currentVisibility = State(initialValue: recipe.visibility)
    }

    private var highlightedStepIndex: Int? {
        if let explicit = explicitHighlightedStepIndex {
            return explicit
        }
        let coordinator = dependencies.cookModeCoordinator
        if coordinator.isActive, coordinator.currentRecipe?.id == recipe.id {
            return coordinator.currentStepIndex
        }
        return nil
    }

    var scaledResult: ScaledRecipe {
        RecipeScaler.scale(recipe, by: scaleFactor)
    }

    var scaledRecipe: Recipe {
        scaledResult.recipe
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if recipe.imageURL != nil || recipe.cloudImageRecordName != nil {
                            HeroRecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                                .ignoresSafeArea(edges: .top)
                                .id("\(recipe.imageURL?.absoluteString ?? "no-url")-\(recipe.id)-\(imageRefreshID)")
                        }

                        VStack(alignment: .leading, spacing: 20) {
                            RecipeHeaderSection(
                                recipe: recipe,
                                scaledRecipe: scaledRecipe,
                                scaledResult: scaledResult,
                                scaleFactor: $scaleFactor,
                                currentVisibility: $currentVisibility,
                                localIsFavorite: $localIsFavorite,
                                hasOwnedCopy: hasOwnedCopy,
                                isSavingRecipe: isSavingRecipe,
                                isCheckingDuplicates: isCheckingDuplicates,
                                hasUpdates: hasUpdates,
                                isUpdatingRecipe: isUpdatingRecipe,
                                isLoadingCreator: isLoadingCreator,
                                sharedBy: sharedBy,
                                recipeOwner: recipeOwner,
                                originalCreator: originalCreator,
                                dependencies: dependencies,
                                onToggleFavorite: toggleFavorite,
                                onChangeVisibility: changeVisibility,
                                onSaveRecipe: saveRecipeToLibrary,
                                onUpdateRecipe: updateRecipeCopy
                            )
                            .padding(.top, (recipe.imageURL != nil || recipe.cloudImageRecordName != nil) ? -80 : 0)

                            if let notes = recipe.notes, !notes.isEmpty {
                                RecipeNotesSection(notes: notes)
                            }

                            RecipeIngredientsSection(ingredients: scaledRecipe.ingredients)

                            RecipeStepsSection(
                                steps: scaledRecipe.steps,
                                highlightedStepIndex: highlightedStepIndex,
                                onTimerTap: startTimer
                            )

                            if let nutrition = recipe.nutrition, nutrition.hasData {
                                RecipeNutritionSection(nutrition: nutrition)
                            }

                            if !relatedRecipes.isEmpty {
                                RecipeRelatedSection(relatedRecipes: relatedRecipes, dependencies: dependencies)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, recipe.imageURL != nil ? 0 : 20)
                        .padding(.bottom, 100)
                    }
                }
                .onAppear {
                    if let stepIndex = highlightedStepIndex {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                scrollProxy.scrollTo("step-\(stepIndex)", anchor: .center)
                            }
                        }
                    }
                }
            }
            .ignoresSafeArea(edges: (recipe.imageURL != nil || recipe.cloudImageRecordName != nil) ? .top : [])

            HStack {
                Spacer()

                Button {
                    handleCookButtonTap()
                } label: {
                    HStack(spacing: 8) {
                        Image("BrandMarks/CauldronIconSmall")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if recipe.originalRecipeId != nil {
                await checkForRecipeUpdates()
            }
        }
        .toolbar {
            toolbarContent
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
        .confirmationDialog(
            "Save Related Recipes?",
            isPresented: $showSaveRelatedRecipesPrompt,
            titleVisibility: .visible
        ) {
            Button("Save All (\(relatedRecipesToSave.count + 1) recipes)") {
                Task {
                    await performSaveRecipe(saveRelatedRecipes: true)
                }
            }
            Button("Just This Recipe") {
                Task {
                    await performSaveRecipe(saveRelatedRecipes: false)
                }
            }
            Button("Cancel", role: .cancel) {
                relatedRecipesToSave = []
            }
        } message: {
            Text("This recipe has \(relatedRecipesToSave.count) related recipe\(relatedRecipesToSave.count == 1 ? "" : "s"). Would you like to save them to your library as well?")
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
                ShareSheet(items: [LinkMetadataSource(link: link)])
            }
        }
        .toast(isShowing: $showingToast, icon: "cart.fill.badge.plus", message: "Added to grocery list")
        .toast(isShowing: $showReferenceRemovedToast, icon: "bookmark.slash", message: "Reference removed")
        .toast(isShowing: $showSaveSuccessToast, icon: "checkmark.circle.fill", message: "Saved to your recipes")
        .toast(isShowing: $showUpdateSuccessToast, icon: "arrow.triangle.2.circlepath", message: "Recipe updated successfully")
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated"))) { notification in
            if let updatedRecipeId = notification.object as? UUID {
                if updatedRecipeId == recipe.id {
                    Task {
                        await refreshRecipe()
                    }
                }
            } else {
                Task {
                    await refreshRecipe()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { notification in
            if let deletedRecipeId = notification.object as? UUID {
                if !recipe.isOwnedByCurrentUser() {
                    Task {
                        await checkForOwnedCopy()
                    }
                }
            }
        }
        .task {
            if !recipe.isOwnedByCurrentUser() && !recipe.isPreview {
                await saveAsPreviewIfNeeded()
            }

            if !recipe.isOwnedByCurrentUser() {
                await checkForOwnedCopy()

                if let ownerId = recipe.ownerId {
                    await loadRecipeOwner(ownerId)
                }
            }

            if let creatorId = recipe.originalCreatorId {
                await loadOriginalCreator(creatorId)
            }

            if recipe.originalRecipeId != nil {
                await checkForRecipeUpdates()
            }

            if !recipe.relatedRecipeIds.isEmpty {
                await loadRelatedRecipes()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
