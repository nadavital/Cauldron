//
//  CollectionFormView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import UIKit
import os

struct CollectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    // Edit mode
    let collectionToEdit: Collection?

    // Form state
    @State private var name: String
    @State private var description: String
    @State private var symbolName: String?
    @State private var color: String?
    @State private var visibility: RecipeVisibility
    @State private var selectedRecipeIds: Set<UUID>
    @State private var isSaving = false
    @State private var showingRecipeSelector = false
    @State private var showingDeleteConfirmation = false
    @State private var showingPublishRecipesConfirmation = false
    @State private var showingImageSourceDialog = false
    @State private var showingImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedCoverImage: UIImage?
    @State private var existingCoverImage: UIImage?
    @State private var shouldRemoveCustomCover = false
    @State private var publicMembershipRepairPlan = PublicCollectionMembershipRepairPlan(
        privateOwnedRecipeCount: 0,
        referencedRecipeCount: 0
    )
    @State private var allRecipes: [Recipe] = []
    @FocusState private var isNameFieldFocused: Bool

    init(collectionToEdit: Collection? = nil) {
        self.collectionToEdit = collectionToEdit

        // Initialize state
        _name = State(initialValue: collectionToEdit?.name ?? "")
        _description = State(initialValue: collectionToEdit?.description ?? "")
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

    private var publishRecipesConfirmationMessage: String {
        var actions: [String] = []

        if publicMembershipRepairPlan.privateOwnedRecipeCount > 0 {
            let count = publicMembershipRepairPlan.privateOwnedRecipeCount
            let recipeText = count == 1 ? "recipe" : "recipes"
            actions.append("make \(count) private \(recipeText) public")
        }

        if publicMembershipRepairPlan.referencedRecipeCount > 0 {
            let count = publicMembershipRepairPlan.referencedRecipeCount
            let recipeText = count == 1 ? "referenced recipe" : "referenced recipes"
            actions.append("save \(count) \(recipeText) as your own public copies")
        }

        guard !actions.isEmpty else {
            return "Making this collection public will make its recipes available to people who can see the collection."
        }

        return "Making this collection public will \(actions.joined(separator: " and ")) so everyone sees the same recipes."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        collectionImagePicker

                        TextField("Collection Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .submitLabel(.done)
                            .focused($isNameFieldFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.appSurface)
                            )

                        symbolSelectionRow
                        colorSelectionRow
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                } header: {
                    Text("Collection")
                }

                Section {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                        .submitLabel(.return)
                } header: {
                    Text("Description")
                } footer: {
                    Text("Optional. Use this for what belongs in the collection, not as a recipe count.")
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
                                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                                        .fill(Color.appSurface)
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
                        Text("Everyone can see this collection. Included recipes will be public too.")
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
            .fullScreenCover(isPresented: $showingImagePicker) {
                ImagePicker(
                    image: $selectedCoverImage,
                    sourceType: imagePickerSourceType,
                    allowsEditing: true
                )
                .ignoresSafeArea()
            }
            .task {
                await loadRecipes()
                await loadExistingCoverImage()
            }
            .onChange(of: selectedCoverImage != nil) {
                if selectedCoverImage != nil {
                    shouldRemoveCustomCover = false
                }
            }
            .confirmationDialog(
                "Collection Image",
                isPresented: $showingImageSourceDialog,
                titleVisibility: .visible
            ) {
                Button("Choose Photo", systemImage: "photo.on.rectangle") {
                    imagePickerSourceType = .photoLibrary
                    showingImagePicker = true
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo", systemImage: "camera") {
                        imagePickerSourceType = .camera
                        showingImagePicker = true
                    }
                }

                if selectedCoverImage != nil || existingCoverImage != nil || collectionToEdit?.coverImageType == .customImage {
                    Button("Remove Image", systemImage: "trash", role: .destructive) {
                        selectedCoverImage = nil
                        existingCoverImage = nil
                        shouldRemoveCustomCover = true
                    }
                }

                Button("Cancel", role: .cancel) {}
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
            .alert(
                "Make Collection Recipes Public?",
                isPresented: $showingPublishRecipesConfirmation
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Continue") {
                    Task {
                        await saveCollection(confirmingRecipePublish: true)
                    }
                }
            } message: {
                Text(publishRecipesConfirmationMessage)
            }
        }
    }

    private var collectionImagePicker: some View {
        Button {
            showingImageSourceDialog = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let coverImage = selectedCoverImage ?? existingCoverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                    } else {
                        LinearGradient(
                            colors: [
                                selectedColor.opacity(0.26),
                                selectedColor.opacity(0.10),
                                Color.appSurface
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 28, weight: .semibold))
                                Text("Add Collection Image")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(selectedColor)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 148)
                .clipShape(.rect(cornerRadius: 16))

                Image(systemName: "pencil.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selectedColor)
                    .background(Circle().fill(Color.appSurface))
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedCoverImage == nil && existingCoverImage == nil ? "Add collection image" : "Change collection image")
    }

    private var symbolSelectionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Self.availableSymbolNames, id: \.self) { symbol in
                    Button {
                        symbolName = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(selectedSymbolName == symbol ? .white : selectedColor)
                            .frame(width: 34, height: 34)
                            .background(
                                Circle()
                                    .fill(selectedSymbolName == symbol ? selectedColor : selectedColor.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbolDisplayName(for: symbol))
                    .accessibilityAddTraits(selectedSymbolName == symbol ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var colorSelectionRow: some View {
        HStack(spacing: 12) {
            ForEach(Self.availableColorHexes, id: \.self) { colorHex in
                Button {
                    color = colorHex
                } label: {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .cauldronOrange)
                        .frame(width: 26, height: 26)
                        .overlay {
                            if resolvedColorHex == colorHex {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collection color")
                .accessibilityValue(colorHex)
                .accessibilityAddTraits(resolvedColorHex == colorHex ? .isSelected : [])
            }

            ColorPicker(
                "",
                selection: Binding(
                    get: { selectedColor },
                    set: { color = $0.toHex() }
                )
            )
            .labelsHidden()
            .frame(width: 30, height: 30)
        }
    }

    // MARK: - Actions

    private func loadRecipes() async {
        do {
            allRecipes = try await loadLibraryRecipesIncludingSavedReferences(dependencies: dependencies)
            AppLogger.general.info("✅ Loaded \(allRecipes.count) owned recipes")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadExistingCoverImage() async {
        guard let collectionToEdit,
              collectionToEdit.coverImageType == .customImage,
              !shouldRemoveCustomCover,
              selectedCoverImage == nil else {
            return
        }

        existingCoverImage = await dependencies.entityImageLoader.loadCollectionCoverImage(
            for: collectionToEdit,
            dependencies: dependencies
        )
    }

    private func saveCollection(confirmingRecipePublish: Bool = false) async {
        isSaving = true
        defer { isSaving = false }

        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("No user ID - cannot save collection")
            return
        }

        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
            var recipeIds = orderedSelectedRecipeIds
            let resolvedSymbolName = symbolName ?? defaultSymbolName
            let resolvedColor = color ?? Color.cauldronOrange.toHex() ?? "#FF9933"
            let collectionId = collectionToEdit?.id ?? UUID()
            let cover = try await resolveCoverImageState(collectionId: collectionId)
            let recipesById = RecipeDeduplication.byIdPreferringBest(allRecipes)

            if !confirmingRecipePublish {
                let repairPlan = try await dependencies.publicCollectionMembershipResolver.repairPlan(
                    recipeIds: recipeIds,
                    ownerId: userId,
                    visibility: visibility
                )
                let referencedRecipeCount = visibility == .publicRecipe
                    ? max(
                        repairPlan.referencedRecipeCount,
                        externalRecipeIdsNeedingMaterialization(
                            recipeIds: recipeIds,
                            recipesById: recipesById,
                            currentUserId: userId
                        ).count
                    )
                    : repairPlan.referencedRecipeCount
                let combinedRepairPlan = PublicCollectionMembershipRepairPlan(
                    privateOwnedRecipeCount: repairPlan.privateOwnedRecipeCount,
                    referencedRecipeCount: referencedRecipeCount
                )
                if combinedRepairPlan.requiresRepair {
                    publicMembershipRepairPlan = combinedRepairPlan
                    showingPublishRecipesConfirmation = true
                    return
                }
            }

            recipeIds = try await materializeExternalRecipeIdsForOwnedCollection(
                recipeIds,
                recipesById: recipesById,
                currentUserId: userId,
                collectionVisibility: visibility,
                dependencies: dependencies
            )

            let membershipResolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
                recipeIds: recipeIds,
                ownerId: userId,
                visibility: visibility
            )
            recipeIds = membershipResolution.recipeIds

            if let existingCollection = collectionToEdit {
                // Update existing collection
                let updated = Collection(
                    id: existingCollection.id,
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    userId: existingCollection.userId,
                    recipeIds: recipeIds,
                    visibility: visibility,
                    emoji: nil,
                    symbolName: resolvedSymbolName,
                    color: resolvedColor,
                    coverImageType: cover.coverImageType,
                    coverImageURL: cover.coverImageURL,
                    cloudCoverImageRecordName: cover.cloudCoverImageRecordName,
                    coverImageModifiedAt: cover.coverImageModifiedAt,
                    cloudRecordName: existingCollection.cloudRecordName,
                    originalCollectionId: existingCollection.originalCollectionId,
                    originalCollectionOwnerId: existingCollection.originalCollectionOwnerId,
                    originalCollectionName: existingCollection.originalCollectionName,
                    savedAt: existingCollection.savedAt,
                    sourceCollectionUpdatedAt: existingCollection.sourceCollectionUpdatedAt,
                    followsSourceUpdates: existingCollection.followsSourceUpdates,
                    createdAt: existingCollection.createdAt,
                    updatedAt: Date()
                )
                try await dependencies.collectionRepository.update(updated)
                AppLogger.general.info("✅ Updated collection: \(trimmedName)")
            } else {
                // Create new collection
                let newCollection = Collection(
                    id: collectionId,
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    userId: userId,
                    recipeIds: recipeIds,
                    visibility: visibility,
                    emoji: nil,
                    symbolName: resolvedSymbolName,
                    color: resolvedColor,
                    coverImageType: cover.coverImageType,
                    coverImageURL: cover.coverImageURL,
                    cloudCoverImageRecordName: cover.cloudCoverImageRecordName,
                    coverImageModifiedAt: cover.coverImageModifiedAt
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

    private struct CoverImageState {
        let coverImageType: CoverImageType
        let coverImageURL: URL?
        let cloudCoverImageRecordName: String?
        let coverImageModifiedAt: Date?
    }

    private func resolveCoverImageState(collectionId: UUID) async throws -> CoverImageState {
        if shouldRemoveCustomCover {
            return CoverImageState(
                coverImageType: .recipeGrid,
                coverImageURL: nil,
                cloudCoverImageRecordName: nil,
                coverImageModifiedAt: nil
            )
        }

        if let selectedCoverImage {
            let imageURL = try await dependencies.collectionImageManager.saveImage(
                selectedCoverImage,
                collectionId: collectionId
            )
            return CoverImageState(
                coverImageType: .customImage,
                coverImageURL: imageURL,
                cloudCoverImageRecordName: nil,
                coverImageModifiedAt: Date()
            )
        }

        if let collectionToEdit {
            return CoverImageState(
                coverImageType: collectionToEdit.coverImageType,
                coverImageURL: collectionToEdit.coverImageURL,
                cloudCoverImageRecordName: collectionToEdit.cloudCoverImageRecordName,
                coverImageModifiedAt: collectionToEdit.coverImageModifiedAt
            )
        }

        return CoverImageState(
            coverImageType: .recipeGrid,
            coverImageURL: nil,
            cloudCoverImageRecordName: nil,
            coverImageModifiedAt: nil
        )
    }

    private var selectedRecipes: [Recipe] {
        allRecipes.filter { selectedRecipeIds.contains($0.id) }
    }

    private var orderedSelectedRecipeIds: [UUID] {
        var orderedIds: [UUID] = []
        var seenIds = Set<UUID>()

        if let collectionToEdit {
            for recipeId in collectionToEdit.recipeIds where selectedRecipeIds.contains(recipeId) {
                if seenIds.insert(recipeId).inserted {
                    orderedIds.append(recipeId)
                }
            }
        }

        for recipeId in allRecipes.map(\.id) where selectedRecipeIds.contains(recipeId) {
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

    private var selectedColor: Color {
        if let colorHex = color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }

    private static let defaultSymbolName = "folder.fill"
    private static let defaultColorHex = "#FF9933"
    private static let availableColorHexes = [
        "#FF9933",
        "#FF6B6B",
        "#4ECDC4",
        "#45B7D1",
        "#96CEB4",
        "#A78BFA",
        "#F7B731",
        "#5F27CD"
    ]
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
    private var resolvedColorHex: String { color ?? Self.defaultColorHex }

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
            recipes = try await loadLibraryRecipesIncludingSavedReferences(dependencies: dependencies)
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

private func loadLibraryRecipesIncludingSavedReferences(
    dependencies: DependencyContainer
) async throws -> [Recipe] {
    var recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
        try await dependencies.recipeRepository.fetchLibraryRecipes(ownerId: CurrentUserSession.shared.userId),
        currentUserId: CurrentUserSession.shared.userId
    )

    guard let currentUserId = CurrentUserSession.shared.userId else {
        return recipes
    }

    let references = try await dependencies.savedReferenceRepository.recipeReferences(for: currentUserId)
    let representedSourceIds = Set(recipes.map(\.relatedGraphReferenceID))
    let missingSourceIds = references.compactMap { reference -> UUID? in
        guard reference.materializedRecipeId == nil,
              !representedSourceIds.contains(reference.sourceRecipeId) else {
            return nil
        }
        return reference.sourceRecipeId
    }

    if !missingSourceIds.isEmpty {
        let fetchedRecipes = try await dependencies.recipeDiscoveryCache.fetchPublicRecipes(ids: missingSourceIds)
        recipes += references.compactMap { reference in
            guard reference.materializedRecipeId == nil else { return nil }
            return fetchedRecipes[reference.sourceRecipeId]
        }
    }

    return recipes
}

private func externalRecipeIdsNeedingMaterialization(
    recipeIds: [UUID],
    recipesById: [UUID: Recipe],
    currentUserId: UUID
) -> [UUID] {
    recipeIds.filter { recipeId in
        guard let recipe = recipesById[recipeId] else {
            return false
        }
        return recipe.isPreview || recipe.ownerId != currentUserId
    }
}

private func materializeExternalRecipeIdsForOwnedCollection(
    _ recipeIds: [UUID],
    recipesById: [UUID: Recipe],
    currentUserId: UUID,
    collectionVisibility: RecipeVisibility,
    dependencies: DependencyContainer
) async throws -> [UUID] {
    var resolvedRecipeIds: [UUID] = []
    var seenRecipeIds = Set<UUID>()

    for recipeId in recipeIds {
        let resolvedRecipeId: UUID
        if let recipe = recipesById[recipeId],
           recipe.isPreview || recipe.ownerId != currentUserId {
            let materializedRecipe = try await dependencies.recipeSaveService.materializeRecipeForOwnedCollectionMembership(
                recipe,
                minimumVisibility: collectionVisibility,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipe.originalCreatorName
            )
            resolvedRecipeId = materializedRecipe.id
        } else {
            resolvedRecipeId = recipeId
        }

        if seenRecipeIds.insert(resolvedRecipeId).inserted {
            resolvedRecipeIds.append(resolvedRecipeId)
        }
    }

    return resolvedRecipeIds
}

#Preview {
    CollectionFormView()
        .dependencies(DependencyContainer.preview())
}
