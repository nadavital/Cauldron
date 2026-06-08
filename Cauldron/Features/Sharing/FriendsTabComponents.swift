//
//  FriendsTabComponents.swift
//  Cauldron
//
//  Extracted from FriendsTabView.swift: shared row/header/inline components.
//

import SwiftUI
import os

struct SharedRecipeRowView: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer
    var ownerTier: UserTier? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Recipe Image
            RecipeImageView(thumbnailForRecipe: sharedRecipe.recipe, recipeImageService: dependencies.recipeImageService)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
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
                HStack(spacing: Theme.Spacing.xs) {
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
        HStack(spacing: Theme.Spacing.xs) {
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
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

// MARK: - Inline Connections View

struct ConnectionsInlineView: View {
    @State private var viewModel: ConnectionsViewModel
    let dependencies: DependencyContainer
    var onAddFriend: (() -> Void)?

    init(dependencies: DependencyContainer, onAddFriend: (() -> Void)? = nil) {
        self.dependencies = dependencies
        self.onAddFriend = onAddFriend
        _viewModel = State(initialValue: ConnectionsViewModel(dependencies: dependencies))
    }

    /// Dashed "+" tile that opens the add-friends flow, shown at the start of
    /// the friends row (replaces the toolbar "+" button).
    private var addFriendTile: some View {
        Button {
            onAddFriend?()
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .strokeBorder(
                            Color.cauldronOrange.opacity(0.8),
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.cauldronOrange)
                        )

                    // Pending-request count badge
                    if !viewModel.receivedRequests.isEmpty {
                        Text("\(viewModel.receivedRequests.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.red, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                Text(viewModel.receivedRequests.isEmpty ? "Add" : "Requests")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PressableScaleStyle())
        .accessibilityLabel(viewModel.receivedRequests.isEmpty ? "Add friends" : "\(viewModel.receivedRequests.count) friend requests and add friends")
    }

    private var hasAnyConnectionsActivity: Bool {
        !viewModel.connections.isEmpty || !viewModel.receivedRequests.isEmpty || !viewModel.sentRequests.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Top row: See All (right)
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
                .padding(.top, 12)
            }

            // Content
            if !hasAnyConnectionsActivity {
                emptyConnectionsState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.md) {
                        if onAddFriend != nil {
                            addFriendTile
                        }
                        ForEach(viewModel.connections.prefix(10), id: \.id) { connection in
                            if let otherUserId = connection.otherUserId(currentUserId: viewModel.currentUserId),
                               let user = viewModel.usersMap[otherUserId] {
                                ConnectionAvatarCard(user: user, dependencies: dependencies)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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

    private var emptyConnectionsState: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 36))
                .foregroundColor(.gray.opacity(0.5))

            Text("No friends yet")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Find people to add")
                .font(.caption)
                .foregroundColor(.cauldronOrange)
                .onTapGesture {
                    if let onAddFriend {
                        onAddFriend()
                    } else {
                        NotificationCenter.default.post(name: NSNotification.Name("SwitchToSearchTab"), object: nil)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

}
