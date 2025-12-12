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
    @StateObject private var viewModel: UserProfileViewModel
    @StateObject private var currentUserSession = CurrentUserSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditProfile = false
    @State private var hasLoadedInitialData = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]  // Cache recipe images by collection ID
    
    // External sharing
    @State private var showShareSheet = false
    @State private var shareLink: ShareableLink?
    @State private var isGeneratingShareLink = false

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(
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
            VStack(spacing: 24) {
                // Profile Header
                profileHeader

                // Friend View Indicator (only for current user)
                if viewModel.isCurrentUser {
                    friendViewIndicator
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
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $viewModel.searchText, prompt: "Search recipes")
        .refreshable {
            await viewModel.refreshProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            // Only refresh if viewing own profile
            if viewModel.isCurrentUser {
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
        .sheet(isPresented: $showShareSheet) {
            if let link = shareLink {
                ShareSheet(items: [link])
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Only allow sharing if it's the current user's profile
                if viewModel.isCurrentUser {
                    Button {
                        Task {
                            await generateShareLink()
                        }
                    } label: {
                        if isGeneratingShareLink {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingShareLink)
                }
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ProfileAvatar(user: displayUser, size: 100, dependencies: viewModel.dependencies)

            // Display Name
            Text(displayUser.displayName)
                .font(.title2)
                .fontWeight(.bold)

            // Username, Friends Count, and Connection Status Badge
            VStack(spacing: 8) {
                Text("@\(displayUser.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Friends count for current user
                if viewModel.isCurrentUser {
                    NavigationLink(destination: ConnectionsView(dependencies: viewModel.dependencies)) {
                        HStack(spacing: 4) {
                            Text("\(viewModel.connections.count) \(viewModel.connections.count == 1 ? "friend" : "friends")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.cauldronOrange)
                    }
                } else if !viewModel.isCurrentUser {
                    connectionStatusBadge
                }
            }

            // Edit Profile button for current user
            if viewModel.isCurrentUser {
                Button {
                    showingEditProfile = true
                } label: {
                    Label("Edit Profile", systemImage: "pencil")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .tint(.cauldronOrange)
            }
        }
        .padding(.top)
    }

    private var friendViewIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .font(.caption)
            Text("This is how your profile appears to friends")
                .font(.caption)
        }
        .foregroundColor(.secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var connectionStatusBadge: some View {
        switch viewModel.connectionState {
        case .connected:
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

        case .pendingSent:
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

        case .pendingReceived:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                Text("Wants to be Friends")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.15))
            .cornerRadius(8)

        case .notConnected, .loading:
            EmptyView()
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        VStack(spacing: 12) {
            if viewModel.isProcessing {
                ProgressView()
                    .padding()
            } else {
                switch viewModel.connectionState {
                case .notConnected:
                    connectButton
                case .pendingSent:
                    pendingText
                case .pendingReceived:
                    pendingReceivedButtons
                case .connected:
                    connectedSection
                case .loading:
                    ProgressView()
                }
            }
        }
        .padding(.horizontal)
    }

    private var connectButton: some View {
        Button {
            Task {
                await viewModel.sendConnectionRequest()
            }
        } label: {
            Label("Add Friend", systemImage: "person.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.cauldronOrange)
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(viewModel.isProcessing)
    }

    private var pendingReceivedButtons: some View {
        VStack(spacing: 12) {
            Text("Friend Request")
                .font(.headline)
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.acceptConnection()
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isProcessing)

                Button {
                    Task {
                        await viewModel.rejectConnection()
                    }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.isProcessing)
            }
        }
    }

    private var connectedSection: some View {
        Button(role: .destructive) {
            Task {
                await viewModel.removeConnection()
            }
        } label: {
            Label("Remove Friend", systemImage: "person.badge.minus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
        }
        .disabled(viewModel.isProcessing)
    }

    private var pendingText: some View {
        VStack(spacing: 12) {
            Label("Request Sent", systemImage: "clock")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Waiting for \(user.displayName) to respond")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            Button(role: .destructive) {
                Task {
                    await viewModel.cancelConnectionRequest()
                }
            } label: {
                Label("Cancel Request", systemImage: "xmark.circle")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(8)
            }
            .disabled(viewModel.isProcessing)
        }
        .padding()
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
                                CollectionCardCompact(collection: collection)
                            }
                            .buttonStyle(.plain)
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
                // Horizontal scroll for normal view, grid for search
                if viewModel.searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(viewModel.filteredRecipes.prefix(10), id: \.id) { sharedRecipe in
                                NavigationLink(destination: RecipeDetailView(
                                    recipe: sharedRecipe.recipe,
                                    dependencies: viewModel.dependencies,
                                    sharedBy: sharedRecipe.sharedBy,
                                    sharedAt: sharedRecipe.sharedAt
                                )) {
                                    ProfileRecipeCard(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    // Grid view for search results
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(viewModel.filteredRecipes, id: \.id) { sharedRecipe in
                            NavigationLink(destination: RecipeDetailView(
                                recipe: sharedRecipe.recipe,
                                dependencies: viewModel.dependencies,
                                sharedBy: sharedRecipe.sharedBy,
                                sharedAt: sharedRecipe.sharedAt
                            )) {
                                ProfileRecipeCard(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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

            if viewModel.searchText.isEmpty && viewModel.connectionState != .connected {
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
            showShareSheet = true
        } catch {
            AppLogger.general.error("Failed to generate profile share link: \(error.localizedDescription)")
            viewModel.errorMessage = "Failed to generate share link: \(error.localizedDescription)"
            viewModel.showError = true
        }
    }
}

// MARK: - Profile Recipe Card (horizontal scroll)

struct ProfileRecipeCard: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            RecipeImageView(recipe: sharedRecipe.recipe, recipeImageService: dependencies.recipeImageService)
                .frame(width: 240, height: 160)

            // Title
            Text(sharedRecipe.recipe.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 240, height: 20, alignment: .leading)

            // Time and visibility
            HStack(spacing: 6) {
                if let time = sharedRecipe.recipe.displayTime {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(time)
                            .font(.caption)
                    }
                    .foregroundColor(.cauldronOrange)
                }

                Spacer()

                // Visibility indicator for own recipes
                if sharedRecipe.recipe.isOwnedByCurrentUser() {
                    Image(systemName: sharedRecipe.recipe.visibility.icon)
                        .font(.caption2)
                        .foregroundColor(sharedRecipe.recipe.visibility == .publicRecipe ? .green : .secondary)
                }
            }
            .frame(width: 240, height: 20)
        }
        .frame(width: 240)
    }
}

// MARK: - Collection Card Compact

struct CollectionCardCompact: View {
    let collection: Collection

    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                Circle()
                    .fill(selectedColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                if let emoji = collection.emoji {
                    Text(emoji)
                        .font(.system(size: 40))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 36))
                        .foregroundColor(selectedColor)
                }
            }

            // Collection name
            Text(collection.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .frame(width: 100, alignment: .center)

            // Recipe count
            Text("\(collection.recipeCount) recipes")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 100)
    }

    private var selectedColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .purple
        }
        return .purple
    }
}

// MARK: - All Profile Recipes List View

struct AllProfileRecipesListView: View {
    let recipes: [SharedRecipe]
    let user: User
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
        .navigationTitle("\(user.displayName)'s Recipes")
        .navigationBarTitleDisplayMode(.inline)
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
