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
            // Parallelize independent fetches for better performance
            async let localRecipesTask = dependencies.recipeRepository.fetchAll()
            async let sharedRecipesTask = dependencies.sharingService.getSharedRecipes()
            async let publicRecipesTask = dependencies.recipeCloudService.querySharedRecipes(
                ownerIds: nil,
                visibility: .publicRecipe
            )

            // Fetch connections in parallel too (if we have a user)
            let connectionsFuture: Task<[Connection], Error>?
            if let userId = currentUserId {
                connectionsFuture = Task {
                    try await dependencies.connectionRepository.fetchConnections(forUserId: userId)
                }
            } else {
                connectionsFuture = nil
            }

            // Await all parallel fetches
            let (allUserRecipes, allSharedRecipes, publicRecipesList) = try await (
                localRecipesTask,
                sharedRecipesTask,
                publicRecipesTask
            )

            // Process local recipes (filter by tag)
            allRecipes = allUserRecipes.filter { recipe in
                recipe.tags.contains { $0.name.lowercased() == tag.name.lowercased() }
            }
            AppLogger.general.info("✅ Found \(allRecipes.count) own recipes")

            // Process friend recipes (filter by tag)
            friendRecipes = allSharedRecipes
                .filter { sharedRecipe in
                    sharedRecipe.recipe.tags.contains { $0.name.lowercased() == tag.name.lowercased() }
                }
                .sorted { $0.sharedAt > $1.sharedAt }
            AppLogger.general.info("✅ Loaded \(friendRecipes.count) friend recipes via SharingService")

            // Collect owner IDs from public recipes
            let ownerIds = Set(publicRecipesList.map { $0.ownerId }.compactMap { $0 })

            // Fetch owners in batch
            let owners = try await dependencies.userCloudService.fetchUsers(byUserIds: Array(ownerIds))
            let ownersMap = Dictionary(uniqueKeysWithValues: owners.map { ($0.id, $0) })

            // Get friend IDs for filtering
            var friendIds: Set<UUID> = []
            if let connectionsFuture = connectionsFuture {
                let connections = try await connectionsFuture.value
                let acceptedConnections = connections.filter { $0.isAccepted }
                friendIds = Set(acceptedConnections.map {
                    $0.fromUserId == currentUserId ? $0.toUserId : $0.fromUserId
                })
            }

            // Filter and map to SharedRecipe
            publicRecipes = publicRecipesList.compactMap { recipe -> SharedRecipe? in
                // Match tag
                guard recipe.tags.contains(where: { $0.name.lowercased() == tag.name.lowercased() }) else {
                    return nil
                }

                guard let ownerId = recipe.ownerId else { return nil }

                // Exclude own recipes
                if let currentUserId = currentUserId, ownerId == currentUserId { return nil }

                // Exclude friend recipes (using friendIds from connections)
                if friendIds.contains(ownerId) { return nil }

                // Get owner
                guard let owner = ownersMap[ownerId] else { return nil }

                return SharedRecipe(
                    recipe: recipe,
                    sharedBy: owner,
                    sharedAt: recipe.createdAt
                )
            }

        } catch {
            AppLogger.general.error("Failed to load recipes for tag '\(tag.name)': \(error.localizedDescription)")
        }
    }
}

// MARK: - List Views

struct TagRecipesListView: View {
    let tag: Tag
    let recipes: [Recipe]
    let dependencies: DependencyContainer
    let color: Color

    var body: some View {
        List {
            ForEach(recipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                    RecipeRowView(recipe: recipe, dependencies: dependencies)
                }
            }
        }
        .navigationTitle("All Recipes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TagFriendRecipesListView: View {
    let tag: Tag
    let sharedRecipes: [SharedRecipe]
    let dependencies: DependencyContainer
    let color: Color

    var body: some View {
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
        .navigationTitle("From Friends")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TagPublicRecipesListView: View {
    let tag: Tag
    let recipes: [SharedRecipe]
    let dependencies: DependencyContainer
    let color: Color

    var body: some View {
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
        .navigationTitle("Community Recipes")
        .navigationBarTitleDisplayMode(.inline)
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
