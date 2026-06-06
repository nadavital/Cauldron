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
    @State private var recipeImageSources: [CollectionRecipeImageSource] = []
    @State private var visibleRecipes: [Recipe] = []
    @State private var showingPublicMembershipRepairConfirmation = false
    @State private var hasPromptedForPublicMembershipRepair = false
    @State private var isFriendWithOwner = false
    @State private var collectionOwner: User?
    @State private var isSavingCollection = false
    @State private var savedCollection: Collection?
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

    private var nonConformingRecipes: [Recipe] {
        collection.nonConformingRecipes(from: recipes)
    }

    private var ownedPrivateRecipesNeedingPublicRepair: [Recipe] {
        guard collection.visibility == .publicRecipe,
              isOwned,
              let currentUserId = CurrentUserSession.shared.userId else {
            return []
        }

        return nonConformingRecipes.filter { $0.ownerId == currentUserId }
    }

    private var referencedRecipesNeedingPublicRepair: [Recipe] {
        guard collection.visibility == .publicRecipe,
              isOwned,
              let currentUserId = CurrentUserSession.shared.userId else {
            return []
        }

        return recipes.filter { recipe in
            recipe.isPreview || recipe.ownerId != currentUserId
        }
    }

    private var publicMembershipRepairPlan: PublicCollectionMembershipRepairPlan {
        PublicCollectionMembershipRepairPlan(
            privateOwnedRecipeCount: ownedPrivateRecipesNeedingPublicRepair.count,
            referencedRecipeCount: referencedRecipesNeedingPublicRepair.count
        )
    }

    private var publicMembershipRepairConfirmationMessage: String {
        publicMembershipRepairPlan.confirmationMessage
    }

    /// Check if the current user owns this collection
    @MainActor
    var isOwned: Bool {
        guard let currentUserId = CurrentUserSession.shared.userId else {
            return false
        }
        return collection.userId == currentUserId
    }

    private var canSaveCollection: Bool {
        CurrentUserSession.shared.userId != nil && !isOwned
    }

    init(collection: Collection, dependencies: DependencyContainer) {
        self.initialCollection = collection
        self.dependencies = dependencies
        self._collection = State(initialValue: collection)
    }

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    private var displayedRecipeCount: Int {
        if isLoading || shouldShowUnavailableRecipesEmptyState {
            return collection.recipeCount
        }
        return visibleRecipes.count
    }

    private var hasDescription: Bool {
        guard let description = collection.description else {
            return false
        }
        return !description.isEmpty
    }

    private var shouldShowUnavailableRecipesEmptyState: Bool {
        !isLoading && collection.recipeCount > 0 && visibleRecipes.isEmpty
    }

    private var recipeLayoutToolbarMenu: some View {
        RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
            storedRecipeLayoutMode = mode.rawValue
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CollectionCoverView(
                    collection: collection,
                    recipes: recipes,
                    recipeImageSources: recipeImageSources,
                    dependencies: dependencies
                )

                VStack(alignment: .leading, spacing: 22) {
                    headerSection

                    if isOwned && collection.isShared && !nonConformingRecipes.isEmpty {
                        nonConformingRecipesWarning
                    }

                    recipesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 100)
            }
        }
        .warmCanvas()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipes")
        .onChange(of: searchText) { _, _ in
            updateVisibleRecipes()
        }
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
        .alert(
            "Repair Collection Sharing?",
            isPresented: $showingPublicMembershipRepairConfirmation
        ) {
            Button("Not Now", role: .cancel) {}
            Button("Repair") {
                Task {
                    await repairPublicCollectionMemberships()
                }
            }
        } message: {
            Text(publicMembershipRepairConfirmationMessage)
        }
        .task {
            await loadCollectionOwner()
            await loadRecipes()
            await loadExistingSavedCollection()
        }
        .refreshable {
            await loadCollectionOwner(forceRefresh: true)
            await loadRecipes(forceRefresh: true)
            await loadExistingSavedCollection()
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
                if isOwned && collection.visibility == .publicRecipe {
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
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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
        .buttonStyle(PressableScaleStyle())
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func loadRecipes(forceRefresh: Bool = false) async {
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

                let fetchedRecipes = try await dependencies.recipeRepository.fetch(ids: collection.recipeIds)
                let recipesById = fetchedRecipes.reduce(into: [UUID: Recipe]()) { partialResult, recipe in
                    partialResult[recipe.id] = recipe
                }
                recipes = collection.recipeIds.compactMap { recipesById[$0] }
            } else {
                AppLogger.general.info("📡 Loading recipes from CloudKit for non-owned collection: \(collection.name)")
                await refreshNonOwnedCollection(forceRefresh: forceRefresh)
                await checkFriendshipStatus(forceRefresh: forceRefresh)
                let result = await SharedCollectionLoader(dependencies: dependencies).loadRecipes(
                    from: collection,
                    viewerId: CurrentUserSession.shared.userId,
                    isFriend: isFriendWithOwner,
                    forceRefresh: forceRefresh
                )
                recipes = result.visibleRecipes
                AppLogger.general.info("✅ Loaded \(recipes.count) of \(collection.recipeIds.count) recipes for non-owned collection")
            }

            // Load available recipe images for collection artwork and detail paging.
            let imagePairs: [(UUID, URL)] = recipes.compactMap { recipe in
                guard let imageURL = recipe.imageURL else { return nil }
                return (recipe.id, imageURL)
            }
            let imageByRecipeId = imagePairs.reduce(into: [UUID: URL]()) { partialResult, pair in
                partialResult[pair.0] = pair.1
            }
            recipeImages = Array(collection.recipeIds.compactMap { imageByRecipeId[$0] }.prefix(4).map(Optional.some))
            let recipesById = RecipeDeduplication.byIdPreferringBest(recipes)
            recipeImageSources = collection.recipeIds.prefix(10).map { recipeId in
                let recipe = recipesById[recipeId]
                return CollectionRecipeImageSource(
                    recipeId: recipeId,
                    imageURL: recipe?.imageURL,
                    ownerId: recipe?.ownerId,
                    hasCloudImage: recipe?.cloudImageRecordName != nil
                )
            }
            updateVisibleRecipes()
            promptForPublicMembershipRepairIfNeeded()

            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for collection: \(collection.name)")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }
    }

    private func refreshNonOwnedCollection(forceRefresh: Bool = false) async {
        if RuntimeEnvironment.isSimulatorQAMode {
            do {
                if let updatedCollection = try await dependencies.collectionRepository.fetch(id: collection.id) {
                    collection = updatedCollection
                }
            } catch {
                AppLogger.general.warning("Failed to refresh simulator QA collection: \(error.localizedDescription)")
            }
            return
        }

        guard CurrentUserSession.shared.isCloudSyncAvailable else {
            return
        }

        do {
            let ownerCollections = try await dependencies.collectionCloudService.fetchCollections(forUserId: collection.userId)
            if let updatedCollection = ownerCollections.first(where: { $0.id == collection.id }) {
                collection = updatedCollection
            }
        } catch {
            AppLogger.general.warning("Failed to refresh shared collection metadata: \(error.localizedDescription)")
        }
    }

    private func promptForPublicMembershipRepairIfNeeded() {
        guard !hasPromptedForPublicMembershipRepair,
              publicMembershipRepairPlan.requiresRepair else {
            return
        }

        hasPromptedForPublicMembershipRepair = true
        showingPublicMembershipRepairConfirmation = true
    }

    private func repairPublicCollectionMemberships() async {
        guard let currentUserId = CurrentUserSession.shared.userId,
              currentUserId == collection.userId,
              publicMembershipRepairPlan.requiresRepair else {
            return
        }

        do {
            let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
                recipeIds: collection.recipeIds,
                ownerId: currentUserId,
                visibility: collection.visibility
            )

            if resolution.changedRecipeIds {
                let updatedCollection = collection.updated(recipeIds: resolution.recipeIds)
                try await dependencies.collectionRepository.update(updatedCollection)
            }

            await loadRecipes(forceRefresh: true)
        } catch {
            AppLogger.general.error("❌ Failed to repair public collection memberships: \(error.localizedDescription)")
            errorMessage = "Failed to repair collection sharing: \(error.localizedDescription)"
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

    private func checkFriendshipStatus(forceRefresh: Bool = false) async {
        guard !isOwned, let currentUserId = CurrentUserSession.shared.userId else {
            isFriendWithOwner = false
            return
        }

        await dependencies.connectionManager.loadConnections(forUserId: currentUserId, forceRefresh: forceRefresh)
        let connectionStatus = dependencies.connectionManager.connectionStatus(with: collection.userId)
        isFriendWithOwner = connectionStatus?.isAccepted ?? false
    }

    private func loadExistingSavedCollection() async {
        guard canSaveCollection else {
            savedCollection = nil
            return
        }

        do {
            savedCollection = try await dependencies.collectionSaveService.existingSavedCollection(for: collection)
        } catch {
            AppLogger.general.warning("Failed to check saved collection state: \(error.localizedDescription)")
        }
    }

    private func loadCollectionOwner(forceRefresh: Bool = false) async {
        guard !isOwned else {
            collectionOwner = nil
            return
        }

        do {
            collectionOwner = try await dependencies.userCloudService.fetchUser(byUserId: collection.userId)
        } catch {
            AppLogger.general.warning("Failed to fetch collection owner: \(error.localizedDescription)")
        }
    }

    private func saveCollectionToLibrary() async {
        guard !isSavingCollection else { return }

        isSavingCollection = true
        defer { isSavingCollection = false }

        do {
            let result = try await dependencies.collectionSaveService.saveCollectionToLibrary(
                collection,
                visibleRecipes: visibleRecipes,
                sourceOwnerName: collectionOwner?.displayName
            )
            savedCollection = result.collection
        } catch {
            AppLogger.general.error("❌ Failed to save collection: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - View Components

    private var emptyStateIconName: String {
        if shouldShowUnavailableRecipesEmptyState {
            return "exclamationmark.triangle"
        }
        return searchText.isEmpty ? "tray" : "magnifyingglass"
    }

    private var emptyStateTitle: String {
        if shouldShowUnavailableRecipesEmptyState {
            return "Recipes Unavailable"
        }
        return searchText.isEmpty ? "No recipes in this collection" : "No recipes found"
    }

    @ViewBuilder
    private func recipeDestination(for recipe: Recipe) -> some View {
        if !isOwned, let sharedRecipe = createSharedRecipe(from: recipe) {
            RecipeDetailView(
                recipe: recipe,
                dependencies: dependencies,
                sharedBy: sharedRecipe.sharedBy,
                sharedAt: sharedRecipe.sharedAt
            )
        } else {
            RecipeDetailView(recipe: recipe, dependencies: dependencies)
        }
    }

    @ViewBuilder
    private func recipeCard(for recipe: Recipe) -> some View {
        if !isOwned, let owner = collectionOwner {
            RecipeCardView(recipe: recipe, dependencies: dependencies, sharedBy: owner)
        } else {
            RecipeCardView(recipe: recipe, dependencies: dependencies)
        }
    }

    private func createSharedRecipe(from recipe: Recipe) -> SharedRecipe? {
        guard !isOwned else { return nil }

        let owner = collectionOwner ?? User(
            id: collection.userId,
            username: "user",
            displayName: "Unknown",
            createdAt: Date(),
            profileEmoji: nil,
            profileColor: nil
        )

        return SharedRecipe(
            recipe: recipe,
            sharedBy: owner,
            sharedAt: collection.updatedAt
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Text(collection.name.recipeDetailLineBreakFriendly())
                    .font(.title.bold())
                    .fontDesign(.serif)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                collectionPrimaryAction
            }

            if !isOwned {
                ownerPill
            }

            if hasDescription, let description = collection.description {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isOwned {
                HStack(spacing: 10) {
                    editCollectionButton
                    addRecipesButton
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var collectionPrimaryAction: some View {
        if canSaveCollection {
            if savedCollection != nil {
                Label("Saved", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .foregroundStyle(.green)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Saved")
            } else {
                Button {
                    Task {
                        await saveCollectionToLibrary()
                    }
                } label: {
                    if isSavingCollection {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.cauldronOrange.opacity(0.12), in: Capsule())
                    } else {
                        Label("Save", systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .foregroundStyle(Color.cauldronOrange)
                            .background(Color.cauldronOrange.opacity(0.12), in: Capsule())
                    }
                }
                .disabled(isLoading || isSavingCollection)
                .accessibilityLabel("Save Collection")
            }
        }
    }

    @ViewBuilder
    private var ownerPill: some View {
        if let owner = collectionOwner {
            NavigationLink {
                UserProfileView(user: owner, dependencies: dependencies)
            } label: {
                HStack(spacing: 6) {
                    ProfileAvatar(user: owner, size: 20, dependencies: dependencies)
                    Text("By \(owner.displayName.recipeDetailLineBreakFriendly())")
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSurface, in: Capsule())
            }
            .buttonStyle(PressableScaleStyle())
        }
    }

    @ViewBuilder
    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Recipes")
                .font(.title3)
                .fontWeight(.bold)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading recipes...")
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if visibleRecipes.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: emptyStateIconName)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Text(emptyStateTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

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
                .padding(.vertical, 40)
            } else {
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
        ForEach(visibleRecipes) { recipe in
            NavigationLink {
                recipeDestination(for: recipe)
            } label: {
                RecipeRowView(recipe: recipe, dependencies: dependencies)
            }
            .buttonStyle(PressableScaleStyle())
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

    private var recipesGridContent: some View {
        LazyVGrid(columns: recipeGridColumns, spacing: Theme.Spacing.md) {
            ForEach(visibleRecipes) { recipe in
                NavigationLink {
                    recipeDestination(for: recipe)
                } label: {
                    recipeCard(for: recipe)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressableScaleStyle())
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
    }

    private var recipeGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: Theme.Spacing.md)]
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
            .background(Color.appSurface, in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
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
            .background(Color.cauldronOrange.opacity(0.1), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleStyle())
    }

    // MARK: - Helpers

    private func updateVisibleRecipes() {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            visibleRecipes = recipes
            return
        }

        visibleRecipes = recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(trimmedSearchText) ||
            recipe.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(trimmedSearchText) })
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
