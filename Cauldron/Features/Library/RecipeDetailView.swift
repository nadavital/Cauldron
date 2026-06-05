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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State var recipe: Recipe
    @State var showingEditSheet = false
    @State var showSessionConflictAlert = false
    @State var scaleFactor: Double = 1.0
    @State var unitSystem: UnitSystem = .original
    @State var localIsFavorite: Bool
    @State var showingToast = false
    @State var recipeWasDeleted = false
    @State private var showDeleteConfirmation = false
    @State var recipeOwner: User?
    @State var isLoadingOwner = false
    @State var hasOwnedCopy = false
    @State private var showReferenceRemovedToast = false
    @State var currentVisibility: RecipeVisibility
    @State var isChangingVisibility = false
    @State var pendingVisibilityChange: RecipeVisibility?
    @State var pendingVisibilityImpact: RecipeVisibilityChangeImpact?
    @State var showVisibilityImpactAlert = false
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

    /// Ingredients after scaling, converted to the chosen measurement system.
    var displayedIngredients: [Ingredient] {
        UnitConverter.convert(scaledRecipe.ingredients, to: unitSystem)
    }

    private var shouldApplyBackgroundExtensionEffect: Bool {
        horizontalSizeClass == .regular
    }

    private var hasHeroImage: Bool {
        RecipeDetailDisplayPolicy.hasHeroImage(recipe)
    }

    private var recipeHeaderSection: some View {
        RecipeHeaderSection(
            recipe: recipe,
            scaledRecipe: scaledRecipe,
            scaledResult: scaledResult,
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
            onSaveRecipe: saveRecipeToLibrary,
            onUpdateRecipe: updateRecipeCopy
        )
        .padding(.top, hasHeroImage ? -80 : 0)
    }

    @ViewBuilder
    private var notesSection: some View {
        if let notes = recipe.notes, !notes.isEmpty {
            RecipeNotesSection(notes: notes)
        }
    }

    private var ingredientsSection: some View {
        RecipeIngredientsSection(ingredients: displayedIngredients)
    }

    private var stepsSection: some View {
        RecipeStepsSection(
            steps: scaledRecipe.steps,
            highlightedStepIndex: highlightedStepIndex,
            onTimerTap: startTimer
        )
    }

    @ViewBuilder
    private var nutritionSection: some View {
        if let nutrition = recipe.nutrition, nutrition.hasData {
            RecipeNutritionSection(nutrition: nutrition)
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        if !relatedRecipes.isEmpty {
            RecipeRelatedSection(relatedRecipes: relatedRecipes, dependencies: dependencies)
        }
    }

    @ViewBuilder
    private var compactRecipeContent: some View {
        GlassEffectContainer(spacing: 2) {
            VStack(alignment: .leading, spacing: 20) {
                recipeHeaderSection
                notesSection
                ingredientsSection
                stepsSection
                nutritionSection
                relatedSection
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, hasHeroImage ? 0 : 20)
        .padding(.bottom, 100)
    }

    @ViewBuilder
    private var regularRecipeContent: some View {
        GlassEffectContainer(spacing: 2) {
            VStack(alignment: .leading, spacing: 20) {
                recipeHeaderSection
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        ingredientsSection
                        notesSection
                    }
                    .frame(maxWidth: 430, alignment: .leading)

                    stepsSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                nutritionSection
                relatedSection
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, hasHeroImage ? 0 : 20)
        .padding(.bottom, 100)
        .frame(maxWidth: 1_080, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { scrollProxy in
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if hasHeroImage {
                                HeroRecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)
                                    .backgroundExtensionEffect(isEnabled: shouldApplyBackgroundExtensionEffect)
                                    .ignoresSafeArea(edges: .top)
                                    .id("\(recipe.imageURL?.absoluteString ?? "no-url")-\(recipe.id)-\(imageRefreshID)")
                            }

                            if horizontalSizeClass == .regular {
                                regularRecipeContent
                            } else {
                                compactRecipeContent
                            }
                        }
                        .frame(width: proxy.size.width, alignment: .leading)
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
            .ignoresSafeArea(edges: hasHeroImage ? .top : [])

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
                            .frame(width: 26, height: 26)

                        Text("Cook")
                            .font(.headline)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .tint(.cauldronOrange)
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            if recipe.isFollowingSourceUpdates {
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
        .alert("Remove from Public Collections?", isPresented: $showVisibilityImpactAlert) {
            Button("Cancel", role: .cancel) {
                pendingVisibilityChange = nil
                pendingVisibilityImpact = nil
            }
            Button("Make Private", role: .destructive) {
                let targetVisibility = pendingVisibilityChange ?? .privateRecipe
                pendingVisibilityChange = nil
                pendingVisibilityImpact = nil
                Task {
                    await changeVisibility(to: targetVisibility)
                }
            }
        } message: {
            if let impact = pendingVisibilityImpact {
                Text("This recipe is in \(impact.publicCollectionCount) public collection\(impact.publicCollectionCount == 1 ? "" : "s"). Making it private will remove it from those collections.")
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
            if notification.object is UUID {
                if !recipe.isOwnedByCurrentUser() {
                    Task {
                        await checkForOwnedCopy()
                    }
                }
            }
        }
        .task {
            let currentUserId = CurrentUserSession.shared.userId
            if RecipeDetailDisplayPolicy.shouldRefreshPublicRecipeOnOpen(recipe, currentUserId: currentUserId) {
                await refreshPublicRecipeIfNeeded()

                if RecipeDetailDisplayPolicy.shouldSaveAsPreviewOnOpen(recipe, currentUserId: currentUserId) {
                    await saveAsPreviewIfNeeded()
                }
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

            if recipe.isFollowingSourceUpdates {
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
            Menu {
                Picker("Scale", selection: $scaleFactor) {
                    Text("1/2x").tag(0.5)
                    Text("1x").tag(1.0)
                    Text("2x").tag(2.0)
                    Text("3x").tag(3.0)
                }
                .pickerStyle(.inline)

                Picker("Units", selection: $unitSystem) {
                    ForEach(UnitSystem.allCases) { system in
                        Text(system.label).tag(system)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(scaleFactorLabel, systemImage: "arrow.up.left.and.arrow.down.right")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if recipe.visibility == .publicRecipe {
                    Button {
                        Task {
                            await generateShareLink()
                        }
                    } label: {
                        Label(
                            isGeneratingShareLink ? "Creating Share Link" : "Share Recipe",
                            systemImage: isGeneratingShareLink ? "hourglass" : "square.and.arrow.up"
                        )
                    }
                    .disabled(isGeneratingShareLink)
                }

                Button {
                    Task {
                        await addToGroceryList()
                    }
                } label: {
                    Label("Add Ingredients to Groceries", systemImage: "cart.badge.plus")
                }

                if recipe.isOwnedByCurrentUser() {
                    Divider()

                    Picker("Visibility", selection: visibilitySelection) {
                        ForEach(RecipeVisibility.allCases, id: \.self) { visibility in
                            Label(visibility.displayName, systemImage: visibility.icon)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(.inline)
                    .disabled(isChangingVisibility)

                    Divider()

                    Button {
                        Task {
                            await prepareRecipeForEditing()
                        }
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
                    }
                } else if hasOwnedCopy {
                    Divider()

                    Button {
                        Task {
                            await prepareRecipeForEditing()
                        }
                    } label: {
                        Label("Edit Recipe", systemImage: "pencil")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var visibilitySelection: Binding<RecipeVisibility> {
        Binding(
            get: { currentVisibility },
            set: { newVisibility in
                guard newVisibility != currentVisibility else {
                    return
                }

                Task {
                    await requestVisibilityChange(to: newVisibility)
                }
            }
        )
    }

    private var scaleFactorLabel: String {
        switch scaleFactor {
        case 0.5:
            return "1/2x"
        case 1.0:
            return "1x"
        case 2.0:
            return "2x"
        case 3.0:
            return "3x"
        default:
            return "\(scaleFactor.formatted(.number.precision(.fractionLength(0...1))))x"
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
