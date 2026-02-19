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
    @State private var activeSheet: ActiveSheet?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var recipeImages: [URL?] = []  // For recipe grid display
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    // External sharing
    @State private var showShareSheet = false
    @State private var shareLink: ShareableLink?
    @State private var isGeneratingShareLink = false

    enum ActiveSheet: Identifiable {
        case edit
        case addRecipes
        case conformance

        var id: Int {
            switch self {
            case .edit: return 1
            case .addRecipes: return 2
            case .conformance: return 3
            }
        }
    }

    var nonConformingRecipes: [Recipe] {
        collection.nonConformingRecipes(from: recipes)
    }

    /// Check if the current user owns this collection
    @MainActor
    var isOwned: Bool {
        guard let currentUserId = CurrentUserSession.shared.userId else {
            return false
        }
        return collection.userId == currentUserId
    }

    init(collection: Collection, dependencies: DependencyContainer) {
        self.initialCollection = collection
        self.dependencies = dependencies
        self._collection = State(initialValue: collection)
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

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    private var recipeLayoutToolbarMenu: some View {
        RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
            storedRecipeLayoutMode = mode.rawValue
        }
    }

    var body: some View {
        List {
            headerSection
            recipesSection
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipes")
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .onChange(of: activeSheet) { oldValue, newValue in
            // Refresh collection when any sheet is dismissed
            if oldValue != nil && newValue == nil {
                Task {
                    await loadRecipes()
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            Task {
                await loadRecipes()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let link = shareLink {
                ShareSheet(items: [link])
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !recipes.isEmpty {
                    recipeLayoutToolbarMenu
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                // Only allow sharing if collection is public
                if collection.visibility == .publicRecipe {
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
        }
    }

    // MARK: - Sheet Content

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .edit:
            CollectionFormView(collectionToEdit: collection)
                .environment(\.dependencies, dependencies)
        case .addRecipes:
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
        case .conformance:
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
            activeSheet = .conformance
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
            // For owned collections, refresh from local database
            if isOwned {
                // Refresh the collection object from the database first
                if let updatedCollection = try await dependencies.collectionRepository.fetch(id: collection.id) {
                    collection = updatedCollection
                    AppLogger.general.info("✅ Refreshed collection: \(collection.name) with \(collection.recipeCount) recipes")
                }

                // Fetch all owned recipes from local storage
                let allRecipes = try await dependencies.recipeRepository.fetchAll()

                // Filter to only recipes in this collection
                recipes = allRecipes.filter { recipe in
                    collection.recipeIds.contains(recipe.id)
                }
            } else {
                // For non-owned collections, fetch recipes from CloudKit in parallel
                AppLogger.general.info("📡 Loading recipes from CloudKit for non-owned collection: \(collection.name)")

                let fetchedRecipes = await withTaskGroup(of: Recipe?.self, returning: [Recipe].self) { group in
                    for recipeId in collection.recipeIds {
                        group.addTask {
                            do {
                                return try await dependencies.recipeCloudService.fetchPublicRecipe(id: recipeId)
                            } catch {
                                AppLogger.general.warning("Failed to fetch recipe \(recipeId) from CloudKit: \(error.localizedDescription)")
                                return nil
                            }
                        }
                    }

                    var results: [Recipe] = []
                    for await recipe in group {
                        if let recipe = recipe {
                            results.append(recipe)
                        }
                    }
                    return results
                }

                recipes = fetchedRecipes
                AppLogger.general.info("✅ Loaded \(recipes.count) of \(collection.recipeIds.count) recipes from CloudKit")
            }

            // Load up to 4 available recipe images for cover grid display.
            let imagePairs: [(UUID, URL)] = recipes.compactMap { recipe in
                guard let imageURL = recipe.imageURL else { return nil }
                return (recipe.id, imageURL)
            }
            let imageByRecipeId = Dictionary(uniqueKeysWithValues: imagePairs)
            recipeImages = Array(collection.recipeIds.compactMap { imageByRecipeId[$0] }.prefix(4).map(Optional.some))

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
        }
    }

    private func generateShareLink() async {
        isGeneratingShareLink = true
        defer { isGeneratingShareLink = false }

        do {
            let link = try await dependencies.externalShareService.shareCollection(
                collection,
                recipeIds: collection.recipeIds
            )
            shareLink = link
            showShareSheet = true
        } catch {
            AppLogger.general.error("Failed to generate collection share link: \(error.localizedDescription)")
            errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            showError = true
        }
    }

    // MARK: - View Components

    @ViewBuilder
    private var recipesSection: some View {
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

                    // Only show "add recipes" button for owner
                    if searchText.isEmpty && isOwned {
                        Button {
                            activeSheet = .addRecipes
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.subheadline.weight(.semibold))
                                Text("Add Recipes")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cauldronOrange)
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                if usesGridRecipeLayout {
                    recipesGridContent
                } else {
                    recipesCompactContent
                }
            }
        }
    }

    @ViewBuilder
    private var recipesCompactContent: some View {
        ForEach(filteredRecipes) { recipe in
            NavigationLink {
                RecipeDetailView(recipe: recipe, dependencies: dependencies)
            } label: {
                RecipeRowView(recipe: recipe, dependencies: dependencies)
            }
            // Only allow removal for owner
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if isOwned {
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

    private var recipesGridContent: some View {
        LazyVGrid(columns: recipeGridColumns, spacing: 12) {
            ForEach(filteredRecipes) { recipe in
                NavigationLink {
                    RecipeDetailView(recipe: recipe, dependencies: dependencies)
                } label: {
                    RecipeCardView(recipe: recipe, dependencies: dependencies)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if isOwned {
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
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var recipeGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 12)]
    }

    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                // Cover Image
                coverImageView
                    .frame(width: 120, height: 120)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(collectionColor.opacity(0.2), lineWidth: 1)
                    )

                // Name and count
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: collection.symbolName ?? "folder.fill")
                            .foregroundStyle(collectionColor)
                        Text(collection.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }

                    Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Action buttons (only for owner)
                if isOwned {
                    HStack(spacing: 12) {
                        editCollectionButton
                            .id("edit-button")
                        addRecipesButton
                            .id("add-button")
                    }
                    .padding(.horizontal, 16)
                }

                // Warning banner (only for owner who can fix it)
                if isOwned && collection.isShared && !nonConformingRecipes.isEmpty {
                    nonConformingRecipesWarning
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var editCollectionButton: some View {
        Button(action: {
            activeSheet = .edit
        }) {
            HStack(spacing: 6) {
                Image(systemName: "pencil")
                    .font(.subheadline)
                Text("Edit Collection")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var addRecipesButton: some View {
        Button(action: {
            activeSheet = .addRecipes
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(.subheadline)
                Text("Add Recipes")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.cauldronOrange)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color.cauldronOrange.opacity(0.1))
            .cornerRadius(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private var coverImageView: some View {
        recipeGridView
    }

    private var recipeGridView: some View {
        Group {
            let size: CGFloat = 60  // 120 / 2 for the 2x2 grid

            if collection.recipeCount == 0 || recipeImages.isEmpty || recipeImages.allSatisfy({ $0 == nil }) {
                // Show placeholder
                collectionColor
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 30))
                                .foregroundStyle(.white.opacity(0.7))
                            if collection.recipeCount > 0 {
                                Text("\(collection.recipeCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    )
            } else {
                // Show 2x2 grid of recipe images
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        recipeImageTile(at: 0, size: size)
                        recipeImageTile(at: 1, size: size)
                    }
                    HStack(spacing: 0) {
                        recipeImageTile(at: 2, size: size)
                        recipeImageTile(at: 3, size: size)
                    }
                }
            }
        }
    }

    private func recipeImageTile(at index: Int, size: CGFloat) -> some View {
        Group {
            if index < recipeImages.count, let imageURL = recipeImages[index] {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        placeholderTile(size: size)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipped()
                    case .failure:
                        placeholderTile(size: size)
                    @unknown default:
                        placeholderTile(size: size)
                    }
                }
            } else {
                placeholderTile(size: size)
            }
        }
    }

    private func placeholderTile(size: CGFloat) -> some View {
        Rectangle()
            .fill(collectionColor.opacity(0.3))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.3))
                    .foregroundColor(.white.opacity(0.5))
            )
    }

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
        case .publicRecipe:
            return "globe"
        }
    }

    private var visibilityText: String {
        switch collection.visibility {
        case .privateRecipe:
            return "Private"
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
    @State private var recipeOwnerCache: [UUID: User] = [:]  // Cache recipe owners by userId

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

            // Create a copy of the recipe owned by the current user using withOwner()
            let copiedRecipe = recipe.withOwner(
                userId,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipeOwner?.displayName
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
                                        recipeRow(recipe: recipe, selectable: true, dependencies: dependencies)
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
                                    recipeRow(recipe: recipe, selectable: false, dependencies: dependencies)
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
    private func recipeRow(recipe: Recipe, selectable: Bool, dependencies: DependencyContainer) -> some View {
        HStack(spacing: 12) {
            RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)
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
