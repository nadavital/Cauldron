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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isRegularWidth {
                splitView
            } else {
                compactView
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

    private var compactView: some View {
        NavigationStack(path: $navigationPath) {
            searchContent
                .navigationTitle("Search")
                .toolbar { searchToolbar }
                .refreshable {
                    await viewModel.loadData()
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
    }

    private var splitView: some View {
        NavigationSplitView {
            searchContent
                .navigationTitle("Search")
                .toolbar { searchToolbar }
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
                .refreshable {
                    await viewModel.loadData()
                }
        } detail: {
            NavigationStack(path: $navigationPath) {
                splitDetailPlaceholder
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
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(
            text: $searchText,
            placement: .sidebar,
            prompt: searchMode == .recipes ? "Search recipes" : "Search people"
        )
    }

    private var searchContent: some View {
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
    }

    private var splitDetailPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: searchMode == .recipes ? "fork.knife" : "person.2")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text(searchMode == .recipes ? "Select a recipe to view details" : "Select a person to view profile")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cauldronBackground.ignoresSafeArea())
    }

    @ToolbarContentBuilder
    private var searchToolbar: some ToolbarContent {
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
                        Button {
                            navigationPath.append(user)
                        } label: {
                            UserSearchRowView(
                                user: user,
                                viewModel: viewModel
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
                            Button {
                                navigationPath.append(user)
                            } label: {
                                UserSearchRowView(
                                    user: user,
                                    viewModel: viewModel
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
                    Button {
                        navigationPath.append(user)
                    } label: {
                        UserSearchRowView(
                            user: user,
                            viewModel: viewModel
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

    @State private var isProcessing = false

    private var connectionState: ConnectionRelationshipState {
        viewModel.relationshipState(for: user)
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
        switch connectionState {
        case .currentUser:
            Text("You")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()

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

        case .pendingOutgoing:
            Text("Pending")
                .font(.caption)
                .foregroundColor(.secondary)

        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.green)

        case .syncing:
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.green)

                ProgressView()
                    .scaleEffect(0.6)
                    .offset(x: 12, y: -12)
            }

        case .failed:
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

        case .pendingIncoming:
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
    
    // MARK: - Actions (delegate to ViewModel)

    private func sendConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }
        await viewModel.sendConnectionRequest(to: user)
    }

    private func acceptConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }
        await viewModel.acceptConnectionRequest(from: user)
    }

    private func rejectConnectionRequest() async {
        isProcessing = true
        defer { isProcessing = false }
        await viewModel.rejectConnectionRequest(from: user)
    }

    private func retryFailedOperation() async {
        await viewModel.retryConnectionOperation(for: user)
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
