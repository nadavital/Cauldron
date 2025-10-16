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
    
    init(dependencies: DependencyContainer) {
        _viewModel = StateObject(wrappedValue: SearchTabViewModel(dependencies: dependencies))
    }
    
    var body: some View {
        NavigationStack {
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
                        RecipeRowView(recipe: recipe)
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
                        Text("Create demo users from the Sharing tab menu")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
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
                    UserSearchRowView(
                        user: user,
                        dependencies: viewModel.dependencies,
                        currentUserId: viewModel.currentUserId,
                        onConnectionChanged: {
                            await viewModel.loadUsers()
                        }
                    )
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
    let dependencies: DependencyContainer
    let currentUserId: UUID
    let onConnectionChanged: () async -> Void
    
    @State private var connectionStatus: ConnectionButtonStatus = .none
    @State private var isProcessing = false
    
    enum ConnectionButtonStatus {
        case none
        case pending
        case connected
        case pendingReceived
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cauldronOrange.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(user.displayName.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.cauldronOrange)
                )
            
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
        .task {
            await checkConnectionStatus()
        }
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
            switch connectionStatus {
            case .none:
                Button {
                    Task {
                        await sendConnectionRequest()
                    }
                } label: {
                    if isProcessing {
                        ProgressView()
                    } else {
                        Text("Connect")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.cauldronOrange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .disabled(isProcessing)

            case .pending:
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.secondary)

            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

            case .pendingReceived:
                Text("Respond")
                    .font(.caption)
                    .foregroundColor(.cauldronOrange)
            }
        }
    }
    
    private func checkConnectionStatus() async {
        do {
            // Fetch connections from CloudKit PUBLIC database
            let connections = try await dependencies.cloudKitService.fetchConnections(forUserId: currentUserId)

            // Find connection with this user
            if let connection = connections.first(where: { conn in
                (conn.fromUserId == currentUserId && conn.toUserId == user.id) ||
                (conn.fromUserId == user.id && conn.toUserId == currentUserId)
            }) {
                if connection.isAccepted {
                    connectionStatus = .connected
                } else if connection.fromUserId == currentUserId {
                    connectionStatus = .pending
                } else {
                    connectionStatus = .pendingReceived
                }
            } else {
                connectionStatus = .none
            }
        } catch {
            AppLogger.general.error("Failed to check connection status: \(error.localizedDescription)")
        }
    }
    
    private func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Send connection request via CloudKit to PUBLIC database
            let connection = try await dependencies.cloudKitService.sendConnectionRequest(
                from: currentUserId,
                to: user.id
            )

            // Also save locally for offline access
            try? await dependencies.connectionRepository.save(connection)

            connectionStatus = .pending
            await onConnectionChanged()
        } catch {
            AppLogger.general.error("Failed to send connection request: \(error.localizedDescription)")
        }
    }
}

/// Row view for displaying a user
struct UserRowView: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.cauldronOrange.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(user.displayName.prefix(2).uppercased())
                        .font(.headline)
                        .foregroundColor(.cauldronOrange)
                )
            
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
    SearchTabView(dependencies: .preview())
}
