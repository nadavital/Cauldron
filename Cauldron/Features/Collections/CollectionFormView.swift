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
    @State private var symbolName: String?
    @State private var color: String?
    @State private var visibility: RecipeVisibility
    @State private var selectedRecipeIds: Set<UUID>
    @State private var isSaving = false
    @State private var showingRecipeSelector = false
    @State private var showingDeleteConfirmation = false
    @State private var allRecipes: [Recipe] = []

    init(collectionToEdit: Collection? = nil) {
        self.collectionToEdit = collectionToEdit

        // Initialize state
        _name = State(initialValue: collectionToEdit?.name ?? "")
        _symbolName = State(initialValue: collectionToEdit?.symbolName)
        _color = State(initialValue: collectionToEdit?.color)
        _visibility = State(initialValue: collectionToEdit?.visibility ?? .publicRecipe)
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
                            ZStack {
                                Circle()
                                    .fill(selectedColor.opacity(0.15))
                                    .frame(width: 80, height: 80)

                                Image(systemName: selectedSymbolName)
                                    .font(.system(size: 40))
                                    .foregroundColor(selectedColor)
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

                    Picker("Symbol", selection: Binding(
                        get: { selectedSymbolName },
                        set: { symbolName = $0 }
                    )) {
                        ForEach(Self.availableSymbolNames, id: \.self) { symbol in
                            Label(symbolDisplayName(for: symbol), systemImage: symbol)
                                .tag(symbol)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Collections always use a recipe grid cover for consistency.")
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
                                if recipe.imageURL != nil {
                                    RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)
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
                    case .publicRecipe:
                        Text("Everyone can see and save this collection")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Sharing")
                }

                // Delete Collection Section (only when editing)
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Collection")
                            }
                        }
                    } header: {
                        Text("Delete Collection")
                    } footer: {
                        Text("This will permanently delete this collection and remove all recipes from it. The recipes themselves will not be deleted.")
                    }
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
                Text("This will permanently delete \"\(collectionToEdit?.name ?? "this collection")\" and remove all recipes from it. The recipes themselves will not be deleted.")
            }
        }
    }

    // MARK: - Actions

    private func loadRecipes() async {
        do {
            // Load owned recipes from local storage
            allRecipes = try await dependencies.recipeRepository.fetchAll()
            AppLogger.general.info("✅ Loaded \(allRecipes.count) owned recipes")
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
            let resolvedSymbolName = symbolName ?? defaultSymbolName
            let resolvedColor = color ?? Color.cauldronOrange.toHex() ?? "#FF9933"

            if let existingCollection = collectionToEdit {
                // Update existing collection
                let updated = existingCollection.updated(
                    name: trimmedName,
                    recipeIds: recipeIds,
                    visibility: visibility,
                    emoji: nil,
                    symbolName: resolvedSymbolName,
                    color: resolvedColor,
                    coverImageType: .recipeGrid,
                    coverImageURL: nil,
                    cloudCoverImageRecordName: nil,
                    coverImageModifiedAt: nil
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
                    emoji: nil,
                    symbolName: resolvedSymbolName,
                    color: resolvedColor,
                    coverImageType: .recipeGrid,
                    coverImageURL: nil,
                    cloudCoverImageRecordName: nil,
                    coverImageModifiedAt: nil
                )
                try await dependencies.collectionRepository.create(newCollection)
                AppLogger.general.info("✅ Created collection: \(trimmedName)")
            }

            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to save collection: \(error.localizedDescription)")
        }
    }

    private func deleteCollection() async {
        guard let collection = collectionToEdit else { return }

        do {
            // Delete from repository
            try await dependencies.collectionRepository.delete(id: collection.id)

            AppLogger.general.info("✅ Deleted collection: \(collection.name)")
            dismiss()
        } catch {
            AppLogger.general.error("❌ Failed to delete collection: \(error.localizedDescription)")
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

    private static let defaultSymbolName = "folder.fill"
    private static let availableSymbolNames = [
        "folder.fill",
        "fork.knife",
        "carrot.fill",
        "birthday.cake.fill",
        "leaf.fill",
        "flame.fill",
        "clock.fill",
        "heart.fill",
        "takeoutbag.and.cup.and.straw.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "party.popper.fill"
    ]

    private var defaultSymbolName: String { Self.defaultSymbolName }
    private var selectedSymbolName: String { symbolName ?? defaultSymbolName }

    private func symbolDisplayName(for symbol: String) -> String {
        switch symbol {
        case "folder.fill": return "Folder"
        case "fork.knife": return "Recipes"
        case "carrot.fill": return "Healthy"
        case "birthday.cake.fill": return "Desserts"
        case "leaf.fill": return "Vegetarian"
        case "flame.fill": return "Spicy"
        case "clock.fill": return "Quick"
        case "heart.fill": return "Favorites"
        case "takeoutbag.and.cup.and.straw.fill": return "Takeout"
        case "sun.max.fill": return "Breakfast"
        case "moon.stars.fill": return "Dinner"
        case "party.popper.fill": return "Celebration"
        default: return "Collection"
        }
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
                                    RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)

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
            recipes = try await dependencies.recipeRepository.fetchAll()
            AppLogger.general.info("✅ Loaded \(recipes.count) owned recipes for selector")
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
