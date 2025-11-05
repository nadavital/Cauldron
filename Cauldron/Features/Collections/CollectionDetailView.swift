//
//  CollectionDetailView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import os

struct CollectionDetailView: View {
    let initialCollection: Collection
    let dependencies: DependencyContainer

    @State private var collection: Collection
    @State private var recipes: [Recipe] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var showingEditSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showingRecipeSelector = false
    @State private var selectedVisibility: RecipeVisibility
    @State private var isUpdatingVisibility = false
    @State private var showingDeleteConfirmation = false
    @State private var showingConformanceSheet = false
    @Environment(\.dismiss) private var dismiss

    var nonConformingRecipes: [Recipe] {
        collection.nonConformingRecipes(from: recipes)
    }

    init(collection: Collection, dependencies: DependencyContainer) {
        self.initialCollection = collection
        self.dependencies = dependencies
        self._collection = State(initialValue: collection)
        self._selectedVisibility = State(initialValue: collection.visibility)
    }

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText) ||
            recipe.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        List {
            // Header with collection info
            Section {
                VStack(spacing: 16) {
                    // Icon
                    if let emoji = collection.emoji {
                        ZStack {
                            Circle()
                                .fill(collectionColor.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Text(emoji)
                                .font(.system(size: 50))
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(collectionColor.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "folder.fill")
                                .font(.system(size: 40))
                                .foregroundColor(collectionColor)
                        }
                    }

                    // Name and count
                    VStack(spacing: 4) {
                        Text(collection.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Action buttons - Horizontal layout
                    HStack(spacing: 12) {
                        // Visibility picker
                        Menu {
                            ForEach(RecipeVisibility.allCases, id: \.self) { visibility in
                                Button {
                                    Task {
                                        await updateVisibility(to: visibility)
                                    }
                                } label: {
                                    Label(visibility.displayName, systemImage: visibility.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selectedVisibility.icon)
                                    .font(.subheadline)
                                Text(selectedVisibility.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .disabled(isUpdatingVisibility)

                        // Add Recipes button
                        Button {
                            showingRecipeSelector = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.subheadline)
                                Text("Add Recipes")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.cauldronOrange)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.cauldronOrange.opacity(0.1))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Non-conforming recipes warning (only for shared collections)
                    if collection.isShared && !nonConformingRecipes.isEmpty {
                        nonConformingRecipesWarning
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Recipes
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if filteredRecipes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text(searchText.isEmpty ? "No recipes in this collection" : "No recipes found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if searchText.isEmpty {
                            Text("Add recipes from the recipe detail view")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, dependencies: dependencies)
                        } label: {
                            RecipeRowView(recipe: recipe)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await removeRecipe(recipe)
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Collection", systemImage: "pencil")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Collection", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CollectionFormView(collectionToEdit: collection)
                .environment(\.dependencies, dependencies)
        }
        .sheet(isPresented: $showingRecipeSelector) {
            CollectionRecipeSelectorSheet(
                collection: collection,
                dependencies: dependencies,
                onDismiss: {
                    // Reload the collection and recipes after adding
                    Task {
                        await loadRecipes()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteCollection()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete \"\(collection.name)\" and remove all recipes from it. The recipes themselves will not be deleted.")
        }
        .task {
            await loadRecipes()
        }
        .refreshable {
            await loadRecipes()
        }
        .sheet(isPresented: $showingConformanceSheet) {
            ConformanceFixSheet(
                collection: collection,
                nonConformingRecipes: nonConformingRecipes,
                dependencies: dependencies,
                onDismiss: {
                    Task {
                        await loadRecipes()
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Warning Banner

    private var nonConformingRecipesWarning: some View {
        Button {
            showingConformanceSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(nonConformingRecipes.count) recipe\(nonConformingRecipes.count == 1 ? "" : "s") won't be visible")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("These recipes need to be \(collection.minimumVisibilityDescription) to appear in this collection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // IMPORTANT: Refresh the collection object from the database first
            // This ensures we have the latest recipeIds array after any updates
            if let updatedCollection = try await dependencies.collectionRepository.fetch(id: collection.id) {
                collection = updatedCollection
                AppLogger.general.info("✅ Refreshed collection: \(collection.name) with \(collection.recipeCount) recipes")
            }

            // Fetch all owned recipes
            let allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Filter to only recipes in this collection
            recipes = allRecipes.filter { recipe in
                collection.recipeIds.contains(recipe.id)
            }

            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for collection: \(collection.name)")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }
    }

    private func removeRecipe(_ recipe: Recipe) async {
        do {
            try await dependencies.collectionRepository.removeRecipe(recipe.id, from: collection.id)
            await loadRecipes()  // Refresh list
            AppLogger.general.info("✅ Removed recipe from collection")
        } catch {
            AppLogger.general.error("❌ Failed to remove recipe: \(error.localizedDescription)")
            errorMessage = "Failed to remove recipe: \(error.localizedDescription)"
            showError = true
        }
    }

    private func updateVisibility(to newVisibility: RecipeVisibility) async {
        guard newVisibility != selectedVisibility else { return }

        isUpdatingVisibility = true
        defer { isUpdatingVisibility = false }

        do {
            let updated = collection.updated(visibility: newVisibility)
            try await dependencies.collectionRepository.update(updated)

            // Update local state
            collection = updated
            selectedVisibility = newVisibility

            AppLogger.general.info("✅ Updated collection visibility to \(newVisibility.displayName)")
        } catch {
            AppLogger.general.error("❌ Failed to update visibility: \(error.localizedDescription)")
            errorMessage = "Failed to update visibility: \(error.localizedDescription)"
            showError = true
        }
    }

    private func deleteCollection() async {
        do {
            try await dependencies.collectionRepository.delete(id: collection.id)
            AppLogger.general.info("✅ Deleted collection: \(collection.name)")

            // Dismiss the view after successful deletion
            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to delete collection: \(error.localizedDescription)")
            errorMessage = "Failed to delete collection: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - Helpers

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }

    private var visibilityIcon: String {
        switch collection.visibility {
        case .privateRecipe:
            return "lock.fill"
        case .friendsOnly:
            return "person.2.fill"
        case .publicRecipe:
            return "globe"
        }
    }

    private var visibilityText: String {
        switch collection.visibility {
        case .privateRecipe:
            return "Private"
        case .friendsOnly:
            return "Friends"
        case .publicRecipe:
            return "Public"
        }
    }
}

// MARK: - Collection Recipe Selector Sheet

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
                                        recipeRow(recipe: recipe, isSelectable: true)
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
                                        recipeRow(recipe: recipe, isSelectable: false)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Text("Saved from Others")
                            } footer: {
                                Text("To add these to your collection, you'll need to save a copy")
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
            .task {
                await loadRecipes()
            }
        }
    }

    @ViewBuilder
    private func recipeRow(recipe: Recipe, isSelectable: Bool) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(thumbnailImageURL: recipe.imageURL)
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
            recipes = try await dependencies.recipeRepository.fetchAll()
            AppLogger.general.info("✅ Loaded \(recipes.count) owned recipes for collection selector")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes for selector: \(error.localizedDescription)")
        }
    }

    private func saveChanges() async {
        do {
            // Determine which recipes to add and which to remove
            let currentRecipeIds = Set(collection.recipeIds)
            let recipesToAdd = selectedRecipeIds.subtracting(currentRecipeIds)
            let recipesToRemove = currentRecipeIds.subtracting(selectedRecipeIds)

            // Add new recipes
            for recipeId in recipesToAdd {
                try await dependencies.collectionRepository.addRecipe(recipeId, to: collection.id)
                AppLogger.general.info("✅ Added recipe to collection")
            }

            // Remove recipes
            for recipeId in recipesToRemove {
                try await dependencies.collectionRepository.removeRecipe(recipeId, from: collection.id)
                AppLogger.general.info("✅ Removed recipe from collection")
            }

            dismiss()
            onDismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save collection changes: \(error.localizedDescription)")
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

    private func copyAndAddRecipe(_ recipe: Recipe) async {
        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("Cannot copy recipe - no current user")
            return
        }

        isCopying = true
        defer { isCopying = false }

        do {
            // Create a copy of the recipe owned by the current user using withOwner()
            let copiedRecipe = recipe.withOwner(
                userId,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipe.ownerId != nil ? "Unknown" : nil  // TODO: Fetch actual creator name
            )

            // Save the copied recipe
            try await dependencies.recipeRepository.create(copiedRecipe)

            // Add the copied recipe to the collection
            try await dependencies.collectionRepository.addRecipe(copiedRecipe.id, to: collection.id)

            // Update selected recipes to include the new copy
            selectedRecipeIds.insert(copiedRecipe.id)

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

// MARK: - Conformance Fix Sheet

struct ConformanceFixSheet: View {
    let collection: Collection
    let nonConformingRecipes: [Recipe]
    let dependencies: DependencyContainer
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var isUpdating = false
    @State private var errorMessage: String?
    @State private var showError = false

    var targetVisibility: RecipeVisibility {
        collection.visibility
    }

    // Separate owned recipes from references
    var ownedRecipes: [Recipe] {
        nonConformingRecipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId == currentUserId
        }
    }

    var referencedRecipes: [Recipe] {
        nonConformingRecipes.filter { recipe in
            guard let currentUserId = CurrentUserSession.shared.userId,
                  let ownerId = recipe.ownerId else {
                return false
            }
            return ownerId != currentUserId
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header explanation
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Visibility Issue")
                                .font(.title3)
                                .fontWeight(.bold)

                            Text("This \(collection.visibility.displayName.lowercased()) collection contains recipes that won't be visible to others")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding()

                // Select All button (above the list)
                if !ownedRecipes.isEmpty {
                    HStack {
                        Button {
                            if selectedRecipeIds.count == ownedRecipes.count {
                                selectedRecipeIds.removeAll()
                            } else {
                                selectedRecipeIds = Set(ownedRecipes.map(\.id))
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selectedRecipeIds.count == ownedRecipes.count ? "checkmark.square.fill" : "square")
                                    .foregroundColor(.cauldronOrange)
                                Text(selectedRecipeIds.count == ownedRecipes.count ? "Deselect All" : "Select All")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        Spacer()

                        Text("\(selectedRecipeIds.count) selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // ScrollView with recipes
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Owned recipes section
                        if !ownedRecipes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("YOUR RECIPES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 8)

                                Text("Select recipes to update to \(targetVisibility.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)

                                ForEach(ownedRecipes) { recipe in
                                    Button {
                                        toggleRecipe(recipe.id)
                                    } label: {
                                        recipeRow(recipe: recipe, selectable: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Referenced recipes section (non-selectable)
                        if !referencedRecipes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("REFERENCED RECIPES")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 16)

                                Text("These are saved from others. You can't change their visibility.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)

                                ForEach(referencedRecipes) { recipe in
                                    recipeRow(recipe: recipe, selectable: false)
                                }
                            }
                        }
                    }
                }

                // Update button (bottom)
                VStack(spacing: 12) {
                    Button {
                        Task {
                            await updateSelectedRecipes()
                        }
                    } label: {
                        HStack {
                            if isUpdating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text(isUpdating ? "Updating..." : "Update \(selectedRecipeIds.count) Recipe\(selectedRecipeIds.count == 1 ? "" : "s")")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(selectedRecipeIds.isEmpty ? Color.gray : Color.cauldronOrange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(selectedRecipeIds.isEmpty || isUpdating)
                }
                .padding()
                .background(Color(uiColor: .systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 8, y: -4)
            }
            .navigationTitle("Recipe Visibility")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                    .disabled(isUpdating)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }

    @ViewBuilder
    private func recipeRow(recipe: Recipe, selectable: Bool) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(thumbnailImageURL: recipe.imageURL)
                .overlay(
                    Group {
                        if !selectable {
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

                HStack(spacing: 4) {
                    Image(systemName: recipe.visibility.icon)
                        .font(.caption)
                    Text(recipe.visibility.displayName)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }

            Spacer()

            if selectable {
                if selectedRecipeIds.contains(recipe.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.cauldronOrange)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func toggleRecipe(_ recipeId: UUID) {
        if selectedRecipeIds.contains(recipeId) {
            selectedRecipeIds.remove(recipeId)
        } else {
            selectedRecipeIds.insert(recipeId)
        }
    }

    private func updateSelectedRecipes() async {
        isUpdating = true
        defer { isUpdating = false }

        var successCount = 0
        var failureCount = 0

        for recipeId in selectedRecipeIds {
            guard let recipe = nonConformingRecipes.first(where: { $0.id == recipeId }) else {
                continue
            }

            do {
                // Create updated recipe with new visibility
                let updatedRecipe = Recipe(
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
                    visibility: targetVisibility,
                    ownerId: recipe.ownerId,
                    cloudRecordName: recipe.cloudRecordName,
                    createdAt: recipe.createdAt,
                    updatedAt: Date()
                )

                try await dependencies.recipeRepository.update(updatedRecipe)
                successCount += 1
                AppLogger.general.info("✅ Updated recipe visibility: \(recipe.title)")
            } catch {
                failureCount += 1
                AppLogger.general.error("❌ Failed to update recipe visibility: \(error.localizedDescription)")
            }
        }

        if failureCount > 0 {
            errorMessage = "Updated \(successCount) recipes, but \(failureCount) failed"
            showError = true
        } else {
            AppLogger.general.info("✅ Successfully updated \(successCount) recipe visibilities")
            dismiss()
            onDismiss()
        }
    }
}

#Preview {
    NavigationStack {
        CollectionDetailView(
            collection: Collection.new(name: "Holiday Foods", userId: UUID()),
            dependencies: DependencyContainer.preview()
        )
    }
}
