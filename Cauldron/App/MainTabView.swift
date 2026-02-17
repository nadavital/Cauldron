//
//  MainTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import Combine
import os

/// Tab identifiers for MainTabView
enum AppTab: Hashable {
    case cook
    case collections
    case collection(UUID)
    case groceries
    case sharing
    case search
}

/// Main tab-based navigation view
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let dependencies: DependencyContainer
    let preloadedData: PreloadedRecipeData?
    @State private var selectedTab: AppTab = .cook
    @State private var sidebarCollections: [Collection] = []
    @State private var sharedImportRequest: SharedImportRequest?
    @State private var didCheckInitialPendingImport = false
    @State private var isSavingPreparedSharedRecipe = false
    @State private var showSharedRecipeSavedToast = false
    @ObservedObject private var connectionManager: ConnectionManager

    @State private var searchNavigationPath = NavigationPath()

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let initialURL: URL?
        let preparedRecipe: Recipe?
        let preparedSourceInfo: String?
    }

    private var isCookModeActive: Bool {
        dependencies.cookModeCoordinator.isActive
    }

    private var isRegularWidthLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var featuredSidebarCollections: [Collection] {
        Array(sidebarCollections.prefix(4))
    }

    private var selectedTabBinding: Binding<AppTab?> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 ?? .cook }
        )
    }

    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        self.dependencies = dependencies
        self.preloadedData = preloadedData
        self.connectionManager = dependencies.connectionManager
    }

    var body: some View {
        tabScaffold
        // On iPad, this enables the native sidebar-based tab presentation.
        // On iPhone, it keeps standard tab bar behavior.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: isCookModeActive) {
            CookModeBanner(coordinator: dependencies.cookModeCoordinator)
                .contentShape(Rectangle())
                .onTapGesture {
                    dependencies.cookModeCoordinator.expandToFullScreen()
                }
        }
        .fullScreenCover(isPresented: Binding(
            get: { dependencies.cookModeCoordinator.showFullScreen },
            set: { dependencies.cookModeCoordinator.showFullScreen = $0 }
        )) {
            if let recipe = dependencies.cookModeCoordinator.currentRecipe {
                NavigationStack {
                    CookModeView(
                        recipe: recipe,
                        coordinator: dependencies.cookModeCoordinator,
                        dependencies: dependencies
                    )
                }
            }
        }
        .sheet(item: $sharedImportRequest) { request in
            ImporterView(
                dependencies: dependencies,
                initialURL: request.initialURL,
                preparedRecipe: request.preparedRecipe,
                preparedSourceInfo: request.preparedSourceInfo
            )
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
            // Switch to Friends tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Friends tab from notification")
            selectedTab = .sharing
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSharedContent"))) { notification in
            if let contentWrapper = notification.object as? ContentView.SharedContentWrapper {
                AppLogger.general.info("📍 Navigating to shared content in Search tab")
                selectedTab = .search

                // Reset path first to ensure clean navigation
                searchNavigationPath = NavigationPath()

                // Push content based on type
                switch contentWrapper.content {
                case .recipe(let recipe, _):
                    searchNavigationPath.append(recipe)
                case .profile(let user):
                    searchNavigationPath.append(user)
                case .collection(let collection, _):
                    searchNavigationPath.append(collection)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSearchTab"))) { _ in
            // Switch to Search tab when "Find people to add" is tapped from Friends empty state
            AppLogger.general.info("📍 Switching to Search tab to find people")
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecipeImportURL)) { notification in
            guard let url = notification.object as? URL else { return }
            AppLogger.general.info("📥 Opening importer from Share Extension URL: \(url.absoluteString)")
            _ = ShareExtensionImportStore.consumePendingRecipeURL()
            openImporter(with: url)
        }
        .task {
            guard !didCheckInitialPendingImport else { return }
            didCheckInitialPendingImport = true
            openPendingImporterIfNeeded()
        }
        .task {
            await refreshSidebarCollections()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            openPendingImporterIfNeeded()
            Task {
                await refreshSidebarCollections()
            }
        }
        .onChange(of: horizontalSizeClass) {
            Task {
                await refreshSidebarCollections()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            guard isRegularWidthLayout else { return }

            switch newTab {
            case .collection:
                Task {
                    await refreshSidebarCollections()
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionMetadataChanged)) { notification in
            applyOptimisticSidebarCollectionUpdate(notification)
            Task {
                await refreshSidebarCollections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionUpdated)) { _ in
            Task {
                await refreshSidebarCollections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionRecipesChanged)) { _ in
            Task {
                await refreshSidebarCollections()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CollectionAdded"))) { notification in
            applyOptimisticSidebarCollectionInsert(notification)
            Task {
                await refreshSidebarCollections()
            }
        }
        .toast(
            isShowing: Binding(
                get: { dependencies.cookModeCoordinator.showRecipeDeletedToast },
                set: { dependencies.cookModeCoordinator.showRecipeDeletedToast = $0 }
            ),
            icon: "trash.fill",
            message: "Recipe was deleted"
        )
        .toast(
            isShowing: $showSharedRecipeSavedToast,
            icon: "checkmark.circle.fill",
            message: "Recipe imported from share sheet"
        )
    }

    private var tabScaffold: some View {
        TabView(selection: selectedTabBinding) {
            Tab("Cook", systemImage: "flame.fill", value: .cook) {
                CookTabView(dependencies: dependencies, preloadedData: preloadedData)
            }

            Tab("Groceries", systemImage: "cart.fill", value: .groceries) {
                GroceriesView(dependencies: dependencies)
            }

            Tab("Friends", systemImage: "person.2.fill", value: .sharing) {
                FriendsTabView(dependencies: dependencies)
            }
            .badge(connectionManager.pendingRequestsCount)

            if isRegularWidthLayout {
                Tab("Collections", systemImage: "folder.fill", value: .collections) {
                    NavigationStack {
                        CollectionsListView(dependencies: dependencies)
                    }
                }
                .defaultVisibility(.hidden, for: .sidebar)
            }

            if isRegularWidthLayout {
                if !featuredSidebarCollections.isEmpty {
                    TabSection {
                        ForEach(featuredSidebarCollections, id: \.id) { collection in
                            Tab(
                                collectionSidebarLabel(for: collection),
                                systemImage: collectionSidebarSystemImage(for: collection),
                                value: Optional(AppTab.collection(collection.id))
                            ) {
                                NavigationStack {
                                    CollectionDetailView(collection: collection, dependencies: dependencies)
                                }
                            }
                        }
                    } header: {
                        Text("Collections")
                    }
                    .defaultVisibility(.hidden, for: .tabBar)
                }
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(dependencies: dependencies, navigationPath: $searchNavigationPath)
            }
        }
    }

    private func openPendingImporterIfNeeded() {
        guard !isSavingPreparedSharedRecipe else {
            return
        }

        if let prepared = ShareExtensionImportStore.consumePreparedRecipe() {
            AppLogger.general.info("📥 Consumed prepared Share Extension recipe payload")
            isSavingPreparedSharedRecipe = true
            Task {
                await autoSavePreparedSharedRecipe(prepared)
            }
            return
        }

        guard let pendingURL = ShareExtensionImportStore.consumePendingRecipeURL() else {
            return
        }

        AppLogger.general.info("📥 Consumed pending Share Extension URL: \(pendingURL.absoluteString)")
        openImporter(with: pendingURL)
    }

    private func openImporter(with url: URL) {
        selectedTab = .cook
        sharedImportRequest = SharedImportRequest(
            initialURL: url,
            preparedRecipe: nil,
            preparedSourceInfo: nil
        )
    }

    private func openPreparedImporter(recipe: Recipe, sourceInfo: String) {
        selectedTab = .cook
        sharedImportRequest = SharedImportRequest(
            initialURL: nil,
            preparedRecipe: recipe,
            preparedSourceInfo: sourceInfo
        )
    }

    @MainActor
    private func autoSavePreparedSharedRecipe(_ prepared: PreparedSharedRecipe) async {
        defer { isSavingPreparedSharedRecipe = false }

        let recipeForImport: Recipe
        do {
            let parsedRecipe = try await dependencies.textParser.parse(from: prepared.recipeParserInputText())
            recipeForImport = prepared.recipeMergedWithParsedContent(parsedRecipe)
            AppLogger.general.info("🧠 Reparsed Share Extension payload via text parser before save")
        } catch {
            recipeForImport = prepared.recipe
            AppLogger.general.warning("⚠️ Failed to reparse prepared share recipe; falling back to preprocessed payload: \(error.localizedDescription)")
        }

        let recipeToSave = await ImportedRecipeSaveBuilder.recipeForSave(
            from: recipeForImport,
            userId: CurrentUserSession.shared.userId,
            imageManager: dependencies.imageManager
        )

        do {
            try await dependencies.recipeRepository.create(recipeToSave)
            AppLogger.general.info("✅ Auto-saved prepared share recipe: \(recipeToSave.title)")
            NotificationCenter.default.post(name: .recipeAdded, object: recipeToSave.id)
            selectedTab = .cook
            showSharedRecipeSavedToast = true
        } catch {
            AppLogger.general.error("❌ Failed to auto-save prepared share recipe: \(error.localizedDescription)")
            openPreparedImporter(recipe: recipeForImport, sourceInfo: prepared.sourceInfo)
        }
    }

    @MainActor
    private func refreshSidebarCollections() async {
        guard isRegularWidthLayout else {
            sidebarCollections = []
            if case .collection = selectedTab {
                selectedTab = .cook
            } else if selectedTab == .collections {
                selectedTab = .cook
            }
            return
        }

        do {
            let allCollections = try await dependencies.collectionRepository.fetchAll()
            let ownedCollections: [Collection]

            if let currentUserID = CurrentUserSession.shared.userId {
                ownedCollections = allCollections.filter { $0.userId == currentUserID }
            } else {
                ownedCollections = allCollections
            }

            sidebarCollections = ownedCollections.sorted { $0.updatedAt > $1.updatedAt }

            if case let .collection(collectionID) = selectedTab,
               !sidebarCollections.contains(where: { $0.id == collectionID }) {
                selectedTab = .cook
            }
        } catch {
            AppLogger.general.warning("⚠️ Failed to refresh sidebar collections: \(error.localizedDescription)")
        }
    }

    private func collectionSidebarLabel(for collection: Collection) -> String {
        collection.name
    }

    private func collectionSidebarSystemImage(for collection: Collection) -> String {
        collection.symbolName ?? "folder.fill"
    }

    @MainActor
    private func applyOptimisticSidebarCollectionUpdate(_ notification: Notification) {
        guard isRegularWidthLayout,
              let updatedCollection = notification.userInfo?["collection"] as? Collection else {
            return
        }

        if let currentUserID = CurrentUserSession.shared.userId,
           updatedCollection.userId != currentUserID {
            return
        }

        if let existingIndex = sidebarCollections.firstIndex(where: { $0.id == updatedCollection.id }) {
            sidebarCollections[existingIndex] = updatedCollection
        }

        sidebarCollections.sort { $0.updatedAt > $1.updatedAt }
    }

    @MainActor
    private func applyOptimisticSidebarCollectionInsert(_ notification: Notification) {
        guard isRegularWidthLayout,
              let insertedCollection = notification.userInfo?["collection"] as? Collection else {
            return
        }

        if let currentUserID = CurrentUserSession.shared.userId,
           insertedCollection.userId != currentUserID {
            return
        }

        guard !sidebarCollections.contains(where: { $0.id == insertedCollection.id }) else {
            return
        }

        sidebarCollections.insert(insertedCollection, at: 0)
        sidebarCollections.sort { $0.updatedAt > $1.updatedAt }
    }
}

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil)
}
