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
    @State private var customCoverImage: UIImage?
    @State private var loadedCoverKey: String?
    @State private var isLoadingCoverImage = false
    @State private var selectedCoverPage = 0
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

    private var collectionSymbolName: String {
        collection.symbolName ?? "folder.fill"
    }

    private var customCoverTaskID: String {
        let remoteKey = collection.coverImageURL?.absoluteString ?? collection.cloudCoverImageRecordName ?? "no-cover"
        return "\(collection.id.uuidString)|\(collection.coverImageType.rawValue)|\(remoteKey)"
    }

    private var recipeLayoutToolbarMenu: some View {
        RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
            storedRecipeLayoutMode = mode.rawValue
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                collectionCover

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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipes")
        .onChange(of: searchText) { _, _ in
            updateVisibleRecipes()
        }
        .onChange(of: collectionCoverPageCount) { _, pageCount in
            selectedCoverPage = min(selectedCoverPage, max(0, pageCount - 1))
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
        .task(id: customCoverTaskID) {
            await loadCustomCoverImage()
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

    @MainActor
    private func loadCustomCoverImage() async {
        guard collection.coverImageType == .customImage else {
            customCoverImage = nil
            loadedCoverKey = nil
            isLoadingCoverImage = false
            return
        }

        if loadedCoverKey != customCoverTaskID {
            customCoverImage = nil
        }
        isLoadingCoverImage = true
        defer { isLoadingCoverImage = false }

        let image = await dependencies.entityImageLoader.loadCollectionCoverImage(
            for: collection,
            dependencies: dependencies
        )

        guard !Task.isCancelled else { return }

        if let image {
            if let currentImage = customCoverImage {
                if !ImageLoadingPipeline.areImagesEqual(image, currentImage) {
                    customCoverImage = image
                }
            } else {
                customCoverImage = image
            }
            loadedCoverKey = customCoverTaskID
        } else {
            customCoverImage = nil
            loadedCoverKey = nil
        }
    }

    // MARK: - View Components

    private var collectionCover: some View {
        VStack(spacing: 10) {
            TabView(selection: $selectedCoverPage) {
                if showsCustomCollectionCoverPage {
                    customCoverView
                        .tag(0)
                        .accessibilityLabel("\(collection.name) collection cover")
                }

                if collectionCoverRecipePages.isEmpty && !showsCustomCollectionCoverPage {
                    fallbackCoverView
                        .tag(0)
                        .accessibilityLabel("\(collection.name) collection cover")
                }

                ForEach(Array(collectionCoverRecipePages.enumerated()), id: \.element.id) { index, recipe in
                    collectionRecipeCoverPage(for: recipe)
                        .tag(showsCustomCollectionCoverPage ? index + 1 : index)
                    .accessibilityLabel(recipe.title)
                }
            }
            .id(collectionCoverPagesID)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .regular ? 360 : 260)
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.07), radius: 14, y: 6)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            }

            if collectionCoverPageCount > 1 {
                collectionCoverPageIndicator
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var showsCustomCollectionCoverPage: Bool {
        collection.coverImageType == .customImage
    }

    private var collectionCoverPageCount: Int {
        let customCoverCount = showsCustomCollectionCoverPage ? 1 : 0
        return max(1, customCoverCount + collectionCoverRecipePages.count)
    }

    private var collectionCoverPagesID: String {
        let recipePageKeys = collectionCoverRecipePages.map { recipe in
            [
                recipe.id.uuidString,
                recipe.imageURL?.absoluteString ?? "no-url",
                recipe.cloudImageRecordName ?? "no-cloud-image"
            ].joined(separator: ":")
        }
        let customCoverKey = showsCustomCollectionCoverPage ? customCoverTaskID : "no-custom-cover"
        return ([customCoverKey] + recipePageKeys).joined(separator: "|")
    }

    private var collectionCoverRecipePages: [Recipe] {
        let recipesById = RecipeDeduplication.byIdPreferringBest(recipes)
        let imageSourceByRecipeId = recipeImageSources.reduce(into: [UUID: CollectionRecipeImageSource]()) { result, source in
            if let recipeId = source.recipeId, result[recipeId] == nil {
                result[recipeId] = source
            }
        }
        var seenRecipeIds = Set<UUID>()
        let orderedRecipes = collection.recipeIds.compactMap { recipeId -> Recipe? in
            guard seenRecipeIds.insert(recipeId).inserted else {
                return nil
            }
            return recipesById[recipeId]
        }

        let imageCapableRecipes = orderedRecipes.filter { recipe in
            let imageSource = imageSourceByRecipeId[recipe.id]
            return recipe.imageURL != nil || recipe.cloudImageRecordName != nil || imageSource?.canLoadImage == true
        }

        return Array(imageCapableRecipes.prefix(10))
    }

    @ViewBuilder
    private func collectionRecipeCoverPage(for recipe: Recipe) -> some View {
        ZStack(alignment: .bottomLeading) {
            RecipeImageView(
                imageURL: recipe.imageURL,
                size: .collectionTile,
                showPlaceholderText: false,
                recipeImageService: dependencies.recipeImageService,
                recipeId: recipe.id,
                ownerId: recipe.ownerId
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.18), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )

            recipeCoverTitle(recipe.title)
        }
    }

    private func recipeCoverTitle(_ title: String) -> some View {
        Text(title.recipeDetailLineBreakFriendly())
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .minimumScaleFactor(0.88)
            .allowsTightening(true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            .accessibilityHidden(true)
    }

    private var collectionCoverPageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<collectionCoverPageCount, id: \.self) { index in
                Capsule()
                    .fill(index == selectedCoverPage ? collectionColor : Color.secondary.opacity(0.28))
                    .frame(width: index == selectedCoverPage ? 18 : 6, height: 6)
                    .animation(.snappy(duration: 0.2), value: selectedCoverPage)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Cover page \(selectedCoverPage + 1) of \(collectionCoverPageCount)")
    }

    @ViewBuilder
    private var customCoverView: some View {
        if let customCoverImage {
            Image(uiImage: customCoverImage)
                .resizable()
                .scaledToFill()
        } else if isLoadingCoverImage {
            fallbackCoverView
                .overlay {
                    ProgressView()
                        .tint(.white)
                }
        } else {
            fallbackCoverView
        }
    }

    @ViewBuilder
    private var fallbackCoverView: some View {
        CollectionCoverArtwork(
            imageSources: [],
            additionalRecipeCount: 0,
            collectionColor: collectionColor,
            collectionSymbolName: collectionSymbolName,
            dependencies: dependencies,
            iconScale: 82
        )
    }

    private var collectionColor: Color {
        Color(hex: collection.color ?? "#FF9933") ?? .cauldronOrange
    }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
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
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                VStack(spacing: 12) {
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

    private var recipesGridContent: some View {
        LazyVGrid(columns: recipeGridColumns, spacing: 16) {
            ForEach(visibleRecipes) { recipe in
                NavigationLink {
                    recipeDestination(for: recipe)
                } label: {
                    recipeCard(for: recipe)
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
    }

    private var recipeGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16)]
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
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
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
            .background(Color.cauldronOrange.opacity(0.1), in: Capsule())
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                    cloudImageRecordName: recipe.cloudImageRecordName,
                    imageModifiedAt: recipe.imageModifiedAt,
                    createdAt: recipe.createdAt,
                    updatedAt: Date(),
                    originalRecipeId: recipe.originalRecipeId,
                    originalCreatorId: recipe.originalCreatorId,
                    originalCreatorName: recipe.originalCreatorName,
                    savedAt: recipe.savedAt,
                    sourceRecipeUpdatedAt: recipe.sourceRecipeUpdatedAt,
                    followsSourceUpdates: recipe.followsSourceUpdates,
                    relatedRecipeIds: recipe.relatedRecipeIds,
                    isPreview: recipe.isPreview
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
