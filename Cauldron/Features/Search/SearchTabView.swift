//
//  SearchTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI
import os

/// Search tab - search across all recipes and browse by category
struct SearchTabView: View {
    @State private var viewModel: SearchTabViewModel
    @StateObject private var currentUserSession = CurrentUserSession.shared
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .recipes
    @State private var showingProfileSheet = false

    enum SearchMode: String, CaseIterable {
        case recipes = "Recipes"
        case people = "People"
    }

    @Binding var navigationPath: NavigationPath

    init(dependencies: DependencyContainer, navigationPath: Binding<NavigationPath>) {
        _viewModel = State(initialValue: SearchTabViewModel(dependencies: dependencies))
        _navigationPath = navigationPath
    }
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Search mode picker
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content based on search mode
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if searchMode == .recipes {
                            if searchText.isEmpty && viewModel.selectedCategories.isEmpty {
                                // Show categories when not searching and no filters
                                categoriesView
                            } else {
                                // Show recipe search results (filtered by text or categories)
                                recipeSearchResultsView
                            }
                        } else {
                            // Show people search
                            peopleSearchView
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let user = currentUserSession.currentUser {
                        Button {
                            showingProfileSheet = true
                        } label: {
                            ProfileAvatar(user: user, size: 32, dependencies: viewModel.dependencies)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingProfileSheet) {
                NavigationStack {
                    if let user = currentUserSession.currentUser {
                        UserProfileView(user: user, dependencies: viewModel.dependencies)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { showingProfileSheet = false }
                                }
                            }
                    }
                }
            }
            .task {
                await viewModel.loadData()
            }
            .refreshable {
                await viewModel.loadData()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated"))) { _ in
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeAdded"))) { _ in
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSearchTab"))) { _ in
                // Switch to People search mode when coming from Friends empty state
                searchMode = .people
                searchText = "" // Clear any existing search
            }
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)
            }
            .navigationDestination(for: User.self) { user in
                UserProfileView(user: user, dependencies: viewModel.dependencies)
            }
            .navigationDestination(for: Collection.self) { collection in
                CollectionDetailView(collection: collection, dependencies: viewModel.dependencies)
            }
            .navigationDestination(for: Tag.self) { tag in
                ExploreTagView(tag: tag, dependencies: viewModel.dependencies)
            }
        }
        .searchable(text: $searchText, prompt: searchMode == .recipes ? "Search recipes" : "Search people")
        .onChange(of: searchText) { _, newValue in
            if searchMode == .recipes {
                viewModel.updateRecipeSearch(newValue)
            } else {
                viewModel.updatePeopleSearch(newValue)
            }
        }
        .onChange(of: searchMode) { _, _ in
            // Clear search when switching modes
            searchText = ""
        }
    }
    
    private var categoriesView: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Active Filters (if any)
            if !viewModel.selectedCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Array(viewModel.selectedCategories), id: \.self) { category in
                            Button {
                                viewModel.toggleCategory(category)
                            } label: {
                                TagView(category.tagValue, isSelected: true, onRemove: {
                                    viewModel.toggleCategory(category)
                                })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Categories Grid
            ForEach(RecipeCategory.Section.allCases, id: \.self) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.rawValue)
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(RecipeCategory.all(in: section)) { category in
                            Button {
                                navigationPath.append(Tag(name: category.tagValue))
                            } label: {
                                HStack(spacing: 12) {
                                    // Icon Container
                                    ZStack {
                                        Circle()
                                            .fill(category.color.opacity(0.15))
                                            .frame(width: 40, height: 40)
                                        Text(category.emoji)
                                            .font(.title3)
                                    }

                                    Text(category.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(8)
                                .background(Color(.secondarySystemGroupedBackground))
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    private var recipeSearchResultsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.recipeSearchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No recipes found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Try searching for different keywords")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Text("\(viewModel.recipeSearchResults.count) recipes found")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ForEach(viewModel.recipeSearchResults) { group in
                    Button {
                        navigationPath.append(group.primaryRecipe)
                    } label: {
                        SearchRecipeGroupRow(group: group, dependencies: viewModel.dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var peopleSearchView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if searchText.isEmpty {
                // Show friends list if available, otherwise show empty state
                if !viewModel.friends.isEmpty {
                    Text("Your Friends")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    ForEach(viewModel.friends) { user in
                        NavigationLink {
                            UserProfileView(user: user, dependencies: viewModel.dependencies)
                        } label: {
                            UserSearchRowView(
                                user: user,
                                viewModel: viewModel,
                                currentUserId: viewModel.currentUserId
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Recommended Users (Friends of Friends)
                    if !viewModel.recommendedUsers.isEmpty {
                        Text("Suggested for You")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 24)
                        
                        ForEach(viewModel.recommendedUsers) { user in
                            NavigationLink {
                                UserProfileView(user: user, dependencies: viewModel.dependencies)
                            } label: {
                                UserSearchRowView(
                                    user: user,
                                    viewModel: viewModel,
                                    currentUserId: viewModel.currentUserId
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Search for People")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            
                        Text("Find friends to share recipes with")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else if viewModel.isLoadingPeople && viewModel.peopleSearchResults.isEmpty {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.peopleSearchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No matching users")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        
                    Text("Try searching for a different name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack {
                    Text("\(viewModel.peopleSearchResults.count) people found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if viewModel.isLoadingPeople {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.leading, 8)
                    }
                }
                
                ForEach(viewModel.peopleSearchResults) { user in
                    NavigationLink {
                        UserProfileView(user: user, dependencies: viewModel.dependencies)
                    } label: {
                        UserSearchRowView(
                            user: user,
                            viewModel: viewModel,
                            currentUserId: viewModel.currentUserId
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Recipes Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Add recipes to see them organized by category")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Row view for displaying a user in search with connect button
struct UserSearchRowView: View {
    let user: User
    let viewModel: SearchTabViewModel
    let currentUserId: UUID

    @State private var isProcessing = false

    enum ConnectionUIState {
        case none
        case pending
        case connected
        case pendingReceived
        case syncing
        case error(ConnectionError)
    }

    // Compute connection state from ViewModel's connections
    private var connectionState: ConnectionUIState {
        // Get the managed connection from the connection manager
        if let managedConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) {
            let connection = managedConnection.connection

            // Check sync state first
            switch managedConnection.syncState {
            case .syncing:
                return .syncing
            case .syncFailed(let error):
                return .error(error as? ConnectionError ?? .networkFailure(error))
            case .pendingSync:
                return .syncing
            case .synced:
                break // Continue to check connection status
            }

            // Then check connection status
            if connection.isAccepted {
                return .connected
            } else if connection.fromUserId == currentUserId {
                return .pending
            } else {
                return .pendingReceived
            }
        }

        return .none
    }

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(user: user, size: 50, dependencies: viewModel.dependencies)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)

                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            connectionButton
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var connectionButton: some View {
        // Don't show connection button for your own profile
        if user.id == currentUserId {
            Text("You")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        } else {
            switch connectionState {
            case .none:
                Button {
                    Task {
                        await sendConnectionRequest()
                    }
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.cauldronOrange)
                    }
                }
                .disabled(isProcessing)

            case .pending:
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

            case .syncing:
                // Show connected with a subtle spinner
                ZStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green)

                    ProgressView()
                        .scaleEffect(0.6)
                        .offset(x: 12, y: -12)
                }

            case .error(let error):
                // Show error state with retry button
                Button {
                    Task {
                        await retryFailedOperation()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Retry")
                            .font(.caption)
                    }
                }

            case .pendingReceived:
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await acceptConnectionRequest()
                        }
                    } label: {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(isProcessing)

                    Button {
                        Task {
                            await rejectConnectionRequest()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
    
    // MARK: - Actions (delegate to ViewModel)

    private func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }
        await viewModel.sendConnectionRequest(to: user)
    }

    private func acceptConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        AppLogger.general.info("🔍 Attempting to accept connection for user: \(user.username) (ID: \(user.id))")
        AppLogger.general.info("Current user ID: \(currentUserId)")

        // Get the managed connection directly from ConnectionManager
        guard let managedConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("❌ Connection not found in ConnectionManager for user: \(user.username)")
            AppLogger.general.error("Total connections in manager: \(viewModel.dependencies.connectionManager.connections.count)")

            // Try reloading connections and try again
            AppLogger.general.info("🔄 Reloading connections from CloudKit...")
            await viewModel.loadConnections()

            // Try again after reload
            guard let retryConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) else {
                AppLogger.general.error("❌ Still not found after reload. Aborting.")
                return
            }

            AppLogger.general.info("✅ Found connection after reload!")
            await processAccept(retryConnection.connection)
            return
        }

        await processAccept(managedConnection.connection)
    }

    private func processAccept(_ connection: Connection) async {
        // Verify it's a pending request TO us
        guard connection.fromUserId == user.id &&
              connection.toUserId == currentUserId &&
              connection.status == .pending else {
            AppLogger.general.error("❌ Connection found but not a pending request to us.")
            AppLogger.general.error("  From: \(connection.fromUserId), To: \(connection.toUserId), Status: \(connection.status.rawValue)")
            AppLogger.general.error("  Expected - From: \(user.id), To: \(currentUserId), Status: pending")
            return
        }

        AppLogger.general.info("✅ Accepting connection request from \(user.username)")
        await viewModel.acceptConnection(connection)
    }

    private func rejectConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        AppLogger.general.info("🔍 Attempting to reject connection for user: \(user.username)")

        // Get the managed connection directly from ConnectionManager
        guard let managedConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) else {
            AppLogger.general.error("❌ Connection not found in ConnectionManager for user: \(user.username)")

            // Try reloading connections and try again
            await viewModel.loadConnections()

            guard let retryConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) else {
                AppLogger.general.error("❌ Still not found after reload. Aborting.")
                return
            }

            await processReject(retryConnection.connection)
            return
        }

        await processReject(managedConnection.connection)
    }

    private func processReject(_ connection: Connection) async {
        // Verify it's a pending request TO us
        guard connection.fromUserId == user.id &&
              connection.toUserId == currentUserId &&
              connection.status == .pending else {
            AppLogger.general.error("❌ Connection found but not a pending request to us.")
            AppLogger.general.error("  From: \(connection.fromUserId), To: \(connection.toUserId), Status: \(connection.status.rawValue)")
            return
        }

        AppLogger.general.info("✅ Rejecting connection request from \(user.username)")
        await viewModel.rejectConnection(connection)
    }

    private func retryFailedOperation() async {
        // Find the connection ID
        if let managedConnection = viewModel.dependencies.connectionManager.connectionStatus(with: user.id) {
            await viewModel.dependencies.connectionManager.retryFailedOperation(connectionId: managedConnection.id)
        }
    }
}

/// Row view for displaying a user
struct UserRowView: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(user: user, size: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct SearchRecipeGroupRow: View {
    let group: SearchRecipeGroup
    let dependencies: DependencyContainer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RecipeRowView(recipe: group.primaryRecipe, dependencies: dependencies)
            
            // Social Context / Save Count Footer
            if !group.friendSavers.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                    
                    Text("Saved by \(group.friendSavers.map { $0.displayName }.joined(separator: ", "))")
                        .font(.caption)
                    
                    if group.saveCount > group.friendSavers.count {
                        Text("and \(group.saveCount - group.friendSavers.count) others")
                            .font(.caption)
                    }
                }
                .foregroundColor(.secondary)
                .padding(.leading, 80) // Align to text content of row (approx image width + spacing)
            } else if group.saveCount > 1 {
                HStack(spacing: 4) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption)
                    Text("\(group.saveCount) saves")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.leading, 80)
            }
        }
    }
}

#Preview {
    SearchTabView(dependencies: .preview(), navigationPath: .constant(NavigationPath()))
}
