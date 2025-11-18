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
    @StateObject private var viewModel: SearchTabViewModel
    @State private var searchText = ""
    @State private var searchMode: SearchMode = .recipes

    enum SearchMode: String, CaseIterable {
        case recipes = "Recipes"
        case people = "People"
    }
    
    @Binding var navigationPath: NavigationPath
    
    init(dependencies: DependencyContainer, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: SearchTabViewModel(dependencies: dependencies))
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
                            if searchText.isEmpty {
                                // Show categories when not searching
                                categoriesView
                            } else {
                                // Show recipe search results
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
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)
            }
            .navigationDestination(for: User.self) { user in
                UserProfileView(user: user, dependencies: viewModel.dependencies)
            }
            .navigationDestination(for: Collection.self) { collection in
                CollectionDetailView(collection: collection, dependencies: viewModel.dependencies)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Browse by Category")
                .font(.title2)
                .fontWeight(.bold)
            
            if viewModel.recipesByTag.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(Array(viewModel.recipesByTag.keys).sorted(), id: \.self) { tagName in
                        if let recipes = viewModel.recipesByTag[tagName], !recipes.isEmpty {
                            NavigationLink(destination: CategoryRecipesListView(categoryName: tagName, recipes: recipes, dependencies: viewModel.dependencies)) {
                                CategoryCardView(categoryName: tagName, recipeCount: recipes.count)
                                    .frame(maxWidth: .infinity)
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

                ForEach(viewModel.recipeSearchResults) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)) {
                        RecipeRowView(recipe: recipe, dependencies: viewModel.dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var peopleSearchView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoadingPeople {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if viewModel.peopleSearchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No users found" : "No matching users")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if searchText.isEmpty {
                        #if DEBUG
                        Text("Create demo users from the Sharing tab menu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        #endif
                    } else {
                        Text("Try searching for a different name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                Text("\(viewModel.peopleSearchResults.count) people found")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
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
            ProfileAvatar(user: user, size: 50)

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

#Preview {
    SearchTabView(dependencies: .preview(), navigationPath: .constant(NavigationPath()))
}
