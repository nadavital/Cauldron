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
