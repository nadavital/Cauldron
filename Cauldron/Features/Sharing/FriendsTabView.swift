//
//  SharingTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

/// Navigation destinations for FriendsTab
enum FriendsTabDestination: Hashable {
    case connections
}

/// Sections in the Friends tab
enum FriendsTabSection: String, CaseIterable {
    case recipes = "Recipes"
    case connections = "Connections"
}

/// Friends tab - showing shared recipes and connections
struct FriendsTabView: View {
    @Bindable private var viewModel = FriendsTabViewModel.shared
    @ObservedObject private var userSession = CurrentUserSession.shared
    @State private var navigationPath = NavigationPath()
    @State private var selectedSection: FriendsTabSection = .recipes
    @State private var showingProfileSheet = false
    @State private var showingPeopleSearch = false

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            combinedFeedSection
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let user = userSession.currentUser {
                        Button {
                            showingProfileSheet = true
                        } label: {
                            ProfileAvatar(user: user, size: 32, dependencies: dependencies)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingPeopleSearch = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingProfileSheet) {
                NavigationStack {
                    if let user = userSession.currentUser {
                        UserProfileView(user: user, dependencies: dependencies)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingProfileSheet = false }
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showingPeopleSearch) {
                PeopleSearchSheet(dependencies: dependencies)
            }
            .task {
                // Configure dependencies if not already done
                viewModel.configure(dependencies: dependencies)
                await viewModel.loadSharedRecipes()
            }
            .refreshable {
                // Refresh shared recipes and collections
                await viewModel.loadSharedRecipes()

                // Also refresh friends list by posting notification
                NotificationCenter.default.post(name: .refreshConnections, object: nil)
            }
            .alert("Success", isPresented: $viewModel.showSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(viewModel.alertMessage)
            }
            .navigationDestination(for: FriendsTabDestination.self) { destination in
                switch destination {
                case .connections:
                    ConnectionsView(dependencies: dependencies)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
                // Navigate to connections when notification is tapped
                AppLogger.general.info("📍 Navigating to Connections from notification")
                selectedSection = .connections
            }
        }
    }

    private var combinedFeedSection: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Friends section
                VStack(spacing: 0) {
                    SectionHeader(title: "Friends", icon: "person.2.fill", color: .green)

                    ConnectionsInlineView(dependencies: dependencies)
                        .padding(.bottom, 8)
                }
                .background(Color.cauldronSecondaryBackground)
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if viewModel.isLoading {
                    ProgressView("Loading recipes...")
                        .padding(.vertical, 40)
                } else if viewModel.sharedRecipes.isEmpty {
                    emptyRecipesState
                } else {
                    // Recently Added Section
                    if !viewModel.recentlyAdded.isEmpty {
                        recentlyAddedSection
                    }

                    // Tag-based sections
                    ForEach(viewModel.tagSections, id: \.tag) { section in
                        tagSectionView(tag: section.tag, recipes: section.recipes)
                    }

                    // All Friends' Recipes Section (horizontal scroll)
                    allRecipesSection
                }
            }
        }
        .background(Color.cauldronBackground.ignoresSafeArea())
    }

    private var emptyRecipesState: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Friends' Recipes", icon: "book.fill", color: .cauldronOrange)

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cauldronOrange.opacity(0.2), Color.cauldronOrange.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cauldronOrange, Color.cauldronOrange.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("No Friends' Recipes Yet")
                    .font(.headline)

                Text("Add friends and their shared recipes\nwill appear here")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 50)
        }
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.cauldronOrange)
                Text("Recently Added")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.recentlyAdded.prefix(10)) { sharedRecipe in
                        NavigationLink(destination: RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy,
                            sharedAt: sharedRecipe.sharedAt
                        )) {
                            SocialRecipeCard(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func tagSectionView(tag: String, recipes: [SharedRecipe]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.cauldronOrange)
                Text(tag)
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                NavigationLink(destination: AllFriendsRecipesListView(
                    recipes: recipes,
                    title: tag,
                    dependencies: dependencies
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(recipes.prefix(10)) { sharedRecipe in
                        NavigationLink(destination: RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy,
                            sharedAt: sharedRecipe.sharedAt
                        )) {
                            SocialRecipeCard(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var allRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.cauldronOrange)
                Text("All Friends' Recipes")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                NavigationLink(destination: AllFriendsRecipesListView(
                    recipes: viewModel.sharedRecipes,
                    title: "All Friends' Recipes",
                    dependencies: dependencies
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.sharedRecipes.prefix(10)) { sharedRecipe in
                        NavigationLink(destination: RecipeDetailView(
                            recipe: sharedRecipe.recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy,
                            sharedAt: sharedRecipe.sharedAt
                        )) {
                            SocialRecipeCard(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

}

/// Row view for a shared recipe with enhanced visuals (used in list view)
struct SharedRecipeRowView: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer
    var ownerTier: UserTier? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Recipe Image
            RecipeImageView(thumbnailForRecipe: sharedRecipe.recipe, recipeImageService: dependencies.recipeImageService)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(sharedRecipe.recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                // Shared by info with tier badge
                HStack(spacing: 6) {
                    ProfileAvatar(user: sharedRecipe.sharedBy, size: 20, dependencies: dependencies)

                    Text(sharedRecipe.sharedBy.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Tier badge (compact)
                    if let tier = ownerTier {
                        TierBadgeView(tier: tier, style: .compact)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(sharedRecipe.sharedAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Time and tags
                HStack(spacing: 8) {
                    if let time = sharedRecipe.recipe.displayTime {
                        Label(time, systemImage: "clock.fill")
                            .font(.caption2)
                            .foregroundColor(.cauldronOrange)
                    }

                    if !sharedRecipe.recipe.tags.isEmpty {
                        ForEach(sharedRecipe.recipe.tags.prefix(2), id: \.name) { tag in
                            Text(tag.name)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cauldronOrange.opacity(0.15))
                                .foregroundColor(.cauldronOrange)
                                .cornerRadius(4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
}


// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)

            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Inline Connections View

struct ConnectionsInlineView: View {
    @State private var viewModel: ConnectionsViewModel
    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        _viewModel = State(initialValue: ConnectionsViewModel(dependencies: dependencies))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Pending requests (most important - shown first)
            if !viewModel.receivedRequests.isEmpty {
                ForEach(viewModel.receivedRequests.prefix(3), id: \.id) { connection in
                    if let user = viewModel.usersMap[connection.fromUserId] {
                        ConnectionRequestCard(
                            user: user,
                            connection: connection,
                            dependencies: dependencies,
                            onAccept: {
                                await viewModel.acceptRequest(connection)
                            },
                            onReject: {
                                await viewModel.rejectRequest(connection)
                            }
                        )
                    }
                }

                if viewModel.receivedRequests.count > 3 {
                    NavigationLink(destination: ConnectionsView(dependencies: dependencies)) {
                        Text("View \(viewModel.receivedRequests.count - 3) more requests")
                            .font(.caption)
                            .foregroundColor(.cauldronOrange)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                    }
                }
            }

            // Friends display
            if viewModel.connections.isEmpty && viewModel.receivedRequests.isEmpty && viewModel.sentRequests.isEmpty {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "person.2.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.5))

                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Removed redundant link to SearchTabView
                    Text("Find people to add")
                        .font(.caption)
                        .foregroundColor(.cauldronOrange)
                        .onTapGesture {
                            // Ideally switch tab, but for now just show text
                            // Or use a notification to switch tab
                            NotificationCenter.default.post(name: NSNotification.Name("SwitchToSearchTab"), object: nil)
                        }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                // Horizontal scrolling friends
                if !viewModel.connections.isEmpty {
                    HStack {
                        Spacer()

                        NavigationLink(destination: ConnectionsView(dependencies: dependencies)) {
                            Text("See All")
                                .font(.subheadline)
                                .foregroundColor(.cauldronOrange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.connections.prefix(10), id: \.id) { connection in
                                if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                                   let user = viewModel.usersMap[otherUserId] {
                                    ConnectionAvatarCard(user: user, dependencies: dependencies)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                }
            }
        }
        .task {
            await viewModel.loadConnections()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshConnections)) { _ in
            Task {
                await viewModel.loadConnections(forceRefresh: true)
            }
        }
    }
}

// MARK: - All Friends' Recipes List View

/// Full list view for friends' recipes (accessed via "See All")
struct AllFriendsRecipesListView: View {
    let recipes: [SharedRecipe]
    let title: String
    let dependencies: DependencyContainer

    var body: some View {
        List {
            ForEach(recipes) { sharedRecipe in
                NavigationLink(destination: RecipeDetailView(
                    recipe: sharedRecipe.recipe,
                    dependencies: dependencies,
                    sharedBy: sharedRecipe.sharedBy,
                    sharedAt: sharedRecipe.sharedAt
                )) {
                    SharedRecipeRowView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    FriendsTabView(dependencies: .preview())
}
