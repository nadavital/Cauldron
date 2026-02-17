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

/// Friends tab - showing shared recipes and connections
struct FriendsTabView: View {
    @Bindable private var viewModel = FriendsTabViewModel.shared
    @ObservedObject private var userSession = CurrentUserSession.shared
    @State private var navigationPath = NavigationPath()
    @State private var showingProfileSheet = false
    @State private var showingPeopleSearch = false
    @State private var showingInviteSheet = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]

    let dependencies: DependencyContainer

    init(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    var body: some View {
        compactView
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
            AppLogger.general.info("📍 Navigating to Connections from notification")
            handleConnectionsNavigation()
        }
    }

    private var compactView: some View {
        NavigationStack(path: $navigationPath) {
            combinedFeedSection
                .navigationTitle("Friends")
                .toolbar { friendsToolbar }
                .refreshable {
                    await refreshFriendsContent()
                }
                .navigationDestination(for: FriendsTabDestination.self) { destination in
                    switch destination {
                    case .connections:
                        ConnectionsView(dependencies: dependencies)
                    }
                }
        }
    }

    @ToolbarContentBuilder
    private var friendsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if let user = userSession.currentUser {
                Button {
                    showingProfileSheet = true
                } label: {
                    ProfileAvatar(user: user, size: 32, dependencies: dependencies)
                }
            }
        }
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
        navigationPath = NavigationPath()
        navigationPath.append(FriendsTabDestination.connections)
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
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(
                            Color.cauldronOrange.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 5])
                        )
                        .frame(width: 52, height: 52)

                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.cauldronOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite Friends")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("Share your link and unlock referral rewards together.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(14)
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
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
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
                            RecipeCardView(
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
                            RecipeCardView(
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
                            RecipeCardView(
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

    private var allCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                Text("Friends' Collections")
                    .font(.title2)
                    .fontWeight(.bold)
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
                HStack(spacing: 16) {
                    ForEach(viewModel.sharedCollections.prefix(10), id: \.id) { collection in
                        NavigationLink(destination: SharedCollectionDetailView(
                            collection: collection,
                            dependencies: dependencies
                        )) {
                            CollectionCardView(
                                collection: collection,
                                recipeImages: collectionImageCache[collection.id] ?? []
                            )
                        }
                        .buttonStyle(.plain)
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
        .navigationTitle(title)
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
                    sharedBy: sharedRecipe.sharedBy,
                    sharedAt: sharedRecipe.sharedAt
                )) {
                    SharedRecipeRowView(sharedRecipe: sharedRecipe, dependencies: dependencies)
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

struct AllFriendsCollectionsListView: View {
    let collections: [Collection]
    let dependencies: DependencyContainer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var collectionImageCache: [UUID: [URL?]] = [:]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(collections, id: \.id) { collection in
                    NavigationLink(destination: SharedCollectionDetailView(
                        collection: collection,
                        dependencies: dependencies
                    )) {
                        CollectionCardView(
                            collection: collection,
                            recipeImages: collectionImageCache[collection.id] ?? [],
                            preferredWidth: nil
                        )
                    }
                    .buttonStyle(.plain)
                    .task(id: collection.id) {
                        if collectionImageCache[collection.id] == nil {
                            let images = await loadRecipeImages(for: collection)
                            collectionImageCache[collection.id] = images
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Friends' Collections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 12)]
        }
        return [
            GridItem(.flexible(minimum: 150), spacing: 12),
            GridItem(.flexible(minimum: 150), spacing: 12)
        ]
    }

    @MainActor
    private func loadRecipeImages(for collection: Collection) async -> [URL?] {
        let loader = SharedCollectionLoader(dependencies: dependencies)
        let loadResult = await loader.loadRecipes(
            from: collection,
            viewerId: CurrentUserSession.shared.userId
        )
        return Array(loadResult.visibleRecipes.prefix(4).map(\.imageURL))
    }
}

struct InviteFriendsSheetView: View {
    let dependencies: DependencyContainer

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var currentUserSession = CurrentUserSession.shared
    @StateObject private var referralManager = ReferralManager.shared

    @State private var shareLink: ShareableLink?
    @State private var copiedCode = false
    @State private var referredUsers: [User] = []
    @State private var isLoadingReferredUsers = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedMeshGradient()
                    .ignoresSafeArea()

                Color.cauldronBackground.opacity(0.35)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        heroSection
                        actionSection
                        invitesAndRewardsSection
                    }
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $shareLink) { link in
                ShareSheet(items: [link])
            }
            .task(id: currentUserSession.currentUser?.id) {
                referralManager.configure(
                    userCloudService: dependencies.userCloudService,
                    connectionCloudService: dependencies.connectionCloudService
                )
                await loadReferredUsers()
            }
        }
    }

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color.cauldronOrange.opacity(0.3), Color.cauldronOrange.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 8) {
                Label("Invite Friends to Cauldron", systemImage: "person.3.fill")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Send one tap invite links that auto-apply your code and connect you as friends.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 164, alignment: .bottomLeading)
        .overlay(alignment: .topTrailing) {
            Image("BrandMarks/CauldronIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .opacity(0.22)
                .padding(14)
        }
        .clipShape(.rect(cornerRadius: 22))
    }

    private var invitesAndRewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.wave.2.fill")
                    .foregroundColor(.cauldronOrange)
                Text("Invites & Rewards")
                    .font(.headline)
            }

            Text("Rewards Progress")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if let nextUnlock = referralManager.nextIconToUnlock {
                let target = max(1, nextUnlock.requiredReferrals)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            "\(referralManager.referralCount) referral join\(referralManager.referralCount == 1 ? "" : "s")",
                            systemImage: "person.2.fill"
                        )
                        .font(.subheadline.weight(.semibold))

                        Spacer()

                        Text("\(min(referralManager.referralCount, target))/\(target)")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }

                    ProgressView(
                        value: Double(min(referralManager.referralCount, target)),
                        total: Double(target)
                    )
                    .tint(.cauldronOrange)

                    let remaining = max(0, nextUnlock.requiredReferrals - referralManager.referralCount)
                    Text("\(remaining) more to unlock '\(nextUnlock.iconId)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Label("All referral icon rewards unlocked.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Divider()
                .overlay(Color.secondary.opacity(0.2))
                .padding(.vertical, 2)

            Text("People You Invited")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            if isLoadingReferredUsers {
                ProgressView("Loading invites...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if referredUsers.isEmpty {
                Text("No one has joined from your invite yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(referredUsers.prefix(8)) { user in
                        HStack(spacing: 10) {
                            ProfileAvatar(user: user, size: 34, dependencies: dependencies)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("@\(user.username)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                        .padding(10)
                        .background(Color.cauldronBackground.opacity(0.8))
                        .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .clipShape(.rect(cornerRadius: 18))
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Invite Tools")
                    .font(.headline)
                Spacer()
            }

            if let user = currentUserSession.currentUser {
                let referralCode = referralManager.generateReferralCode(for: user)
                let inviteURL = referralManager.getShareURL(for: user)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Referral Code")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 10) {
                            Text(referralCode)
                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Spacer()

                            Button {
                                UIPasteboard.general.string = referralCode
                                copiedCode = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    copiedCode = false
                                }
                            } label: {
                                Label(copiedCode ? "Copied" : "Copy", systemImage: copiedCode ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(12)
                        .background(Color.cauldronBackground)
                        .clipShape(.rect(cornerRadius: 14))
                    }

                    Button {
                        shareLink = ShareableLink(
                            url: inviteURL,
                            previewText: referralManager.getShareText(for: user),
                            image: nil
                        )
                    } label: {
                        Label("Invite Friends", systemImage: "square.and.arrow.up.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)
                }
            } else {
                Label("Sign in to generate your invite link.", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .clipShape(.rect(cornerRadius: 18))
    }

    @MainActor
    private func loadReferredUsers() async {
        guard let currentUser = currentUserSession.currentUser else {
            referredUsers = []
            return
        }

        isLoadingReferredUsers = true
        defer { isLoadingReferredUsers = false }

        do {
            referredUsers = try await dependencies.userCloudService.fetchReferredUsers(for: currentUser.id, limit: 40)
        } catch {
            AppLogger.general.warning("Failed to load referred users for invite sheet: \(error.localizedDescription)")
            referredUsers = []
        }
    }
}

#Preview {
    FriendsTabView(dependencies: .preview())
}
