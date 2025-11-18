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
    @ObservedObject private var viewModel = FriendsTabViewModel.shared
    @StateObject private var userSession = CurrentUserSession.shared
    @State private var navigationPath = NavigationPath()
    @State private var selectedSection: FriendsTabSection = .recipes

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            combinedFeedSection
            .navigationTitle("Friends")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let user = userSession.currentUser {
                        NavigationLink(destination: UserProfileView(user: user, dependencies: dependencies)) {
                            Image(systemName: "person.fill")
                        }
                    }
                }
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
                NotificationCenter.default.post(name: NSNotification.Name("RefreshConnectionsList"), object: nil)
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

                // Shared collections section (only show if there are collections)
                if !viewModel.sharedCollections.isEmpty {
                    sharedCollectionsSection
                }

                // Shared recipes section
                VStack(spacing: 0) {
                    SectionHeader(title: "Friends' Recipes", icon: "book.fill", color: .cauldronOrange)

                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView("Loading shared recipes...")
                                .padding(.vertical, 40)
                            Spacer()
                        }
                    } else if viewModel.sharedRecipes.isEmpty {
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
                    } else {
                        ForEach(viewModel.sharedRecipes) { sharedRecipe in
                            NavigationLink(destination: RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )) {
                                SharedRecipeRowView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                                    .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)

                            if sharedRecipe.id != viewModel.sharedRecipes.last?.id {
                                Divider()
                                    .padding(.leading, 102)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .background(Color.cauldronSecondaryBackground)
                .cornerRadius(16)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color.cauldronBackground.ignoresSafeArea())
    }

    private var sharedCollectionsSection: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Shared Collections", icon: "folder.fill", color: .purple)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.sharedCollections) { collection in
                        NavigationLink {
                            SharedCollectionDetailView(
                                collection: collection,
                                dependencies: dependencies
                            )
                        } label: {
                            SharedCollectionCard(collection: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
        .padding(.horizontal, 16)
    }

    private var recipesSection: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading shared recipes...")
            } else if viewModel.sharedRecipes.isEmpty {
                emptyState
            } else {
                recipesList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Friends' Recipes")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add friends to see their shared recipes here")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            #if DEBUG
            Text("Tap the menu to create demo users for testing")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            #endif
        }
        .padding()
    }
    
    private var recipesList: some View {
        List {
            ForEach(viewModel.sharedRecipes) { sharedRecipe in
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
    }
}

/// Row view for a shared recipe with enhanced visuals
struct SharedRecipeRowView: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer

    var body: some View {
        HStack(spacing: 14) {
            // Recipe Image
            RecipeImageView(thumbnailImageURL: sharedRecipe.recipe.imageURL, recipeImageService: dependencies.recipeImageService)

            VStack(alignment: .leading, spacing: 8) {
                // Title
                Text(sharedRecipe.recipe.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.tail)

                // Shared by info
                HStack(spacing: 6) {
                    ProfileAvatar(user: sharedRecipe.sharedBy, size: 20)

                    Text(sharedRecipe.sharedBy.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)

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
    @StateObject private var viewModel: ConnectionsViewModel
    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ConnectionsViewModel(dependencies: dependencies))
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshConnectionsList"))) { _ in
            Task {
                await viewModel.loadConnections(forceRefresh: true)
            }
        }
    }
}

// MARK: - Shared Collection Card

struct SharedCollectionCard: View {
    let collection: Collection

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(selectedColor.opacity(0.15))
                    .frame(width: 60, height: 60)

                if let emoji = collection.emoji {
                    Text(emoji)
                        .font(.system(size: 32))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundColor(selectedColor)
                }
            }

            // Collection name
            Text(collection.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 80)

            // Recipe count
            Text("\(collection.recipeCount) recipes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var selectedColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .purple
        }
        return .purple
    }
}

#Preview {
    FriendsTabView(dependencies: .preview())
}
