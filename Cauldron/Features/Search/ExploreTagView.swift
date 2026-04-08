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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with category styling
                headerSection

                // All Recipes Section
                if !viewModel.allRecipes.isEmpty {
                    allRecipesSection
                }

                // From Friends Section
                if !viewModel.friendRecipes.isEmpty {
                    friendRecipesSection
                }

                // Community Recipes Section
                if !viewModel.publicRecipes.isEmpty {
                    publicRecipesSection
                }

                // Empty State
                if viewModel.allRecipes.isEmpty && viewModel.friendRecipes.isEmpty && viewModel.publicRecipes.isEmpty && !viewModel.isLoading {
                    emptyState
                }

                // Loading State
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 40)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadRecipes()
        }
        .refreshable {
            await viewModel.loadRecipes()
        }
    }

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)

                if let emoji = emoji {
                    Text(emoji)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 28))
                        .foregroundColor(color)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title)
                    .fontWeight(.bold)

                let totalCount = viewModel.allRecipes.count + viewModel.friendRecipes.count
                if totalCount > 0 {
                    Text("\(totalCount) \(totalCount == 1 ? "recipe" : "recipes")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.allRecipes.prefix(10)) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                            RecipeCardView(recipe: recipe, dependencies: dependencies)
                        }
                        .buttonStyle(.plain)
                    }
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.friendRecipes.prefix(10)) { sharedRecipe in
                        NavigationLink(destination: RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy,
                            sharedAt: sharedRecipe.sharedAt
                        )) {
                            RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                        }
                        .buttonStyle(.plain)
                    }
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.publicRecipes.prefix(10)) { sharedRecipe in
                        NavigationLink(destination: RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy
                        )) {
                            RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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
}

// MARK: - ViewModel

@MainActor
@Observable
final class ExploreTagViewModel {
    let tag: Tag
    let dependencies: DependencyContainer

    var allRecipes: [Recipe] = []
    var friendRecipes: [SharedRecipe] = []
    var publicRecipes: [SharedRecipe] = []
    var isLoading = false

    private var currentUserId: UUID? {
        CurrentUserSession.shared.userId
    }

    init(tag: Tag, dependencies: DependencyContainer) {
        self.tag = tag
        self.dependencies = dependencies
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {}

    func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        AppLogger.general.info("🔍 Loading recipes for tag: \(tag.name)")

        do {
            let normalizedTag = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)

            // Parallelize tag-scoped fetches instead of loading every recipe and filtering in memory.
            async let localRecipesTask = dependencies.recipeRepository.search(tag: normalizedTag)
            async let publicRecipesTask = dependencies.recipeCloudService.querySharedRecipes(
                ownerIds: nil,
                visibility: .publicRecipe,
                requiredTag: normalizedTag,
                limit: 200
            )

            let friendIDsFuture: Task<Set<UUID>, Error>?
            let friendRecipesFuture: Task<[SharedRecipe], Error>?
            if let userId = currentUserId {
                let connectionsFuture = Task {
                    try await dependencies.connectionRepository.fetchConnections(forUserId: userId)
                }
                friendIDsFuture = Task {
                    let connections = try await connectionsFuture.value
                    return Self.acceptedFriendIDs(from: connections, currentUserId: userId)
                }
                friendRecipesFuture = Task {
                    let friendIds = try await friendIDsFuture.value
                    guard !friendIds.isEmpty else { return [] }

                    let recipes = try await dependencies.recipeCloudService.querySharedRecipes(
                        ownerIds: Array(friendIds),
                        visibility: .publicRecipe,
                        requiredTag: normalizedTag,
                        limit: 200
                    )
                    let referencedIds = Set(recipes.flatMap(\.relatedRecipeIds))
                    let filteredRecipes = recipes.filter { !referencedIds.contains($0.id) }

                    let ownerIds = Array(Set(filteredRecipes.compactMap(\.ownerId)))
                    guard !ownerIds.isEmpty else { return [] }

                    let owners = try await dependencies.userCloudService.fetchUsers(byUserIds: ownerIds)
                    let ownersById = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, $0) })

                    return filteredRecipes.compactMap { recipe in
                        guard let ownerId = recipe.ownerId,
                              let owner = ownersById[ownerId] else {
                            return nil
                        }

                        return SharedRecipe(
                            id: UUID(),
                            recipe: recipe,
                            sharedBy: owner,
                            sharedAt: recipe.createdAt
                        )
                    }
                }
            } else {
                friendIDsFuture = nil
                friendRecipesFuture = nil
            }

            // Await all parallel fetches
            let allUserRecipes = try await localRecipesTask
            let publicRecipesList = try await publicRecipesTask

            // Process local recipes (already filtered by tag)
            allRecipes = allUserRecipes
            AppLogger.general.info("✅ Found \(allRecipes.count) own recipes")

            if let friendRecipesFuture {
                friendRecipes = try await friendRecipesFuture.value
                    .sorted { $0.sharedAt > $1.sharedAt }
            } else {
                friendRecipes = []
            }
            AppLogger.general.info("✅ Loaded \(friendRecipes.count) friend recipes via SharingService")

            // Get friend IDs for filtering
            var friendIds: Set<UUID> = []
            if let friendIDsFuture {
                friendIds = try await friendIDsFuture.value
            }

            let candidatePublicRecipes = publicRecipesList.filter { recipe in
                guard let ownerId = recipe.ownerId else { return false }
                if let currentUserId = currentUserId, ownerId == currentUserId {
                    return false
                }
                if friendIds.contains(ownerId) {
                    return false
                }
                return true
            }

            if candidatePublicRecipes.isEmpty {
                publicRecipes = []
            } else {
                let owners = try await dependencies.userCloudService.fetchUsers(
                    byUserIds: Array(Set(candidatePublicRecipes.compactMap(\.ownerId)))
                )
                let ownersMap = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, $0) })

                publicRecipes = candidatePublicRecipes.compactMap { recipe -> SharedRecipe? in
                    guard let ownerId = recipe.ownerId,
                          let owner = ownersMap[ownerId] else {
                        return nil
                    }

                    return SharedRecipe(
                        recipe: recipe,
                        sharedBy: owner,
                        sharedAt: recipe.createdAt
                    )
                }
            }

        } catch {
            AppLogger.general.error("Failed to load recipes for tag '\(tag.name)': \(error.localizedDescription)")
        }
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
    let sharedRecipes: [SharedRecipe]
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
            ForEach(sharedRecipes) { sharedRecipe in
                NavigationLink(destination: RecipeDetailView(
                    recipe: sharedRecipe.recipe,
                    dependencies: dependencies,
                    sharedBy: sharedRecipe.sharedBy,
                    sharedAt: sharedRecipe.sharedAt
                )) {
                    RecipeRowView(recipe: sharedRecipe.recipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(sharedRecipes) { sharedRecipe in
                    NavigationLink(destination: RecipeDetailView(
                        recipe: sharedRecipe.recipe,
                        dependencies: dependencies,
                        sharedBy: sharedRecipe.sharedBy,
                        sharedAt: sharedRecipe.sharedAt
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
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
    let recipes: [SharedRecipe]
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
            ForEach(recipes) { sharedRecipe in
                NavigationLink(destination: RecipeDetailView(
                    recipe: sharedRecipe.recipe,
                    dependencies: dependencies,
                    sharedBy: sharedRecipe.sharedBy
                )) {
                    RecipeRowView(recipe: sharedRecipe.recipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(recipes) { sharedRecipe in
                    NavigationLink(destination: RecipeDetailView(
                        recipe: sharedRecipe.recipe,
                        dependencies: dependencies,
                        sharedBy: sharedRecipe.sharedBy
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
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
