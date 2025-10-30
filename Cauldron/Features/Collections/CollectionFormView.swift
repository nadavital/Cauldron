//
//  CollectionFormView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import os

struct CollectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    // Edit mode
    let collectionToEdit: Collection?

    // Form state
    @State private var name: String
    @State private var emoji: String?
    @State private var color: String?
    @State private var visibility: RecipeVisibility
    @State private var selectedRecipeIds: Set<UUID>
    @State private var showingEmojiPicker = false
    @State private var isSaving = false
    @State private var showingRecipeSelector = false
    @State private var allRecipes: [Recipe] = []

    init(collectionToEdit: Collection? = nil) {
        self.collectionToEdit = collectionToEdit

        // Initialize state
        _name = State(initialValue: collectionToEdit?.name ?? "")
        _emoji = State(initialValue: collectionToEdit?.emoji)
        _color = State(initialValue: collectionToEdit?.color)
        _visibility = State(initialValue: collectionToEdit?.visibility ?? .privateRecipe)
        _selectedRecipeIds = State(initialValue: Set(collectionToEdit?.recipeIds ?? []))
    }

    var isEditing: Bool {
        collectionToEdit != nil
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // Preview Section (moved to top)
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            if let emoji = emoji {
                                ZStack {
                                    Circle()
                                        .fill(selectedColor.opacity(0.15))
                                        .frame(width: 80, height: 80)

                                    Text(emoji)
                                        .font(.system(size: 50))
                                }
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(selectedColor.opacity(0.15))
                                        .frame(width: 80, height: 80)

                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(selectedColor)
                                }
                            }

                            Text(name.isEmpty ? "Collection Name" : name)
                                .font(.headline)
                                .foregroundColor(name.isEmpty ? .secondary : .primary)

                            if !selectedRecipeIds.isEmpty {
                                Text("\(selectedRecipeIds.count) recipe\(selectedRecipeIds.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        Spacer()
                    }
                } header: {
                    Text("Preview")
                }

                // Basic Info Section
                Section {
                    TextField("Collection Name", text: $name)
                        .font(.body)

                    // Emoji picker
                    HStack {
                        Text("Icon")
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            showingEmojiPicker = true
                        } label: {
                            if let emoji = emoji {
                                Text(emoji)
                                    .font(.title2)
                            } else {
                                Text("Add Emoji")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Color picker
                    HStack {
                        Text("Color")
                            .foregroundColor(.primary)

                        Spacer()

                        ColorPicker("", selection: Binding(
                            get: {
                                if let colorHex = color {
                                    return Color(hex: colorHex) ?? .cauldronOrange
                                }
                                return .cauldronOrange
                            },
                            set: { newColor in
                                color = newColor.toHex()
                            }
                        ))
                        .labelsHidden()
                    }
                } header: {
                    Text("Details")
                }

                // Recipes Section
                Section {
                    Button {
                        showingRecipeSelector = true
                    } label: {
                        HStack {
                            Label("Add Recipes", systemImage: "plus.circle.fill")
                                .foregroundColor(.cauldronOrange)
                            Spacer()
                            if !selectedRecipeIds.isEmpty {
                                Text("\(selectedRecipeIds.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if !selectedRecipeIds.isEmpty {
                        ForEach(selectedRecipes) { recipe in
                            HStack {
                                if let imageURL = recipe.imageURL {
                                    RecipeImageView(thumbnailImageURL: imageURL)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.secondary)
                                        )
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.title)
                                        .font(.body)
                                        .lineLimit(2)

                                    if !recipe.tags.isEmpty {
                                        Text(recipe.tags.first!.name)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Button {
                                    selectedRecipeIds.remove(recipe.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    Text("Recipes")
                } footer: {
                    if selectedRecipeIds.isEmpty {
                        Text("Add recipes to your collection")
                    }
                }

                // Visibility Section
                Section {
                    Picker("Visibility", selection: $visibility) {
                        Label("Private", systemImage: "lock.fill")
                            .tag(RecipeVisibility.privateRecipe)

                        Label("Friends", systemImage: "person.2.fill")
                            .tag(RecipeVisibility.friendsOnly)

                        Label("Public", systemImage: "globe")
                            .tag(RecipeVisibility.publicRecipe)
                    }
                    .pickerStyle(.menu)

                    // Visibility explanation
                    switch visibility {
                    case .privateRecipe:
                        Text("Only you can see this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .friendsOnly:
                        Text("Your friends can see and save this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    case .publicRecipe:
                        Text("Everyone can see and save this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Sharing")
                }
            }
            .navigationTitle(isEditing ? "Edit Collection" : "New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create", systemImage: "checkmark") {
                        Task {
                            await saveCollection()
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $showingEmojiPicker) {
                EmojiPickerView(selectedEmoji: $emoji)
            }
            .sheet(isPresented: $showingRecipeSelector) {
                RecipeSelectorSheet(
                    selectedRecipeIds: $selectedRecipeIds,
                    allRecipes: allRecipes,
                    dependencies: dependencies
                )
            }
            .task {
                await loadRecipes()
            }
        }
    }

    // MARK: - Actions

    private func loadRecipes() async {
        do {
            // Load owned recipes from local storage
            var recipes = try await dependencies.recipeRepository.fetchAll()

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
                            if !recipes.contains(where: { $0.id == recipe.id }) {
                                recipes.append(recipe)
                            }
                        } catch {
                            AppLogger.general.warning("Failed to fetch referenced recipe \(reference.recipeTitle): \(error.localizedDescription)")
                            // Continue with other references even if one fails
                        }
                    }

                    AppLogger.general.info("Total recipes including references: \(recipes.count)")
                } catch {
                    AppLogger.general.warning("Failed to fetch recipe references (continuing with owned recipes only): \(error.localizedDescription)")
                    // Don't fail completely - just show owned recipes
                }
            }

            allRecipes = recipes
            AppLogger.general.info("✅ Loaded \(allRecipes.count) recipes (owned + referenced)")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
        }
    }

    private func saveCollection() async {
        isSaving = true
        defer { isSaving = false }

        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("No user ID - cannot save collection")
            return
        }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let recipeIds = Array(selectedRecipeIds)

            if let existingCollection = collectionToEdit {
                // Update existing collection
                let updated = existingCollection.updated(
                    name: trimmedName,
                    recipeIds: recipeIds,
                    visibility: visibility,
                    emoji: emoji,
                    color: color
                )
                try await dependencies.collectionRepository.update(updated)
                AppLogger.general.info("✅ Updated collection: \(trimmedName)")
            } else {
                // Create new collection
                let newCollection = Collection(
                    name: trimmedName,
                    userId: userId,
                    recipeIds: recipeIds,
                    visibility: visibility,
                    emoji: emoji,
                    color: color
                )
                try await dependencies.collectionRepository.create(newCollection)
                AppLogger.general.info("✅ Created collection: \(trimmedName)")
            }

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save collection: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private var selectedRecipes: [Recipe] {
        allRecipes.filter { selectedRecipeIds.contains($0.id) }
    }

    private var selectedColor: Color {
        if let colorHex = color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

// MARK: - Recipe Selector Sheet

struct RecipeSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRecipeIds: Set<UUID>
    let allRecipes: [Recipe]
    let dependencies: DependencyContainer

    @State private var searchText = ""
    @State private var recipes: [Recipe] = []
    @State private var isLoading = true

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
                                        .overlay(
                                            Group {
                                                if recipe.isReference {
                                                    // Reference badge in top-left corner
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
            .navigationTitle("Select Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
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
            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for selector (owned + referenced)")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes for selector: \(error.localizedDescription)")
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
    CollectionFormView()
        .dependencies(DependencyContainer.preview())
}
