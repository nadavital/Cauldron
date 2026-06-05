//
//  CollectionRecipeSelectorSheet.swift
//  Cauldron
//
//  Extracted from CollectionDetailView.swift to keep views focused.
//

import SwiftUI
import os

struct CollectionRecipeSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let collection: Collection
    let dependencies: DependencyContainer
    let onDismiss: () -> Void

    @State private var recipes: [Recipe] = []
    @State private var selectedRecipeIds: Set<UUID>
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var showingCopyConfirmation: Recipe?
    @State private var isCopying = false
    @State private var recipeOwnerCache: [UUID: User] = [:]  // Cache recipe owners by userId
    @State private var showingPublicMembershipRepairConfirmation = false
    @State private var pendingPublicMembershipRepairPlan = PublicCollectionMembershipRepairPlan(
        privateOwnedRecipeCount: 0,
        referencedRecipeCount: 0
    )
    @State private var pendingPublicMembershipConfirmationAction: PublicMembershipConfirmationAction?

    private enum PublicMembershipConfirmationAction {
        case saveSelections
        case copyRecipe(Recipe)
    }

    init(collection: Collection, dependencies: DependencyContainer, onDismiss: @escaping () -> Void) {
        self.collection = collection
        self.dependencies = dependencies
        self.onDismiss = onDismiss
        self._selectedRecipeIds = State(initialValue: Set(collection.recipeIds))
    }

    // Separate owned recipes from references
    var ownedRecipes: [Recipe] {
        recipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId == currentUserId
        }
    }

    var referencedRecipes: [Recipe] {
        recipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId != currentUserId
        }
    }

    var filteredOwnedRecipes: [Recipe] {
        if searchText.isEmpty {
            return ownedRecipes
        } else {
            let lowercased = searchText.lowercased()
            return ownedRecipes.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
    }

    var filteredReferencedRecipes: [Recipe] {
        if searchText.isEmpty {
            return referencedRecipes
        } else {
            let lowercased = searchText.lowercased()
            return referencedRecipes.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading recipes...")
                } else if recipes.isEmpty {
                    emptyState
                } else {
                    List {
                        // Owned recipes section (selectable)
                        if !filteredOwnedRecipes.isEmpty {
                            Section {
                                ForEach(filteredOwnedRecipes) { recipe in
                                    Button {
                                        toggleRecipe(recipe.id)
                                    } label: {
                                        recipeRow(recipe: recipe, isSelectable: true, dependencies: dependencies)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Your Recipes")
                            }
                        }

                        // Referenced recipes section (with copy option)
                        if !filteredReferencedRecipes.isEmpty {
                            Section {
                                ForEach(filteredReferencedRecipes) { recipe in
                                    Button {
                                        showingCopyConfirmation = recipe
                                    } label: {
                                        recipeRow(recipe: recipe, isSelectable: false, dependencies: dependencies)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Saved from Others")
                            } footer: {
                                Text("To add these to your collection, you'll need to add them to your recipes first")
                                    .font(.caption)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .confirmationDialog(
                showingCopyConfirmation?.title ?? "",
                isPresented: Binding(
                    get: { showingCopyConfirmation != nil },
                    set: { if !$0 { showingCopyConfirmation = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Save Copy to Collection") {
                    if let recipe = showingCopyConfirmation {
                        Task {
                            await copyAndAddRecipe(recipe)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    showingCopyConfirmation = nil
                }
            } message: {
                Text("This recipe is saved from another user. To add it to your collection, you need to save your own copy.")
            }
            .alert(
                "Make Recipes Public?",
                isPresented: $showingPublicMembershipRepairConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    Task {
                        await continueAfterPublicMembershipConfirmation()
                    }
                }
            } message: {
                Text(pendingPublicMembershipRepairPlan.confirmationMessage)
            }
            .task {
                await loadRecipes()
            }
        }
    }

    @ViewBuilder
    private func recipeRow(recipe: Recipe, isSelectable: Bool, dependencies: DependencyContainer) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)
                .overlay(
                    Group {
                        if !isSelectable {
                            // Reference badge
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundStyle(Color(red: 0.5, green: 0.0, blue: 0.0))
                                .padding(6)
                                .background(Circle().fill(.ultraThinMaterial))
                                .padding(6)
                        }
                    },
                    alignment: .topLeading
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if !recipe.tags.isEmpty {
                    Text(recipe.tags.first!.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelectable {
                if selectedRecipeIds.contains(recipe.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cauldronOrange)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                }
            } else {
                // Show "Copy" indicator for references
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.cauldronOrange)
                    .font(.caption)
            }
        }
    }

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load owned recipes from local storage
            recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                try await dependencies.recipeRepository.fetchAll(),
                currentUserId: CurrentUserSession.shared.userId
            )
            AppLogger.general.info("✅ Loaded \(recipes.count) owned recipes for collection selector")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes for selector: \(error.localizedDescription)")
        }
    }

    private func saveChanges(confirmingPublicMembershipRepair: Bool = false) async {
        do {
            let recipeIds = orderedSelectedRecipeIds()
            if !confirmingPublicMembershipRepair {
                let repairPlan = try await dependencies.publicCollectionMembershipResolver.repairPlan(
                    recipeIds: recipeIds,
                    ownerId: collection.userId,
                    visibility: collection.visibility
                )
                if repairPlan.requiresRepair {
                    pendingPublicMembershipRepairPlan = repairPlan
                    pendingPublicMembershipConfirmationAction = .saveSelections
                    showingPublicMembershipRepairConfirmation = true
                    return
                }
            }

            let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
                recipeIds: recipeIds,
                ownerId: collection.userId,
                visibility: collection.visibility
            )
            let updatedCollection = collection.updated(recipeIds: resolution.recipeIds)
            try await dependencies.collectionRepository.update(updatedCollection)

            dismiss()
            onDismiss()
            AppLogger.general.info("✅ Saved collection recipe membership")
        } catch {
            AppLogger.general.error("❌ Failed to save collection changes: \(error.localizedDescription)")
        }
    }

    private func publicMembershipRepairPlanForCopyingReferencedRecipe() async throws -> PublicCollectionMembershipRepairPlan {
        guard collection.visibility == .publicRecipe else {
            return PublicCollectionMembershipRepairPlan(privateOwnedRecipeCount: 0, referencedRecipeCount: 0)
        }

        let repairPlan = try await dependencies.publicCollectionMembershipResolver.repairPlan(
            recipeIds: collection.recipeIds,
            ownerId: collection.userId,
            visibility: collection.visibility
        )
        return PublicCollectionMembershipRepairPlan(
            privateOwnedRecipeCount: repairPlan.privateOwnedRecipeCount,
            referencedRecipeCount: repairPlan.referencedRecipeCount + 1
        )
    }

    private func continueAfterPublicMembershipConfirmation() async {
        let action = pendingPublicMembershipConfirmationAction
        pendingPublicMembershipConfirmationAction = nil

        switch action {
        case .saveSelections:
            await saveChanges(confirmingPublicMembershipRepair: true)
        case .copyRecipe(let recipe):
            await copyAndAddRecipe(recipe, confirmingPublicMembershipRepair: true)
        case nil:
            break
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Recipes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create some recipes first to add them to collections")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func toggleRecipe(_ recipeId: UUID) {
        if selectedRecipeIds.contains(recipeId) {
            selectedRecipeIds.remove(recipeId)
        } else {
            selectedRecipeIds.insert(recipeId)
        }
    }

    private func orderedSelectedRecipeIds() -> [UUID] {
        var orderedIds: [UUID] = []
        var seenIds = Set<UUID>()

        for recipeId in collection.recipeIds where selectedRecipeIds.contains(recipeId) {
            if seenIds.insert(recipeId).inserted {
                orderedIds.append(recipeId)
            }
        }

        for recipeId in recipes.map(\.id) where selectedRecipeIds.contains(recipeId) {
            if seenIds.insert(recipeId).inserted {
                orderedIds.append(recipeId)
            }
        }

        for recipeId in selectedRecipeIds.sorted(by: { $0.uuidString < $1.uuidString }) {
            if seenIds.insert(recipeId).inserted {
                orderedIds.append(recipeId)
            }
        }

        return orderedIds
    }

    private func copyAndAddRecipe(
        _ recipe: Recipe,
        confirmingPublicMembershipRepair: Bool = false
    ) async {
        guard CurrentUserSession.shared.userId != nil else {
            AppLogger.general.error("Cannot copy recipe - no current user")
            return
        }

        do {
            if !confirmingPublicMembershipRepair {
                let repairPlan = try await publicMembershipRepairPlanForCopyingReferencedRecipe()
                if repairPlan.requiresRepair {
                    pendingPublicMembershipRepairPlan = repairPlan
                    pendingPublicMembershipConfirmationAction = .copyRecipe(recipe)
                    showingCopyConfirmation = nil
                    showingPublicMembershipRepairConfirmation = true
                    return
                }
            }

            isCopying = true
            defer { isCopying = false }

            // Fetch the recipe owner if not already cached
            var recipeOwner: User?
            if let ownerId = recipe.ownerId {
                if let cachedOwner = recipeOwnerCache[ownerId] {
                    recipeOwner = cachedOwner
                } else {
                    do {
                        recipeOwner = try await dependencies.userCloudService.fetchUser(byUserId: ownerId)
                        if let owner = recipeOwner {
                            recipeOwnerCache[ownerId] = owner
                        }
                    } catch {
                        AppLogger.general.warning("Failed to fetch recipe owner: \(error.localizedDescription)")
                        // Continue without owner name - will be nil
                    }
                }
            }

            let materializedRecipe = try await dependencies.recipeSaveService.materializeRecipeForOwnedCollectionMembership(
                recipe,
                minimumVisibility: collection.visibility,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipeOwner?.displayName
            )

            try await dependencies.collectionRepository.addRecipe(materializedRecipe.id, to: collection.id)

            // Update selected recipes to include the new copy
            selectedRecipeIds.insert(materializedRecipe.id)

            // Reload recipes to show the new copy
            await loadRecipes()

            AppLogger.general.info("✅ Copied and added recipe to collection: \(recipe.title)")
            showingCopyConfirmation = nil
        } catch {
            AppLogger.general.error("❌ Failed to copy and add recipe: \(error.localizedDescription)")
            showingCopyConfirmation = nil
        }
    }
}
