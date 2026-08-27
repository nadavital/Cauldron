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
    @State private var searchHistory: SearchHistoryStore
    @State private var showingProfileSheet = false
    @State private var showingIngredientFilters = false
    @Namespace private var recipeTransition
    let isActive: Bool
    let screenshotDetailRecipe: Recipe?

    enum SearchMode: String, CaseIterable {
        case recipes = "Recipes"
        case people = "People"
    }

    @Binding var navigationPath: NavigationPath

    init(
        dependencies: DependencyContainer,
        navigationPath: Binding<NavigationPath>,
        isActive: Bool = true,
        screenshotDetailRecipe: Recipe? = nil
    ) {
        _viewModel = State(initialValue: SearchTabViewModel(dependencies: dependencies))
        _searchHistory = State(initialValue: SearchHistoryStore(ownerID: CurrentUserSession.shared.userId))
        _navigationPath = navigationPath
        self.isActive = isActive
        self.screenshotDetailRecipe = screenshotDetailRecipe
    }

    private var isRegularWidth: Bool {
        // Both Catalyst and the iPhone/iPad app running on Apple silicon Macs
        // already have the app's primary sidebar. A nested Search split view
        // wastes the remaining window on another sidebar and placeholder pane.
        !RuntimeEnvironment.prefersDesktopWorkspace && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isActive {
                if isRegularWidth {
                    splitView
                } else {
                    compactView
                }
            } else {
                Color.clear
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
            .appSheetSizing(.large)
        }
        .sheet(isPresented: $showingIngredientFilters) {
            ingredientFiltersSheet
                .appSheetSizing(.standard)
        }
        .task {
            searchHistory.selectOwner(currentUserSession.userId)
            await viewModel.loadDataIfNeeded()
        }
        .onChange(of: currentUserSession.userId) { _, userID in
            searchHistory.selectOwner(userID)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
            viewModel.scheduleRecipeLibraryRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated"))) { _ in
            viewModel.scheduleRecipeLibraryRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeAdded"))) { _ in
            viewModel.scheduleRecipeLibraryRefresh()
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
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            showingProfileSheet = false
            showingIngredientFilters = false
        }
        .onSubmit(of: .search) {
            recordCurrentRecipeSearch()
        }
    }

    private var compactView: some View {
        NavigationStack(path: $navigationPath) {
            searchContent
                .navigationTitle("Search")
                .toolbarTitleDisplayMode(
                    RuntimeEnvironment.prefersDesktopWorkspace ? .inline : .inlineLarge
                )
                .toolbar { searchToolbar }
                .refreshable {
                    await viewModel.loadData(forceRefreshPublicRecipes: true)
                }
                .navigationDestination(for: Recipe.self) { recipe in
                    RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)
                        .navigationTransition(.zoom(sourceID: recipe.id, in: recipeTransition))
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
                .navigationDestination(for: VisualRecipeSearchRoute.self) { route in
                    VisualRecipeSearchResultsView(route: route, dependencies: viewModel.dependencies)
                }
        }
        .searchable(text: $searchText, prompt: searchPrompt)
    }

    private var splitView: some View {
        NavigationSplitView {
            searchContent
                .navigationTitle("Search")
                .toolbarTitleDisplayMode(.inlineLarge)
                .toolbar { searchToolbar }
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
                .refreshable {
                    await viewModel.loadData(forceRefreshPublicRecipes: true)
                }
        } detail: {
            NavigationStack(path: $navigationPath) {
                Group {
                    if let screenshotDetailRecipe {
                        RecipeDetailView(
                            recipe: screenshotDetailRecipe,
                            dependencies: viewModel.dependencies
                        )
                    } else {
                        splitDetailPlaceholder
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
                    .navigationDestination(for: Tag.self) { tag in
                        ExploreTagView(tag: tag, dependencies: viewModel.dependencies)
                    }
                    .navigationDestination(for: VisualRecipeSearchRoute.self) { route in
                        VisualRecipeSearchResultsView(route: route, dependencies: viewModel.dependencies)
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
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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
            .contentMargins(.bottom, Theme.Spacing.xxl, for: .scrollContent)
        }
        .warmCanvas()
    }

    private var splitDetailPlaceholder: some View {
        AppStateView(
            kind: .empty(systemImage: searchMode == .recipes ? "fork.knife" : "person.2"),
            titleText: .verbatim(
                searchMode == .recipes ? "Select a Recipe" : "Select a Person"
            ),
            messageText: .verbatim(
                searchMode == .recipes ? "Choose a recipe to view its details." : "Choose a person to view their profile."
            )
        )
        .warmCanvas()
    }

    @ToolbarContentBuilder
    private var searchToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            if let user = currentUserSession.currentUser {
                Button {
                    showingProfileSheet = true
                } label: {
                    ProfileAvatar(user: user, size: 32, dependencies: viewModel.dependencies)
                }
                .accessibilityLabel("Profile and settings")
                .accessibilityHint("Opens your profile and app settings")
            }
        }
    }

    private var searchPrompt: String {
        searchMode == .recipes ? "Search recipes" : "Search people"
    }
    
    private var categoriesView: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            if !searchHistory.entries.isEmpty {
                RecentRecipeSearchesSection(
                    entries: searchHistory.entries,
                    select: selectRecentRecipeSearch,
                    remove: searchHistory.remove,
                    clear: searchHistory.clear
                )
            }

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
                            .buttonStyle(PressableScaleStyle())
                        }
                    }
                }
            }
            
            // Categories Grid
            ForEach(RecipeCategory.Section.allCases, id: \.self) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(section.rawValue)
                        .font(Theme.Typography.sectionTitle)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                        ForEach(RecipeCategory.all(in: section)) { category in
                            Button {
                                navigationPath.append(Tag(name: category.tagValue))
                            } label: {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Text(category.emoji)
                                        .font(.body)
                                        .frame(width: 30, height: 30)
                                        .background(category.color.opacity(0.1), in: Circle())

                                    Text(category.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)

                                    Spacer(minLength: 0)

                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(
                                    category.color.opacity(0.08),
                                    in: .rect(
                                        cornerRadius: Theme.Radius.card,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(PressableScaleStyle())
                        }
                    }
                }
            }
        }
    }
    
    private var recipeSearchResultsView: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            let results = viewModel.displayedRecipeResults

            if RuntimeEnvironment.forceSkeletonLoading || (viewModel.isLoading && viewModel.recipeSearchResults.isEmpty) {
                RecipeRowSkeletonList()
            } else if viewModel.recipeSearchResults.isEmpty {
                EmptyStateView(
                    title: "No Recipes Found",
                    message: "Try searching for different keywords.",
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xxl)
            } else {
                refinementBar

                if results.isEmpty {
                    EmptyStateView(
                        title: "No Matches",
                        message: "No recipes match the current filters.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xl)
                } else {
                    Text("\(results.count) recipe\(results.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ForEach(results) { group in
                        Button {
                            recordCurrentRecipeSearch()
                            navigationPath.append(group.primaryRecipe)
                        } label: {
                            SearchRecipeGroupRow(group: group, dependencies: viewModel.dependencies)
                        }
                        .buttonStyle(PressableScaleStyle())
                        .matchedTransitionSource(id: group.primaryRecipe.id, in: recipeTransition)
                    }
                }
            }
        }
    }

    private func recordCurrentRecipeSearch() {
        guard searchMode == .recipes else { return }
        searchHistory.record(searchText)
    }

    private func selectRecentRecipeSearch(_ query: String) {
        searchMode = .recipes
        searchText = query
        searchHistory.record(query)
    }

    /// Time filter + sort controls shown above recipe results.
    private var refinementBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Menu {
                        Picker("Time", selection: $viewModel.timeFilter) {
                            ForEach(RecipeTimeFilter.allCases) { filter in
                                Text(filter.label).tag(filter)
                            }
                        }
                    } label: {
                        refinementChip(
                            title: viewModel.timeFilter == .any ? "Time" : viewModel.timeFilter.label,
                            systemImage: "clock",
                            isActive: viewModel.timeFilter != .any
                        )
                    }

                    Button {
                        showingIngredientFilters = true
                    } label: {
                        refinementChip(
                            title: ingredientFilterLabel,
                            systemImage: "carrot",
                            isActive: hasIngredientFilters
                        )
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Picker("Sort", selection: $viewModel.sortOrder) {
                            ForEach(RecipeSortOrder.allCases) { order in
                                Text(order.label).tag(order)
                            }
                        }
                    } label: {
                        refinementChip(
                            title: viewModel.sortOrder == .relevance ? "Sort" : viewModel.sortOrder.label,
                            systemImage: "arrow.up.arrow.down",
                            isActive: viewModel.sortOrder != .relevance
                        )
                    }

                    if viewModel.hasActiveRefinements {
                        IconActionButton(
                            "Clear filters",
                            systemImage: "xmark",
                            style: .glass,
                            tint: .secondary
                        ) {
                            withAnimation(Theme.Animation.snappy) { viewModel.clearRefinements() }
                        }
                    }
                }
            }
        }
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    private var hasIngredientFilters: Bool {
        !viewModel.requiredIngredientsText.trimmed.isEmpty ||
            !viewModel.excludedIngredientsText.trimmed.isEmpty
    }

    private var ingredientFilterLabel: String {
        let filterCount = [
            viewModel.requiredIngredientsText,
            viewModel.excludedIngredientsText,
        ].filter { !$0.trimmed.isEmpty }.count
        return filterCount == 0 ? "Ingredients" : "Ingredients · \(filterCount)"
    }

    private var ingredientFiltersSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Ingredient filters")
                            .font(Theme.Typography.sectionTitle)
                        Text("Use commas to separate ingredients. Leave either field empty when it doesn't matter.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        ingredientField(
                            title: "Include",
                            detail: "Every result must contain these",
                            prompt: "tomato, basil",
                            text: $viewModel.requiredIngredientsText
                        )
                        Divider()
                        ingredientField(
                            title: "Exclude",
                            detail: "Hide recipes containing these",
                            prompt: "peanuts, shellfish",
                            text: $viewModel.excludedIngredientsText
                        )
                    }
                    .padding(Theme.Spacing.lg)
                    .appSurface(.resting)
                }
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.xl)
            }
            .warmCanvas()
            .navigationTitle("Ingredients")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if hasIngredientFilters {
                        Button("Clear") {
                            viewModel.requiredIngredientsText = ""
                            viewModel.excludedIngredientsText = ""
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingIngredientFilters = false }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func ingredientField(
        title: String,
        detail: String,
        prompt: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Color.appBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
    }

    private func refinementChip(title: String, systemImage: String, isActive: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: systemImage)
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline)
        .foregroundStyle(isActive ? Color.cauldronOrange : Color.primary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .glassEffect(
            isActive ? .regular.tint(Color.cauldronOrange.opacity(0.25)) : .regular,
            in: Capsule()
        )
    }
    
    private var peopleSearchView: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if searchText.isEmpty {
                // Recommendations only (no friends list)
                if !viewModel.recommendedUsers.isEmpty {
                    Text("Suggested for You")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)

                    ForEach(viewModel.recommendedUsers) { user in
                        Button {
                            navigationPath.append(user)
                        } label: {
                            UserSearchRowView(
                                user: user,
                                viewModel: viewModel
                            )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                } else {
                    AppStateView(
                        kind: .empty(systemImage: "person.2"),
                        title: "Search for People",
                        message: "Find friends to share recipes with."
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else if RuntimeEnvironment.forceSkeletonLoading || (viewModel.isLoadingPeople && viewModel.peopleSearchResults.isEmpty) {
                UserRowSkeletonList()
            } else if viewModel.peopleSearchResults.isEmpty {
                AppStateView(
                    kind: .empty(systemImage: "person.2.slash"),
                    title: "No Matching People",
                    message: "Try searching for a different name."
                )
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
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
    }
    
    private var emptyState: some View {
        EmptyStateView(
            title: "No Recipes Yet",
            message: "Add recipes to see them organized by category.",
            systemImage: "book.closed"
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

private struct RecentRecipeSearchesSection: View {
    let entries: [String]
    let select: (String) -> Void
    let remove: (String) -> Void
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("Recent Searches")
                    .font(Theme.Typography.sectionTitle)
                Spacer()
                Button("Clear", action: clear)
                    .font(.subheadline)
                    .foregroundStyle(Color.cauldronOrange)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(entries, id: \.self) { query in
                        Button {
                            select(query)
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .padding(.horizontal, Theme.Spacing.sm)
                                .frame(minHeight: Theme.HitTarget.minimum)
                                .background(Color.appSurfaceElevated, in: Capsule())
                                .overlay(Capsule().stroke(Color.appSeparator, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from Recents", systemImage: "trash", role: .destructive) {
                                remove(query)
                            }
                        }
                    }
                }
            }
        }
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
        HStack(spacing: Theme.Spacing.sm) {
            ProfileAvatar(user: user, size: 50, dependencies: viewModel.dependencies)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.cauldronOrange)
                    Text("Retry")
                        .font(.caption)
                }
            }

        case .pendingIncoming:
            HStack(spacing: Theme.Spacing.xs) {
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
        HStack(spacing: Theme.Spacing.sm) {
            ProfileAvatar(user: user, size: 50)
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
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
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            RecipeRowView(recipe: group.primaryRecipe, dependencies: dependencies)
            
            // Social Context / Save Count Footer
            if !group.friendSavers.isEmpty {
                HStack(spacing: Theme.Spacing.xxs) {
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
                HStack(spacing: Theme.Spacing.xxs) {
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
