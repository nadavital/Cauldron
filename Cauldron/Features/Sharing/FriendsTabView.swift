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
    case profile(User)
}

/// Friends tab - showing shared recipes and connections
struct FriendsTabView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable private var viewModel = FriendsTabViewModel.shared
    @ObservedObject private var userSession = CurrentUserSession.shared
    @State private var navigationPath = NavigationPath()
    @State private var sidebarSelection: FriendsTabDestination?
    @State private var showingProfileSheet = false
    @State private var showingPeopleSearch = false
    @State private var showingInviteSheet = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]
    @Namespace private var recipeTransition

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var body: some View {
        contentView
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
        .sheet(isPresented: $showingInviteSheet) {
            InviteFriendsSheetView(dependencies: dependencies)
        }
        .task {
            // Configure dependencies if not already done
            viewModel.configure(dependencies: dependencies)
            await viewModel.loadSharedRecipes()
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
        .onReceive(NotificationCenter.default.publisher(for: .navigateToConnections)) { _ in
            AppLogger.general.info("📍 Navigating to Connections from notification")
            handleConnectionsNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReferralProfile)) { notification in
            guard let userId = notification.object as? UUID else { return }
            AppLogger.general.info("📍 Navigating to referral friend's profile from notification: \(userId)")
            Task {
                await handleReferralProfileNavigation(userId: userId)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if horizontalSizeClass == .regular {
            regularView
        } else {
            compactView
        }
    }

    private var compactView: some View {
        NavigationStack(path: $navigationPath) {
            combinedFeedSection
                .navigationTitle("Friends")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar { friendsToolbar }
                .refreshable {
                    await refreshFriendsContent()
                }
                .navigationDestination(for: FriendsTabDestination.self) { destination in
                    switch destination {
                    case .connections:
                        ConnectionsView(dependencies: dependencies)
                    case .profile(let user):
                        UserProfileView(user: user, dependencies: dependencies)
                    }
                }
        }
    }

    private var regularView: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Section("Friends") {
                    Button {
                        sidebarSelection = nil
                    } label: {
                        Label("Shared Recipes", systemImage: "book.fill")
                    }

                    NavigationLink(value: FriendsTabDestination.connections) {
                        Label("Connections", systemImage: "person.2.fill")
                    }

                    Button {
                        showingInviteSheet = true
                    } label: {
                        Label("Invite Friends", systemImage: "gift.fill")
                    }

                    Button {
                        showingPeopleSearch = true
                    } label: {
                        Label("Find People", systemImage: "person.badge.plus")
                    }
                }
            }
            .navigationTitle("Friends")
                .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let user = userSession.currentUser {
                        Button {
                            sidebarSelection = .profile(user)
                        } label: {
                            ProfileAvatar(user: user, size: 32, dependencies: dependencies)
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        } detail: {
            NavigationStack(path: $navigationPath) {
                regularDetailContent
                    .navigationDestination(for: FriendsTabDestination.self) { destination in
                        switch destination {
                        case .connections:
                            ConnectionsView(dependencies: dependencies)
                        case .profile(let user):
                            UserProfileView(user: user, dependencies: dependencies)
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var regularDetailContent: some View {
        switch sidebarSelection {
        case .connections:
            ConnectionsView(dependencies: dependencies)
                .navigationTitle("Connections")
        case .profile(let user):
            UserProfileView(user: user, dependencies: dependencies)
        case nil:
            combinedFeedSection
                .frame(maxWidth: 980, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .top)
                .navigationTitle("Friends")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar { friendsToolbar }
                .refreshable {
                    await refreshFriendsContent()
                }
        }
    }

    @ToolbarContentBuilder
    private var friendsToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showingInviteSheet = true
            } label: {
                Label("Invite", systemImage: "gift.fill")
            }

            Button {
                showingPeopleSearch = true
            } label: {
                Image(systemName: "plus")
            }

            if let user = userSession.currentUser {
                Button {
                    showingProfileSheet = true
                } label: {
                    ProfileAvatar(user: user, size: 30, dependencies: dependencies)
                }
            }
        }
    }

    private func refreshFriendsContent() async {
        collectionImageCache.removeAll()

        // Force refresh shared recipes from CloudKit
        await viewModel.loadSharedRecipes(forceRefresh: true)

        // Also refresh friends list by posting notification
        NotificationCenter.default.post(name: .refreshConnections, object: nil)
    }

    private func handleConnectionsNavigation() {
        if horizontalSizeClass == .regular {
            sidebarSelection = .connections
        } else {
            navigationPath = NavigationPath()
            navigationPath.append(FriendsTabDestination.connections)
        }
    }

    private func handleReferralProfileNavigation(userId: UUID) async {
        // First try local cache for immediate navigation.
        if let cachedUser = try? await dependencies.sharingRepository.fetchUser(id: userId) {
            navigateToProfile(cachedUser)
            return
        }

        // Fall back to CloudKit if user details aren't cached yet.
        do {
            if let cloudUser = try await dependencies.userCloudService.fetchUser(byUserId: userId) {
                await bestEffort("Cache referral friend profile") {
                    try await dependencies.sharingRepository.save(cloudUser)
                }
                navigateToProfile(cloudUser)
                return
            }
        } catch {
            AppLogger.general.warning("⚠️ Failed to load referral friend profile: \(error.localizedDescription)")
        }

        // If profile data isn't available yet, still open Connections.
        handleConnectionsNavigation()
    }

    private func navigateToProfile(_ user: User) {
        if horizontalSizeClass == .regular {
            sidebarSelection = .profile(user)
        } else {
            navigationPath = NavigationPath()
            navigationPath.append(FriendsTabDestination.profile(user))
        }
    }

    private var combinedFeedSection: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.md) {
                // Friends section
                GlassEffectContainer(spacing: 2) {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Friends", icon: "person.2.fill", color: .green)

                        ConnectionsInlineView(dependencies: dependencies)
                            .padding(.bottom, 8)
                    }
                    .glassCard(cornerRadius: 16)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                inviteInlineCard

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

                if !viewModel.isLoading && !viewModel.sharedCollections.isEmpty {
                    allCollectionsSection
                }
            }
        }
        .background(Color.cauldronBackground.ignoresSafeArea())
    }

    private var inviteInlineCard: some View {
        Button {
            showingInviteSheet = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cauldronOrange)
                    .frame(width: 32, height: 32)
                    .background(Color.cauldronOrange.opacity(0.12), in: Circle())

                Text("Invite friends & unlock rewards")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.cauldronOrange.opacity(0.12), Color.cauldronSecondaryBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.cauldronOrange.opacity(0.28), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.horizontal, 16)
    }

    private var emptyRecipesState: some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Friends' Recipes", icon: "book.fill", color: .cauldronOrange)

            VStack(spacing: Theme.Spacing.md) {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeaderLabel(title: "Recently Added", systemImage: "clock.arrow.circlepath")
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.recentlyAdded.prefix(10)) { sharedRecipe in
                        let transitionID = "friends-recent-\(sharedRecipe.recipe.id.uuidString)"
                        NavigationLink {
                            RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )
                            .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                        } label: {
                            RecipeCardView(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(PressableScaleStyle())
                        .matchedTransitionSource(id: transitionID, in: recipeTransition)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func tagSectionView(tag: String, recipes: [SharedRecipe]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeaderLabel(title: tag, systemImage: "tag.fill")
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
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(recipes.prefix(10)) { sharedRecipe in
                        let transitionID = "friends-tag-\(tag)-\(sharedRecipe.recipe.id.uuidString)"
                        NavigationLink {
                            RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )
                            .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                        } label: {
                            RecipeCardView(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(PressableScaleStyle())
                        .matchedTransitionSource(id: transitionID, in: recipeTransition)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var allRecipesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeaderLabel(title: "All Friends' Recipes", systemImage: "book.fill")
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
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.sharedRecipes.prefix(10)) { sharedRecipe in
                        let transitionID = "friends-all-\(sharedRecipe.recipe.id.uuidString)"
                        NavigationLink {
                            RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )
                            .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                        } label: {
                            RecipeCardView(
                                sharedRecipe: sharedRecipe,
                                creatorTier: viewModel.sharerTiers[sharedRecipe.sharedBy.id],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(PressableScaleStyle())
                        .matchedTransitionSource(id: transitionID, in: recipeTransition)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var allCollectionsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeaderLabel(title: "Friends' Collections", systemImage: "folder.fill", iconColor: .purple)
                Spacer()

                NavigationLink(destination: AllFriendsCollectionsListView(
                    collections: viewModel.sharedCollections,
                    dependencies: dependencies
                )) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(viewModel.sharedCollections.prefix(10), id: \.id) { collection in
                        NavigationLink(destination: CollectionDetailView(
                            collection: collection,
                            dependencies: dependencies
                        )) {
                            CollectionCardView(
                                collection: collection,
                                recipeImages: collectionImageCache[collection.id] ?? [],
                                dependencies: dependencies
                            )
                        }
                        .buttonStyle(PressableScaleStyle())
                        .task(id: collection.id) {
                            if collectionImageCache[collection.id] == nil {
                                let images = await viewModel.getRecipeImages(for: collection)
                                collectionImageCache[collection.id] = images
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

}

#Preview {
    FriendsTabView(dependencies: .preview())
}
