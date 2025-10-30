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
                        HStack(spacing: 4) {
                            Image(systemName: selectedVisibility.icon)
                                .font(.caption)
                            Text(selectedVisibility.displayName)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .disabled(isUpdatingVisibility)

                    // Add Recipes button
                    Button {
                        showingRecipeSelector = true
                    } label: {
                        Label("Add Recipes", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.cauldronOrange)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.cauldronOrange.opacity(0.15))
                    .controlSize(.small)
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

                    Button {
                        shareCollection()
                    } label: {
                        Label("Share Collection", systemImage: "square.and.arrow.up")
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
        .task {
            await loadRecipes()
        }
        .refreshable {
            await loadRecipes()
        }
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

            // Fetch all recipes (owned + referenced)
            var allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Add referenced recipes if available
            if CurrentUserSession.shared.isCloudSyncAvailable,
               let userId = CurrentUserSession.shared.userId {
                do {
                    let references = try await dependencies.cloudKitService.fetchRecipeReferences(forUserId: userId)
                    AppLogger.general.info("Fetched \(references.count) recipe references for collection display")

                    // Fetch full recipes for each reference
                    for reference in references {
                        do {
                            let recipe = try await dependencies.cloudKitService.fetchPublicRecipe(
                                recipeId: reference.originalRecipeId,
                                ownerId: reference.originalOwnerId
                            )

                            // Only add if not already in owned recipes (avoid duplicates)
                            if !allRecipes.contains(where: { $0.id == recipe.id }) {
                                allRecipes.append(recipe)
                            }
                        } catch {
                            AppLogger.general.warning("Failed to fetch referenced recipe \(reference.recipeTitle): \(error.localizedDescription)")
                        }
                    }
                } catch {
                    AppLogger.general.warning("Failed to fetch recipe references: \(error.localizedDescription)")
                }
            }

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

    private func shareCollection() {
        // TODO: Implement collection sharing
        AppLogger.general.info("Share collection: \(collection.name)")
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

    init(collection: Collection, dependencies: DependencyContainer, onDismiss: @escaping () -> Void) {
        self.collection = collection
        self.dependencies = dependencies
        self.onDismiss = onDismiss
        self._selectedRecipeIds = State(initialValue: Set(collection.recipeIds))
    }

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        } else {
            let lowercased = searchText.lowercased()
            return recipes.filter { recipe in
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
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                toggleRecipe(recipe.id)
                            } label: {
                                HStack(spacing: 12) {
                                    RecipeImageView(thumbnailImageURL: recipe.imageURL)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(recipe.title)
                                                .font(.body)
                                                .foregroundColor(.primary)
                                                .lineLimit(2)

                                            // Reference indicator
                                            if recipe.isReference {
                                                Image(systemName: "bookmark.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.0))
                                            }
                                        }

                                        if !recipe.tags.isEmpty {
                                            Text(recipe.tags.first!.name)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    if selectedRecipeIds.contains(recipe.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.cauldronOrange)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search recipes")
                }
            }
            .navigationTitle("Add Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                await loadRecipes()
            }
        }
    }

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load owned recipes from local storage
            var loadedRecipes = try await dependencies.recipeRepository.fetchAll()

            // Load recipe references if user is logged in and CloudKit is available
            if CurrentUserSession.shared.isCloudSyncAvailable,
               let userId = CurrentUserSession.shared.userId {
                do {
                    // Fetch recipe references from CloudKit
                    let references = try await dependencies.cloudKitService.fetchRecipeReferences(forUserId: userId)
                    AppLogger.general.info("Fetched \(references.count) recipe references from CloudKit")

                    // Fetch full recipes for each reference
                    for reference in references {
                        do {
                            let recipe = try await dependencies.cloudKitService.fetchPublicRecipe(
                                recipeId: reference.originalRecipeId,
                                ownerId: reference.originalOwnerId
                            )

                            // Only add if not already in owned recipes (avoid duplicates)
                            if !loadedRecipes.contains(where: { $0.id == recipe.id }) {
                                loadedRecipes.append(recipe)
                            }
                        } catch {
                            AppLogger.general.warning("Failed to fetch referenced recipe \(reference.recipeTitle): \(error.localizedDescription)")
                            // Continue with other references even if one fails
                        }
                    }

                    AppLogger.general.info("Total recipes including references: \(loadedRecipes.count)")
                } catch {
                    AppLogger.general.warning("Failed to fetch recipe references (continuing with owned recipes only): \(error.localizedDescription)")
                    // Don't fail completely - just show owned recipes
                }
            }

            recipes = loadedRecipes
            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for collection selector (owned + referenced)")
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
}

#Preview {
    NavigationStack {
        CollectionDetailView(
            collection: Collection.new(name: "Holiday Foods", userId: UUID()),
            dependencies: DependencyContainer.preview()
        )
    }
}
