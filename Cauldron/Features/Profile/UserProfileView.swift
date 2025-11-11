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
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditProfile = false
    @State private var hasLoadedInitialData = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]  // Cache recipe images by collection ID

    init(user: User, dependencies: DependencyContainer) {
        self.user = user
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(
            user: user,
            dependencies: dependencies
        ))
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
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ProfileAvatar(user: user, size: 100)

            // Display Name
            Text(user.displayName)
                .font(.title2)
                .fontWeight(.bold)

            // Username, Friends Count, and Connection Status Badge
            VStack(spacing: 8) {
                Text("@\(user.username)")
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
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Label("Collections", systemImage: "folder")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !viewModel.isLoadingCollections && !viewModel.userCollections.isEmpty {
                    Text("\(viewModel.userCollections.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

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
                collectionsScrollView
            }
        }
    }

    private var emptyCollectionsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(viewModel.isCurrentUser ? "No collections to show" : "\(user.displayName) hasn't shared any collections yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var collectionsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(viewModel.userCollections, id: \.id) { collection in
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
                        // Load recipe images if not cached
                        if collectionImageCache[collection.id] == nil {
                            let images = await viewModel.getRecipeImages(for: collection)
                            collectionImageCache[collection.id] = images
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Label("Recipes", systemImage: "book")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                // Show count when searching
                if !viewModel.searchText.isEmpty && !viewModel.isLoadingRecipes {
                    Text("\(viewModel.filteredRecipes.count)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

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
                recipesGrid
            }
        }
    }

    private var emptyRecipesState: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.searchText.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyStateMessage: String {
        if !viewModel.searchText.isEmpty {
            return "No recipes match '\(viewModel.searchText)'"
        } else if viewModel.connectionState == .connected {
            return "\(user.displayName) hasn't shared any recipes yet"
        } else {
            return "\(user.displayName) hasn't made any recipes public yet"
        }
    }

    private var recipesGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ], spacing: 16) {
            ForEach(viewModel.filteredRecipes, id: \.id) { sharedRecipe in
                if sharedRecipe.recipe.isOwnedByCurrentUser() {
                    // Own recipe - use RecipeDetailView for full editing capabilities
                    NavigationLink(destination: RecipeDetailView(
                        recipe: sharedRecipe.recipe,
                        dependencies: viewModel.dependencies
                    )) {
                        RecipeCard(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                    }
                    .buttonStyle(.plain)
                } else {
                    // Someone else's recipe - use SharedRecipeDetailView (read-only)
                    NavigationLink(destination: SharedRecipeDetailView(
                        sharedRecipe: sharedRecipe,
                        dependencies: viewModel.dependencies,
                        onCopy: {
                            // Reload recipes after copying - force refresh since data changed
                            await viewModel.loadUserRecipes(forceRefresh: true)
                        },
                        onRemove: {
                            // Reload recipes after removing - force refresh since data changed
                            await viewModel.loadUserRecipes(forceRefresh: true)
                        }
                    )) {
                        RecipeCard(sharedRecipe: sharedRecipe, dependencies: viewModel.dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Recipe Card

struct RecipeCard: View {
    let sharedRecipe: SharedRecipe
    let dependencies: DependencyContainer

    @MainActor
    private var isOwnRecipe: Bool {
        sharedRecipe.recipe.isOwnedByCurrentUser()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image
            if let imageURL = sharedRecipe.recipe.imageURL {
                ProfileRecipeImage(imageURL: imageURL, recipeImageService: dependencies.recipeImageService)
                    .onAppear {
                        AppLogger.general.debug("📸 RecipeCard loading image for '\(sharedRecipe.recipe.title)': \(imageURL.absoluteString)")
                    }
            } else {
                placeholderImage
                    .onAppear {
                        AppLogger.general.warning("⚠️ RecipeCard: No imageURL for recipe '\(sharedRecipe.recipe.title)'")
                    }
            }

            // Title
            Text(sharedRecipe.recipe.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundColor(.primary)
                .frame(height: 36, alignment: .top)

            // Meta info
            HStack(spacing: 8) {
                if let time = sharedRecipe.recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Show ownership or visibility indicator
                if isOwnRecipe {
                    // Own recipe - show visibility status
                    Image(systemName: sharedRecipe.recipe.visibility.icon)
                        .font(.caption2)
                        .foregroundColor(sharedRecipe.recipe.visibility == .publicRecipe ? .green : .cauldronOrange)
                } else {
                    // Others' recipe - show shared indicator
                    Image(systemName: "person.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var placeholderImage: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.cauldronOrange.opacity(0.08),
                        Color.cauldronOrange.opacity(0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "fork.knife")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.cauldronOrange.opacity(0.3))
            }
            .frame(width: geometry.size.width, height: geometry.size.width / 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(1.5, contentMode: .fit)
    }
}

// MARK: - Profile Recipe Image

/// Adaptive recipe image for profile grid that fills available width
struct ProfileRecipeImage: View {
    let imageURL: URL
    let recipeImageService: RecipeImageService

    @State private var loadedImage: UIImage?
    @State private var imageOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image = loadedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(imageOpacity)
                } else {
                    placeholderView
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width / 1.5)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .aspectRatio(1.5, contentMode: .fit)
        .task {
            await loadImage()
        }
    }

    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.cauldronOrange.opacity(0.08),
                    Color.cauldronOrange.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "fork.knife")
                .font(.system(size: 36))
                .foregroundStyle(Color.cauldronOrange.opacity(0.3))
        }
    }

    private func loadImage() async {
        let result = await recipeImageService.loadImage(from: imageURL)

        switch result {
        case .success(let image):
            loadedImage = image
            withAnimation(.easeOut(duration: 0.3)) {
                imageOpacity = 1.0
            }
        case .failure:
            break
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
