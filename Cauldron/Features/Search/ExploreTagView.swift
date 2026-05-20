//
//  ExploreTagView.swift
//  Cauldron
//
//  Explore recipes by tag with sections for all recipes and friend recipes
//

import SwiftUI

struct ExploreTagView: View {
    let tag: Tag
    let dependencies: DependencyContainer

    @State private var viewModel: ExploreTagViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(tag: Tag, dependencies: DependencyContainer) {
        self.tag = tag
        self.dependencies = dependencies
        _viewModel = State(initialValue: ExploreTagViewModel(tag: tag, dependencies: dependencies))
    }

    // Resolve category for styling
    private var category: RecipeCategory? {
        RecipeCategory.match(string: tag.name)
    }

    private var displayName: String {
        category?.displayName ?? tag.name
    }

    private var emoji: String? {
        category?.emoji
    }

    private var color: Color {
        category?.color ?? .cauldronOrange
    }

    private var horizontalContentPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if viewModel.isLoading && !viewModel.hasContent {
                    loadingPlaceholder
                }

                if !viewModel.allRecipes.isEmpty {
                    allRecipesSection
                }

                if !viewModel.friendRecipes.isEmpty {
                    friendRecipesSection
                }

                if !viewModel.publicRecipes.isEmpty {
                    publicRecipesSection
                }

                if !viewModel.hasContent && !viewModel.isLoading {
                    emptyState
                }

                if viewModel.isLoading && viewModel.hasContent {
                    refreshingIndicator
                }
            }
            .padding(.horizontal, horizontalContentPadding)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle(displayName)
        .toolbarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRecipes()
        }
        .refreshable {
            await viewModel.loadRecipes(forceRefresh: true)
        }
    }

    private var allRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .foregroundColor(color)
                    Text("My Recipes")
                }
                .font(.title2)
                .fontWeight(.bold)

                Spacer()

                NavigationLink(destination: TagRecipesListView(
                    tag: tag,
                    recipes: viewModel.allRecipes,
                    dependencies: dependencies,
                    color: color
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            edgeToEdgeRecipeCarousel {
                ForEach(viewModel.allRecipes.prefix(10)) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                        RecipeCardView(recipe: recipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var friendRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(color)
                    Text("From Friends")
                }
                .font(.title2)
                .fontWeight(.bold)

                Spacer()

                NavigationLink(destination: TagFriendRecipesListView(
                    tag: tag,
                    sharedRecipes: viewModel.friendRecipes,
                    dependencies: dependencies,
                    color: color
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            edgeToEdgeRecipeCarousel {
                ForEach(viewModel.friendRecipes.prefix(10)) { sharedRecipeSummary in
                    NavigationLink(destination: PublicRecipeDetailLoaderView(
                        summary: sharedRecipeSummary,
                        dependencies: dependencies
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipeSummary.previewSharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var publicRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .foregroundColor(color)
                    Text("Community Recipes")
                }
                .font(.title2)
                .fontWeight(.bold)

                Spacer()

                NavigationLink(destination: TagPublicRecipesListView(
                    tag: tag,
                    recipes: viewModel.publicRecipes,
                    dependencies: dependencies,
                    color: color
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            edgeToEdgeRecipeCarousel {
                ForEach(viewModel.publicRecipes.prefix(10)) { sharedRecipeSummary in
                    NavigationLink(destination: PublicRecipeDetailLoaderView(
                        summary: sharedRecipeSummary,
                        dependencies: dependencies
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipeSummary.previewSharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func edgeToEdgeRecipeCarousel<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                content()
            }
            .padding(.horizontal, horizontalContentPadding)
        }
        .padding(.horizontal, -horizontalContentPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Recipes Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("No recipes with the tag '\(tag.name)' yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                if let emoji {
                    Text(emoji)
                } else {
                    Image(systemName: "tag.fill")
                        .foregroundColor(color)
                }

                Text("Loading recipes")
                    .foregroundColor(.secondary)
            }
            .font(.headline)

            ExploreTagRecipeCarouselPlaceholder(horizontalContentPadding: horizontalContentPadding)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var refreshingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Refreshing")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct ExploreTagRecipeCarouselPlaceholder: View {
    let horizontalContentPadding: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { _ in
                    ExploreTagRecipeCardPlaceholder()
                }
            }
            .padding(.horizontal, horizontalContentPadding)
        }
        .padding(.horizontal, -horizontalContentPadding)
    }
}

private struct ExploreTagRecipeCardPlaceholder: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var cardWidth: CGFloat {
        horizontalSizeClass == .regular ? 252 : 240
    }

    private var cardHeight: CGFloat {
        horizontalSizeClass == .regular ? 168 : 160
    }

    private var placeholderFill: Color {
        Color.secondary.opacity(0.14)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 16)
                .fill(placeholderFill)
                .frame(width: cardWidth, height: cardHeight)

            RoundedRectangle(cornerRadius: 4)
                .fill(placeholderFill)
                .frame(width: cardWidth, height: 20)

            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(placeholderFill)
                    .frame(width: 72, height: 14)

                Spacer()

                Capsule()
                    .fill(placeholderFill)
                    .frame(width: 86, height: 20)
            }
            .frame(width: cardWidth, height: 20)
        }
        .frame(width: cardWidth)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class ExploreTagViewModel {
    let tag: Tag
    let dependencies: DependencyContainer

    var allRecipes: [Recipe] = []
    var friendRecipes: [SharedRecipeSummary] = []
    var publicRecipes: [SharedRecipeSummary] = []
    var isLoading = false

    @ObservationIgnored private var ownerCache: [UUID: User] = [:]
    @ObservationIgnored private var hasRequestedSearchMetadataRefresh = false

    private static let cacheValidityDuration: TimeInterval = 300
    private static var tagResultCache: [String: CachedTagResults] = [:]

    private struct CachedTagResults {
        let allRecipes: [Recipe]
        let friendRecipes: [SharedRecipeSummary]
        let publicRecipes: [SharedRecipeSummary]
        let fetchedAt: Date
    }

    private var currentUserId: UUID? {
        CurrentUserSession.shared.userId
    }

    var hasContent: Bool {
        !allRecipes.isEmpty || !friendRecipes.isEmpty || !publicRecipes.isEmpty
    }

    init(tag: Tag, dependencies: DependencyContainer) {
        self.tag = tag
        self.dependencies = dependencies
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadRecipes(forceRefresh: Bool = false) async {
        let normalizedTag = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = Self.cacheKey(for: normalizedTag, currentUserId: currentUserId)

        if !forceRefresh, applyCachedResults(for: cacheKey) {
            return
        }

        isLoading = true
        defer { isLoading = false }

        AppLogger.general.info("🔍 Loading recipes for tag: \(tag.name)")

        do {
            // User-facing local tag browsing must stay on the owned-library
            // boundary; raw tag search can include cached non-owned recipes.
            async let localRecipesTask = dependencies.recipeRepository.fetchLibraryRecipes(ownerId: currentUserId)
            async let primarySharedRecipesTask = dependencies.recipeDiscoveryCache.querySharedRecipeSummaries(
                ownerIds: nil,
                visibility: .publicRecipe,
                requiredTag: normalizedTag,
                includeDerivedCopies: false,
                limit: 200,
                forceRefresh: forceRefresh
            )

            let friendIDsFuture: Task<Set<UUID>, Error>?
            if let userId = currentUserId {
                let connectionsFuture = Task {
                    try await dependencies.connectionRepository.fetchConnections(forUserId: userId)
                }
                let friendIDsTask = Task {
                    let connections = try await connectionsFuture.value
                    return Self.acceptedFriendIDs(from: connections, currentUserId: userId)
                }
                friendIDsFuture = friendIDsTask
            } else {
                friendIDsFuture = nil
            }

            let localLibraryRecipes = try await localRecipesTask
            let allUserRecipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
                localLibraryRecipes.filter { recipe in
                    recipe.tags.contains { $0.name.localizedCaseInsensitiveContains(normalizedTag) }
                },
                currentUserId: currentUserId,
                hidingRelatedRecipeReferences: true
            )

            // Process local recipes as soon as they are ready. Shared CloudKit/profile
            // lookups can still be in flight without blocking owned content.
            allRecipes = allUserRecipes
            AppLogger.general.info("✅ Found \(allRecipes.count) own recipes")

            let primarySharedRecipes = try await primarySharedRecipesTask
            await applySharedRecipeSummaries(primarySharedRecipes, friendIds: [])

            var friendIds: Set<UUID> = []
            if let friendIDsFuture {
                friendIds = try await friendIDsFuture.value
                if !friendIds.isEmpty {
                    await applySharedRecipeSummaries(primarySharedRecipes, friendIds: friendIds)
                }
            }

            if primarySharedRecipes.isEmpty {
                requestSearchMetadataRefresh(normalizedTag: normalizedTag, friendIds: friendIds)
            }

            storeCachedResults(for: cacheKey)

        } catch {
            AppLogger.general.error("Failed to load recipes for tag '\(tag.name)': \(error.localizedDescription)")
        }
    }

    private func applySharedRecipeSummaries(
        _ sharedRecipesList: [RecipeSummary],
        friendIds: Set<UUID>
    ) async {
        do {
            let visibleSharedRecipes = sharedRecipesList.filter { recipe in
                guard let ownerId = recipe.ownerId else { return false }
                if let currentUserId = currentUserId, ownerId == currentUserId {
                    return false
                }
                return true
            }

            let friendRecipeCandidates = visibleSharedRecipes.filter { recipe in
                guard let ownerId = recipe.ownerId else { return false }
                return friendIds.contains(ownerId)
            }
            let publicRecipeCandidates = visibleSharedRecipes.filter { recipe in
                guard let ownerId = recipe.ownerId else { return false }
                return !friendIds.contains(ownerId)
            }

            setSharedRecipeSections(
                friendRecipeCandidates: friendRecipeCandidates,
                publicRecipeCandidates: publicRecipeCandidates,
                ownersMap: cachedOwnerMap(for: Set(visibleSharedRecipes.compactMap(\.ownerId)))
            )

            let ownerIds = Set(visibleSharedRecipes.compactMap(\.ownerId))
            if !ownerIds.isEmpty {
                let ownersMap = try await owners(for: ownerIds)
                setSharedRecipeSections(
                    friendRecipeCandidates: friendRecipeCandidates,
                    publicRecipeCandidates: publicRecipeCandidates,
                    ownersMap: ownersMap
                )
            }
        } catch {
            AppLogger.general.warning("Loaded shared recipes for tag '\(tag.name)' without profile refresh: \(error.localizedDescription)")
        }
    }

    private func requestSearchMetadataRefresh(normalizedTag: String, friendIds: Set<UUID>) {
        guard !hasRequestedSearchMetadataRefresh else {
            return
        }

        hasRequestedSearchMetadataRefresh = true
        let capturedDependencies = dependencies
        let cacheKey = Self.cacheKey(for: normalizedTag, currentUserId: currentUserId)

        Task {
            await capturedDependencies.recipeRepository.migratePublicRecipeSearchMetadata()

            do {
                let refreshedSharedRecipes = try await capturedDependencies.recipeDiscoveryCache.querySharedRecipeSummaries(
                    ownerIds: nil,
                    visibility: .publicRecipe,
                    requiredTag: normalizedTag,
                    includeDerivedCopies: false,
                    limit: 200,
                    forceRefresh: true
                )
                await applySharedRecipeSummaries(refreshedSharedRecipes, friendIds: friendIds)
                storeCachedResults(for: cacheKey)
            } catch {
                AppLogger.general.warning("Search metadata refresh for tag '\(normalizedTag)' did not return shared recipes: \(error.localizedDescription)")
            }
        }
    }

    private func owners(for ownerIds: Set<UUID>) async throws -> [UUID: User] {
        var ownersMap = cachedOwnerMap(for: ownerIds)
        var missingOwnerIds: [UUID] = []

        for ownerId in ownerIds where ownersMap[ownerId] == nil {
            if let cachedOwner = try? await dependencies.sharingRepository.fetchUser(id: ownerId) {
                ownersMap[ownerId] = cachedOwner
                ownerCache[ownerId] = cachedOwner
            } else {
                missingOwnerIds.append(ownerId)
            }
        }

        guard !missingOwnerIds.isEmpty else {
            return ownersMap
        }

        let cloudOwners = try await dependencies.recipeDiscoveryCache.fetchUsers(byUserIds: missingOwnerIds)
        for owner in cloudOwners {
            ownersMap[owner.id] = owner
            ownerCache[owner.id] = owner
            try? await dependencies.sharingRepository.save(owner)
        }

        return ownersMap
    }

    private func cachedOwnerMap(for ownerIds: Set<UUID>) -> [UUID: User] {
        Dictionary(ownerIds.compactMap { ownerId in
            ownerCache[ownerId].map { (ownerId, $0) }
        }, uniquingKeysWith: { current, candidate in
            candidate.createdAt > current.createdAt ? candidate : current
        })
    }

    private func setSharedRecipeSections(
        friendRecipeCandidates: [RecipeSummary],
        publicRecipeCandidates: [RecipeSummary],
        ownersMap: [UUID: User]
    ) {
        friendRecipes = friendRecipeCandidates.map { recipe in
            SharedRecipeSummary(
                id: UUID(),
                recipe: recipe,
                sharedBy: owner(for: recipe, ownersMap: ownersMap),
                sharedAt: recipe.createdAt
            )
        }
        .sorted { $0.sharedAt > $1.sharedAt }
        AppLogger.general.info("✅ Loaded \(friendRecipes.count) friend recipes")

        publicRecipes = publicRecipeCandidates.map { recipe in
            SharedRecipeSummary(
                recipe: recipe,
                sharedBy: owner(for: recipe, ownersMap: ownersMap),
                sharedAt: recipe.createdAt
            )
        }
        .sorted { $0.sharedAt > $1.sharedAt }
    }

    private func applyCachedResults(for cacheKey: String) -> Bool {
        guard let cachedResults = Self.tagResultCache[cacheKey],
              Date().timeIntervalSince(cachedResults.fetchedAt) < Self.cacheValidityDuration else {
            return false
        }

        allRecipes = cachedResults.allRecipes
        friendRecipes = cachedResults.friendRecipes
        publicRecipes = cachedResults.publicRecipes
        return true
    }

    private func storeCachedResults(for cacheKey: String) {
        Self.tagResultCache[cacheKey] = CachedTagResults(
            allRecipes: allRecipes,
            friendRecipes: friendRecipes,
            publicRecipes: publicRecipes,
            fetchedAt: Date()
        )
    }

    private nonisolated static func cacheKey(for tag: String, currentUserId: UUID?) -> String {
        let normalizedTag = tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return "\(currentUserId?.uuidString ?? "anonymous")::\(normalizedTag)"
    }

    private func owner(for recipe: RecipeSummary, ownersMap: [UUID: User]) -> User {
        guard let ownerId = recipe.ownerId else {
            return User(username: "unknown", displayName: "Unknown Chef")
        }

        if let owner = ownersMap[ownerId] {
            return owner
        }

        let displayName = recipe.originalCreatorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = displayName?.isEmpty == false ? displayName! : "Community Chef"
        return User(
            id: ownerId,
            username: "chef_\(ownerId.uuidString.prefix(8).lowercased())",
            displayName: fallbackName
        )
    }

    private nonisolated static func acceptedFriendIDs(
        from connections: [Connection],
        currentUserId: UUID
    ) -> Set<UUID> {
        Set(connections.compactMap { connection in
            guard connection.isAccepted else { return nil }

            if connection.fromUserId == currentUserId {
                return connection.toUserId
            }
            if connection.toUserId == currentUserId {
                return connection.fromUserId
            }
            return nil
        })
    }
}

// MARK: - List Views

struct TagRecipesListView: View {
    let tag: Tag
    let recipes: [Recipe]
    let dependencies: DependencyContainer
    let color: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
        .navigationTitle("All Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
                    storedRecipeLayoutMode = mode.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if usesGridRecipeLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        List {
            ForEach(recipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                    RecipeRowView(recipe: recipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(recipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                        RecipeCardView(recipe: recipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct TagFriendRecipesListView: View {
    let tag: Tag
    let sharedRecipes: [SharedRecipeSummary]
    let dependencies: DependencyContainer
    let color: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
        .navigationTitle("From Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
                    storedRecipeLayoutMode = mode.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if usesGridRecipeLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        List {
            ForEach(sharedRecipes) { sharedRecipeSummary in
                NavigationLink(destination: PublicRecipeDetailLoaderView(
                    summary: sharedRecipeSummary,
                    dependencies: dependencies
                )) {
                    RecipeRowView(recipe: sharedRecipeSummary.recipe.previewRecipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(sharedRecipes) { sharedRecipeSummary in
                    NavigationLink(destination: PublicRecipeDetailLoaderView(
                        summary: sharedRecipeSummary,
                        dependencies: dependencies
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipeSummary.previewSharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct TagPublicRecipesListView: View {
    let tag: Tag
    let recipes: [SharedRecipeSummary]
    let dependencies: DependencyContainer
    let color: Color
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
        .navigationTitle("Community Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
                    storedRecipeLayoutMode = mode.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if usesGridRecipeLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        List {
            ForEach(recipes) { sharedRecipeSummary in
                NavigationLink(destination: PublicRecipeDetailLoaderView(
                    summary: sharedRecipeSummary,
                    dependencies: dependencies
                )) {
                    RecipeRowView(recipe: sharedRecipeSummary.recipe.previewRecipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(recipes) { sharedRecipeSummary in
                    NavigationLink(destination: PublicRecipeDetailLoaderView(
                        summary: sharedRecipeSummary,
                        dependencies: dependencies
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipeSummary.previewSharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

private struct PublicRecipeDetailLoaderView: View {
    let summary: SharedRecipeSummary
    let dependencies: DependencyContainer

    @State private var fullRecipe: Recipe?
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let fullRecipe {
                RecipeDetailView(
                    recipe: fullRecipe,
                    dependencies: dependencies,
                    sharedBy: summary.sharedBy,
                    sharedAt: summary.sharedAt
                )
            } else if loadFailed {
                ContentUnavailableView(
                    "Recipe Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This recipe could not be loaded right now.")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: summary.recipe.id) {
            await loadFullRecipe()
        }
    }

    private func loadFullRecipe() async {
        guard isLoading else { return }
        isLoading = true
        loadFailed = false

        do {
            if let recipe = try await dependencies.recipeDiscoveryCache.fetchPublicRecipe(id: summary.recipe.id) {
                fullRecipe = recipe
            } else {
                loadFailed = true
            }
        } catch {
            AppLogger.general.warning("Failed to load full public recipe \(summary.recipe.id): \(error.localizedDescription)")
            loadFailed = true
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        ExploreTagView(
            tag: Tag(name: "Breakfast"),
            dependencies: .preview()
        )
    }
}
