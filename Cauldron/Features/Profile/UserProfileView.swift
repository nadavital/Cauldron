//
//  UserProfileView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// User profile view - displays user information and manages connections
struct UserProfileView: View {
    let user: User
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: UserProfileViewModel
    @StateObject private var currentUserSession = CurrentUserSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditProfile = false
    @State private var hasLoadedInitialData = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]  // Cache recipe images by collection ID
    
    // External sharing
    @State private var shareLink: ShareableLink?
    @State private var isGeneratingShareLink = false

    // Tier & icons
    @State private var showTierRoadmap = false
    @State private var showAppIconPicker = false
    @StateObject private var appIconManager = AppIconManager.shared

    // Referral
    @StateObject private var referralManager = ReferralManager.shared
    @State private var codeCopied = false

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        _viewModel = State(initialValue: UserProfileViewModel(
            user: user,
            dependencies: dependencies
        ))
    }

    // Use the live current user from session if viewing own profile
    // This enables optimistic UI updates to show immediately
    private var displayUser: User {
        if viewModel.isCurrentUser, let currentUser = currentUserSession.currentUser {
            return currentUser
        }
        return user
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                profileHeader

                // Rewards & Progress Section (only for current user)
                if viewModel.isCurrentUser {
                    rewardsSection
                }

                // Connection Management Section
                if !viewModel.isCurrentUser {
                    connectionSection
                }

                // Collections Section (only show if user has collections OR still loading the first time)
                if !viewModel.userCollections.isEmpty || (viewModel.isLoadingCollections && !hasLoadedInitialData) {
                    collectionsSection
                }

                // Recipes Section
                recipesSection
            }
            .padding()
        }
        .navigationTitle(displayUser.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search recipes")
        .refreshable {
            collectionImageCache.removeAll()
            await viewModel.refreshProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            // Only refresh if viewing own profile
            if viewModel.isCurrentUser {
                collectionImageCache.removeAll()
                Task {
                    await viewModel.loadUserRecipes()
                }
            }
        }
        .onAppear {
            // Only load initial data once - the viewModel's cache will handle subsequent requests
            if !hasLoadedInitialData {
                hasLoadedInitialData = true
                Task {
                    await viewModel.loadConnectionStatus()
                    await viewModel.loadUserRecipes()
                    await viewModel.loadUserCollections()
                    if viewModel.isCurrentUser {
                        await viewModel.loadConnections()
                    }
                }
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingEditProfile) {
            ProfileEditView(dependencies: viewModel.dependencies)
        }
        .sheet(item: $shareLink) { link in
            ShareSheet(items: [link])
        }
        .sheet(isPresented: $showTierRoadmap) {
            TierRoadmapView(currentTier: viewModel.userTier, recipeCount: viewModel.userRecipeCount, dependencies: viewModel.dependencies)
        }
        .sheet(isPresented: $showAppIconPicker) {
            AppIconPickerView()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Only allow sharing if it's the current user's profile
                if viewModel.isCurrentUser {
                    Button {
                        shareWithFriends()
                    } label: {
                        Image(systemName: "gift")
                            .foregroundColor(.cauldronOrange)
                    }
                }
            }
        }
    }

    private var profileHeader: some View {
        HStack(alignment: .top, spacing: 16) {
            // Avatar
            ProfileAvatar(user: displayUser, size: 70, dependencies: viewModel.dependencies)

            // Info column
            VStack(alignment: .leading, spacing: 6) {
                // Name row with edit button
                HStack {
                    Text(displayUser.displayName)
                        .font(.title3)
                        .fontWeight(.bold)

                    Spacer()

                    if viewModel.isCurrentUser {
                        Button {
                            showingEditProfile = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title2)
                                .foregroundColor(.cauldronOrange)
                        }
                    }
                }

                // Username
                Text("@\(displayUser.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Tier badge and friends/connection row
                HStack(spacing: 12) {
                    // Tier badge - clickable for own profile to see roadmap
                    if viewModel.isCurrentUser {
                        Button {
                            showTierRoadmap = true
                        } label: {
                            TierBadgeView(tier: viewModel.userTier, style: .standard)
                        }
                    } else {
                        TierBadgeView(tier: viewModel.userTier, style: .standard)
                    }

                    if viewModel.isCurrentUser {
                        NavigationLink(destination: ConnectionsView(dependencies: viewModel.dependencies)) {
                            HStack(spacing: 4) {
                                Text("\(viewModel.connections.count) \(viewModel.connections.count == 1 ? "friend" : "friends")")
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .foregroundColor(.cauldronOrange)
                        }
                    } else {
                        connectionActionBadge
                    }
                }

                if viewModel.isCurrentUser {
                    referralQuickSection
                }
            }
        }
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    // MARK: - App Icons Section

    private var rewardsSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("App Icons")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button {
                    showAppIconPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("\(appIconManager.unlockedIcons.count)/\(appIconManager.availableIcons.count)")
                            .font(.caption)
                        Text("View All")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.cauldronOrange)
                }
            }

            // Horizontal scrolling icons with progress
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(appIconManager.availableIcons) { theme in
                        iconCellWithProgress(theme: theme)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(16)
    }

    private func iconCellWithProgress(theme: AppIconTheme) -> some View {
        let isSelected = appIconManager.currentTheme.id == theme.id
        let isUnlocked = appIconManager.isUnlocked(theme)
        let progress = iconUnlockProgress(for: theme)

        return Button {
            showAppIconPicker = true
        } label: {
            VStack(spacing: 6) {
                // Icon with overlay
                ZStack {
                    Image(iconPreviewAssetName(for: theme))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                        .cornerRadius(12)
                        .blur(radius: isUnlocked ? 0 : 3)
                        .opacity(isUnlocked ? 1.0 : 0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSelected ? Color.cauldronOrange : Color.clear, lineWidth: 2)
                        )

                    // Checkmark for selected
                    if isSelected {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.cauldronOrange)
                                    .background(Circle().fill(Color(.systemBackground)).padding(1))
                                    .offset(x: 4, y: 4)
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                }

                // Progress bar for locked icons
                if !isUnlocked {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.cauldronOrange)
                                .frame(width: geo.size.width * progress, height: 4)
                        }
                    }
                    .frame(width: 56, height: 4)
                } else {
                    // Spacer for consistent height
                    Color.clear.frame(width: 56, height: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Calculate progress towards unlocking an icon (0.0 to 1.0)
    private func iconUnlockProgress(for theme: AppIconTheme) -> Double {
        guard let unlock = IconUnlock.unlock(for: theme.id) else { return 1.0 }

        let required = unlock.requiredReferrals
        if required == 0 { return 1.0 }

        let current = referralManager.referralCount
        return min(1.0, Double(current) / Double(required))
    }

    private func shareWithFriends() {
        guard let user = currentUserSession.currentUser else { return }
        let shareURL = referralManager.getShareURL(for: user)
        let shareText = referralManager.getShareText(for: user)
        // Setting shareLink triggers the sheet via .sheet(item:)
        shareLink = ShareableLink(
            url: shareURL,
            previewText: shareText
        )
    }

    private var referralQuickSection: some View {
        Group {
            if let user = currentUserSession.currentUser {
                let code = referralManager.generateReferralCode(for: user)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Referral code")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundColor(.cauldronOrange)

                        Spacer()

                        Button {
                            UIPasteboard.general.string = code
                            withAnimation {
                                codeCopied = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    codeCopied = false
                                }
                            }
                        } label: {
                            Image(systemName: codeCopied ? "checkmark" : "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(codeCopied ? .green : .cauldronOrange)
                        }
                        .buttonStyle(.plain)
                    }

                    if codeCopied {
                        Text("Copied!")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                }
                .padding(.top, 2)
            }
        }
    }

    private func iconPreviewAssetName(for theme: AppIconTheme) -> String {
        switch theme.id {
        case "default":
            return "BrandMarks/CauldronIcon"
        case "wicked":
            return "IconPreviews/IconPreviewWicked"
        case "goodwitch":
            return "IconPreviews/IconPreviewGoodWitch"
        case "maleficent":
            return "IconPreviews/IconPreviewMaleficent"
        case "ursula":
            return "IconPreviews/IconPreviewUrsula"
        case "agatha":
            return "IconPreviews/IconPreviewAgatha"
        case "scarletwitch":
            return "IconPreviews/IconPreviewScarletWitch"
        case "lion":
            return "IconPreviews/IconPreviewLion"
        case "serpent":
            return "IconPreviews/IconPreviewSerpent"
        case "badger":
            return "IconPreviews/IconPreviewBadger"
        case "eagle":
            return "IconPreviews/IconPreviewEagle"
        default:
            return "BrandMarks/CauldronIcon"
        }
    }

    // MARK: - Connection Action Badge (interactive)

    @ViewBuilder
    private var connectionActionBadge: some View {
        if viewModel.isProcessing || viewModel.isLoadingConnectionState {
            ProgressView()
                .scaleEffect(0.8)
        } else {
            switch viewModel.connectionState {
            case .connected:
                // Friends badge - tap to show menu with remove option
                Menu {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeConnection()
                        }
                    } label: {
                        Label("Remove Friend", systemImage: "person.badge.minus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                        Text("Friends")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(8)
                }

            case .pendingOutgoing:
                // Pending badge - tap to cancel
                Menu {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.cancelConnectionRequest()
                        }
                    } label: {
                        Label("Cancel Request", systemImage: "xmark.circle")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .font(.caption)
                        Text("Pending")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }

            case .pendingIncoming:
                // Request received badge - shown in header, actions below
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.clock")
                        .font(.caption)
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(8)

            case .none:
                // Add Friend badge - tap to send request
                Button {
                    Task {
                        await viewModel.sendConnectionRequest()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.caption)
                        Text("Add Friend")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.cauldronOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cauldronOrange.opacity(0.15))
                    .cornerRadius(8)
                }

            case .syncing:
                ProgressView()
                    .scaleEffect(0.8)

            case .failed:
                Button {
                    Task {
                        await viewModel.loadConnectionStatus()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }

            case .currentUser:
                EmptyView()
            }
        }
    }

    // MARK: - Connection Section (only for pending received - needs Accept/Reject buttons)

    @ViewBuilder
    private var connectionSection: some View {
        if viewModel.connectionState == .pendingIncoming && !viewModel.isProcessing && !viewModel.isLoadingConnectionState {
            VStack(spacing: 12) {
                Text("\(user.displayName) wants to be friends")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.acceptConnection()
                        }
                    } label: {
                        Label("Accept", systemImage: "checkmark")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }

                    Button {
                        Task {
                            await viewModel.rejectConnection()
                        }
                    } label: {
                        Label("Decline", systemImage: "xmark")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.secondary.opacity(0.2))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .background(Color.cauldronSecondaryBackground)
            .cornerRadius(16)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                Text("Collections")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !viewModel.userCollections.isEmpty {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            // Content
            if viewModel.isLoadingCollections {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if viewModel.userCollections.isEmpty {
                emptyCollectionsState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.userCollections.prefix(10), id: \.id) { collection in
                            NavigationLink(destination: CollectionDetailView(
                                collection: collection,
                                dependencies: viewModel.dependencies
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
                }
            }
        }
    }

    private var emptyCollectionsState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: "folder")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.purple.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(viewModel.isCurrentUser ? "No Collections Yet" : "No Shared Collections")
                .font(.subheadline)
                .fontWeight(.medium)

            Text(viewModel.isCurrentUser ? "Create collections to organize recipes" : "\(user.displayName) hasn't shared any collections")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "book.fill")
                    .foregroundColor(.cauldronOrange)
                Text(viewModel.searchText.isEmpty ? "Recipes" : "Search Results")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !viewModel.filteredRecipes.isEmpty && viewModel.searchText.isEmpty {
                    NavigationLink(destination: AllProfileRecipesListView(
                        recipes: viewModel.filteredRecipes,
                        user: user,
                        dependencies: viewModel.dependencies
                    )) {
                        Text("See All")
                            .font(.subheadline)
                            .foregroundColor(.cauldronOrange)
                    }
                }
            }

            // Content
            if viewModel.isLoadingRecipes {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if viewModel.filteredRecipes.isEmpty {
                emptyRecipesState
            } else {
                if horizontalSizeClass == .regular {
                    LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                        ForEach(displayedRecipes, id: \.id) { sharedRecipe in
                            NavigationLink(destination: RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: viewModel.dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )) {
                                RecipeCardView(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    if viewModel.searchText.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ForEach(displayedRecipes, id: \.id) { sharedRecipe in
                                    NavigationLink(destination: RecipeDetailView(
                                        recipe: sharedRecipe.recipe,
                                        dependencies: viewModel.dependencies,
                                        sharedBy: sharedRecipe.sharedBy,
                                        sharedAt: sharedRecipe.sharedAt
                                    )) {
                                        RecipeCardView(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        // List view for search results (matches Search tab style)
                        VStack(spacing: 12) {
                            ForEach(viewModel.filteredRecipes, id: \.id) { sharedRecipe in
                                NavigationLink(destination: RecipeDetailView(
                                    recipe: sharedRecipe.recipe,
                                    dependencies: viewModel.dependencies,
                                    sharedBy: sharedRecipe.sharedBy,
                                    sharedAt: sharedRecipe.sharedAt
                                )) {
                                    RecipeRowView(recipe: sharedRecipe.recipe, dependencies: viewModel.dependencies)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    private var displayedRecipes: [SharedRecipe] {
        if viewModel.searchText.isEmpty {
            return Array(viewModel.filteredRecipes.prefix(10))
        }
        return viewModel.filteredRecipes
    }

    private var emptyRecipesState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.cauldronOrange.opacity(0.2), Color.cauldronOrange.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)

                Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.cauldronOrange, Color.cauldronOrange.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text(emptyStateMessage)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)

            if viewModel.searchText.isEmpty && !viewModel.isCurrentUser && viewModel.connectionState != .connected {
                Text("Connect with \(user.displayName) to see their recipes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No recipes match '\(viewModel.searchText)'"
        } else if viewModel.isCurrentUser {
            return "You haven't saved any recipes yet"
        } else if viewModel.connectionState == .connected {
            return "\(user.displayName) hasn't shared any recipes yet"
        } else {
            return "No Public Recipes"
        }
    }

    private func generateShareLink() async {
        isGeneratingShareLink = true
        defer { isGeneratingShareLink = false }

        do {
            // Count public recipes
            let publicRecipeCount = viewModel.userRecipes.filter { $0.recipe.visibility == .publicRecipe }.count
            
            let link = try await viewModel.dependencies.externalShareService.shareProfile(
                user,
                recipeCount: publicRecipeCount
            )
            shareLink = link
        } catch {
            AppLogger.general.error("Failed to generate profile share link: \(error.localizedDescription)")
            viewModel.errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }
}

// MARK: - All Profile Recipes List View

struct AllProfileRecipesListView: View {
    let recipes: [SharedRecipe]
    let user: User
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
        .navigationTitle("\(user.displayName)'s Recipes")
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

#Preview {
    NavigationStack {
        UserProfileView(
            user: User(username: "chef_julia", displayName: "Julia Child"),
            dependencies: .preview()
        )
    }
}
