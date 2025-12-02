//
//  ExploreTagView.swift
//  Cauldron
//
//  Explore recipes by tag with sections for all recipes and friend recipes
//

import SwiftUI
import Combine

struct ExploreTagView: View {
    let tag: Tag
    let dependencies: DependencyContainer

    @StateObject private var viewModel: ExploreTagViewModel

    init(tag: Tag, dependencies: DependencyContainer) {
        self.tag = tag
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ExploreTagViewModel(tag: tag, dependencies: dependencies))
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

                // Empty State
                if viewModel.allRecipes.isEmpty && viewModel.friendRecipes.isEmpty && !viewModel.isLoading {
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
                    Text("All Recipes")
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
                            ExploreTagRecipeCard(recipe: recipe, dependencies: dependencies)
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
                            ExploreTagRecipeCard(recipe: sharedRecipe.recipe, dependencies: dependencies, sharedBy: sharedRecipe.sharedBy)
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

// MARK: - Recipe Card for Tag Exploration

struct ExploreTagRecipeCard: View {
    let recipe: Recipe
    let dependencies: DependencyContainer
    var sharedBy: User? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image with badges
            ZStack(alignment: .topTrailing) {
                RecipeImageView(recipe: recipe, recipeImageService: dependencies.recipeImageService)

                // Favorite indicator (top-right)
                if recipe.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(8)
                }
            }
            .frame(width: 240, height: 160)

            // Title - single line for clean look
            Text(recipe.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 240, height: 20, alignment: .leading)

            // Metadata row - fixed height for alignment
            HStack(spacing: 4) {
                // Time - always reserve space
                if let time = recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(" ")
                        .font(.caption)
                        .frame(width: 60)
                }

                Spacer()

                // Shared by indicator or tag
                if let sharedBy = sharedBy {
                    HStack(spacing: 4) {
                        ProfileAvatar(user: sharedBy, size: 16, dependencies: dependencies)
                        Text(sharedBy.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 120, alignment: .trailing)
                } else if !recipe.tags.isEmpty, let firstTag = recipe.tags.first {
                    TagView(firstTag)
                        .scaleEffect(0.9)
                        .frame(maxWidth: 100, alignment: .trailing)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .frame(width: 60)
                }
            }
            .frame(width: 240, height: 20)
        }
        .frame(width: 240)
    }
}

// MARK: - ViewModel

@MainActor
class ExploreTagViewModel: ObservableObject {
    let tag: Tag
    let dependencies: DependencyContainer

    @Published var allRecipes: [Recipe] = []
    @Published var friendRecipes: [SharedRecipe] = []
    @Published var isLoading = false

    private var currentUserId: UUID? {
        CurrentUserSession.shared.userId
    }

    init(tag: Tag, dependencies: DependencyContainer) {
        self.tag = tag
        self.dependencies = dependencies
    }

    func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load all recipes with this tag (user's own recipes)
            let allUserRecipes = try await dependencies.recipeRepository.fetchAll()
            allRecipes = allUserRecipes.filter { recipe in
                recipe.tags.contains { $0.name.lowercased() == tag.name.lowercased() }
            }

            // Load friend recipes with this tag
            guard let userId = currentUserId else { return }

            // Get all connections
            let connections = try await dependencies.connectionRepository.fetchConnections(forUserId: userId)
            let acceptedConnections = connections.filter { $0.isAccepted }

            // Fetch friend recipes in parallel using task group with concurrency limits
            // Limit to 5 concurrent CloudKit operations to avoid rate limiting
            let friendRecipesTemp = await withTaskGroup(of: [SharedRecipe].self) { group in
                var activeTasks = 0
                let maxConcurrent = 5
                var connectionIterator = acceptedConnections.makeIterator()

                // Start initial batch of tasks
                while activeTasks < maxConcurrent, let connection = connectionIterator.next() {
                    activeTasks += 1
                    group.addTask { [dependencies, tag] in
                        let friendId = connection.fromUserId == userId ? connection.toUserId : connection.fromUserId

                        do {
                            // Fetch friend's user record and their public recipes
                            guard let friendUser = try await dependencies.cloudKitService.fetchUser(byUserId: friendId) else {
                                AppLogger.general.warning("Friend user not found: \(friendId)")
                                return []
                            }

                            let friendRecipesList = try await dependencies.cloudKitService.fetchPublicRecipesForUser(ownerId: friendId)

                            // Filter by tag and map to SharedRecipe
                            return friendRecipesList
                                .filter { recipe in
                                    recipe.tags.contains { $0.name.lowercased() == tag.name.lowercased() }
                                }
                                .map { recipe in
                                    SharedRecipe(
                                        recipe: recipe,
                                        sharedBy: friendUser,
                                        sharedAt: recipe.createdAt
                                    )
                                }
                        } catch {
                            AppLogger.general.warning("Failed to load recipes for friend \(friendId): \(error.localizedDescription)")
                            return []
                        }
                    }
                }

                // Collect results and spawn new tasks as others complete
                var allRecipes: [SharedRecipe] = []
                for await recipes in group {
                    allRecipes.append(contentsOf: recipes)
                    activeTasks -= 1

                    // Start next task if more connections available
                    if let connection = connectionIterator.next() {
                        activeTasks += 1
                        group.addTask { [dependencies, tag] in
                            let friendId = connection.fromUserId == userId ? connection.toUserId : connection.fromUserId

                            do {
                                guard let friendUser = try await dependencies.cloudKitService.fetchUser(byUserId: friendId) else {
                                    AppLogger.general.warning("Friend user not found: \(friendId)")
                                    return []
                                }

                                let friendRecipesList = try await dependencies.cloudKitService.fetchPublicRecipesForUser(ownerId: friendId)

                                return friendRecipesList
                                    .filter { recipe in
                                        recipe.tags.contains { $0.name.lowercased() == tag.name.lowercased() }
                                    }
                                    .map { recipe in
                                        SharedRecipe(
                                            recipe: recipe,
                                            sharedBy: friendUser,
                                            sharedAt: recipe.createdAt
                                        )
                                    }
                            } catch {
                                AppLogger.general.warning("Failed to load recipes for friend \(friendId): \(error.localizedDescription)")
                                return []
                            }
                        }
                    }
                }

                return allRecipes
            }

            friendRecipes = friendRecipesTemp.sorted { $0.sharedAt > $1.sharedAt }

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

#Preview {
    NavigationStack {
        ExploreTagView(
            tag: Tag(name: "Breakfast"),
            dependencies: .preview()
        )
    }
}
