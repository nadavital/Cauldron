//
//  MainTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import Combine
import os
import UIKit

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
    @State private var sidebarRefreshTask: Task<Void, Never>?
    @State private var activeShareImportAcknowledgement: ShareImportAcknowledgement?
    @Binding private var pendingSharedContent: ContentView.SharedContentWrapper?
    @ObservedObject private var connectionManager: ConnectionManager

    @State private var searchNavigationPath = NavigationPath()

    private enum ShareImportAcknowledgement: Equatable {
        case prepared(Data)
        case text(String)
        case url(URL)
    }

    private struct SharedImportRequest: Identifiable {
        let id = UUID()
        let initialURL: URL?
        let initialText: String?
        let preparedRecipe: Recipe?
        let preparedSourceInfo: String?
    }

    private var isCookModeActive: Bool {
        dependencies.cookModeCoordinator.isActive && dependencies.cookModeCoordinator.currentRecipe != nil
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

    init(
        dependencies: DependencyContainer,
        preloadedData: PreloadedRecipeData?,
        pendingSharedContent: Binding<ContentView.SharedContentWrapper?> = .constant(nil)
    ) {
        self.dependencies = dependencies
        self.preloadedData = preloadedData
        self._pendingSharedContent = pendingSharedContent
        self.connectionManager = dependencies.connectionManager
    }

    var body: some View {
        tabScaffoldWithAccessory
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
        .sheet(item: $sharedImportRequest, onDismiss: acknowledgeActiveShareImport) { request in
            ImporterView(
                dependencies: dependencies,
                initialURL: request.initialURL,
                initialText: request.initialText,
                preparedRecipe: request.preparedRecipe,
                preparedSourceInfo: request.preparedSourceInfo
            )
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: .navigateToConnections)) { _ in
            // Switch to Friends tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Friends tab from notification")
            selectedTab = .sharing
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToReferralProfile)) { _ in
            AppLogger.general.info("📍 Switching to Friends tab for referral profile navigation")
            selectedTab = .sharing
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToSharedContent"))) { notification in
            if let contentWrapper = notification.object as? ContentView.SharedContentWrapper {
                AppLogger.general.info("📍 Navigating to shared content in Search tab")
                navigateToSharedContent(contentWrapper)
            }
        }
        .task(id: pendingSharedContent?.id) {
            deliverPendingSharedContentIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToSearchTab"))) { _ in
            // Switch to Search tab when "Find people to add" is tapped from Friends empty state
            AppLogger.general.info("📍 Switching to Search tab to find people")
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .openRecipeImportURL)) { notification in
            guard let url = notification.object as? URL else { return }
            if ShareExtensionImportStore.pendingPreparedRecipe() != nil {
                AppLogger.general.info("📥 Prepared Share Extension payload supersedes URL handoff")
                openPendingImporterIfNeeded()
                return
            }
            AppLogger.general.info("📥 Opening importer from Share Extension URL: \(url.absoluteString)")
            openImporter(with: url, acknowledgement: .url(url))
        }
        .task {
            guard !didCheckInitialPendingImport else { return }
            didCheckInitialPendingImport = true
            openPendingImporterIfNeeded()
        }
        .task {
            scheduleSidebarCollectionsRefresh(delayNanoseconds: 0)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            #if targetEnvironment(macCatalyst)
            resetCatalystWindowTitle()
            #endif
            openPendingImporterIfNeeded()
            scheduleSidebarCollectionsRefresh()
        }
        .onChange(of: horizontalSizeClass) {
            scheduleSidebarCollectionsRefresh()
        }
        .onChange(of: selectedTab) { _, newTab in
            #if targetEnvironment(macCatalyst)
            resetCatalystWindowTitle()
            #endif
            guard isRegularWidthLayout else { return }

            switch newTab {
            case .collection:
                scheduleSidebarCollectionsRefresh()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionMetadataChanged)) { notification in
            applyOptimisticSidebarCollectionUpdate(notification)
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionUpdated)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionRecipesChanged)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .collectionDeleted)) { _ in
            scheduleSidebarCollectionsRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CollectionAdded"))) { notification in
            applyOptimisticSidebarCollectionInsert(notification)
            scheduleSidebarCollectionsRefresh()
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
        .onAppear {
            #if targetEnvironment(macCatalyst)
            resetCatalystWindowTitle()
            #endif
        }
    }

    @ViewBuilder
    private var tabScaffoldWithAccessory: some View {
        if #available(iOS 26.1, macCatalyst 26.1, *) {
            tabScaffold
                // On iPad, this enables the native sidebar-based tab presentation.
                // On iPhone, it keeps standard tab bar behavior.
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: isCookModeActive) {
                    cookModeAccessory
                }
        } else {
            tabScaffold
                // On iPad, this enables the native sidebar-based tab presentation.
                // On iPhone, it keeps standard tab bar behavior.
                .tabViewStyle(.sidebarAdaptable)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if isCookModeActive {
                        cookModeAccessory
                    }
                }
        }
    }

    private var cookModeAccessory: some View {
        CookModeBanner(coordinator: dependencies.cookModeCoordinator)
            .contentShape(Rectangle())
            .onTapGesture {
                dependencies.cookModeCoordinator.expandToFullScreen()
            }
    }

    @MainActor
    private func deliverPendingSharedContentIfNeeded() {
        guard let contentWrapper = pendingSharedContent else { return }
        AppLogger.general.info("📍 Delivering deferred shared content route")
        navigateToSharedContent(contentWrapper)
        pendingSharedContent = nil
    }

    @MainActor
    private func navigateToSharedContent(_ contentWrapper: ContentView.SharedContentWrapper) {
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

            #if targetEnvironment(macCatalyst)
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchTabView(dependencies: dependencies, navigationPath: $searchNavigationPath)
            }
            #else
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(dependencies: dependencies, navigationPath: $searchNavigationPath)
            }
            #endif
        }
    }

    private func openPendingImporterIfNeeded() {
        guard !isSavingPreparedSharedRecipe,
              sharedImportRequest == nil else {
            return
        }

        if let prepared = ShareExtensionImportStore.pendingPreparedRecipe() {
            AppLogger.general.info("📥 Found pending prepared Share Extension recipe payload")
            isSavingPreparedSharedRecipe = true
            Task {
                await autoSavePreparedSharedRecipe(prepared)
            }
            return
        }

        if let pendingText = ShareExtensionImportStore.pendingRecipeText() {
            AppLogger.general.info("📥 Found pending Share Extension text")
            openImporter(withText: pendingText, acknowledgement: .text(pendingText))
            return
        }

        guard let pendingURL = ShareExtensionImportStore.pendingRecipeURL() else {
            return
        }

        AppLogger.general.info("📥 Found pending Share Extension URL: \(pendingURL.absoluteString)")
        openImporter(with: pendingURL, acknowledgement: .url(pendingURL))
    }

    #if targetEnvironment(macCatalyst)
    private func resetCatalystWindowTitle() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }) else {
            return
        }

        // nil restores the default app name ("Cauldron") instead of a dynamic tab/view title.
        windowScene.title = nil
    }
    #endif

    private func openImporter(with url: URL, acknowledgement: ShareImportAcknowledgement? = nil) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: url,
            initialText: nil,
            preparedRecipe: nil,
            preparedSourceInfo: nil
        )
    }

    private func openImporter(withText text: String, acknowledgement: ShareImportAcknowledgement? = nil) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: nil,
            initialText: text,
            preparedRecipe: nil,
            preparedSourceInfo: nil
        )
    }

    private func openPreparedImporter(
        recipe: Recipe,
        sourceInfo: String,
        acknowledgement: ShareImportAcknowledgement? = nil
    ) {
        selectedTab = .cook
        activeShareImportAcknowledgement = acknowledgement
        sharedImportRequest = SharedImportRequest(
            initialURL: nil,
            initialText: nil,
            preparedRecipe: recipe,
            preparedSourceInfo: sourceInfo
        )
    }

    @MainActor
    private func autoSavePreparedSharedRecipe(_ pending: ShareExtensionImportStore.PendingPreparedSharedRecipe) async {
        defer { isSavingPreparedSharedRecipe = false }
        let prepared = pending.preparedRecipe

        let recipeForImport: Recipe
        do {
            let parsedRecipe = try await dependencies.textParser.parse(from: prepared.recipeParserInputText())
            recipeForImport = prepared.recipeMergedWithParsedContent(parsedRecipe)
            AppLogger.general.info("🧠 Reparsed Share Extension payload via text parser before save")
        } catch {
            recipeForImport = prepared.recipe
            AppLogger.general.warning("⚠️ Failed to reparse prepared share recipe; falling back to preprocessed payload: \(error.localizedDescription)")
        }

        guard let userId = CurrentUserSession.shared.userId else {
            AppLogger.general.error("❌ Cannot auto-save prepared share recipe without a current user")
            openPreparedImporter(
                recipe: recipeForImport,
                sourceInfo: prepared.sourceInfo,
                acknowledgement: .prepared(pending.payloadData)
            )
            return
        }

        let recipeToSave = await ImportedRecipeSaveBuilder.recipeForSave(
            from: recipeForImport,
            userId: userId,
            imageManager: dependencies.imageManager
        )

        do {
            try await dependencies.recipeRepository.create(recipeToSave)
            AppLogger.general.info("✅ Auto-saved prepared share recipe: \(recipeToSave.title)")
            ShareExtensionImportStore.acknowledgePreparedRecipe(matching: pending.payloadData)
            NotificationCenter.default.post(name: .recipeAdded, object: recipeToSave.id)
            selectedTab = .cook
            showSharedRecipeSavedToast = true
        } catch {
            AppLogger.general.error("❌ Failed to auto-save prepared share recipe: \(error.localizedDescription)")
            openPreparedImporter(
                recipe: recipeForImport,
                sourceInfo: prepared.sourceInfo,
                acknowledgement: .prepared(pending.payloadData)
            )
        }
    }

    private func acknowledgeActiveShareImport() {
        guard let acknowledgement = activeShareImportAcknowledgement else {
            return
        }

        switch acknowledgement {
        case .prepared(let payloadData):
            ShareExtensionImportStore.acknowledgePreparedRecipe(matching: payloadData)
        case .text(let text):
            ShareExtensionImportStore.acknowledgePendingRecipeText(matching: text)
        case .url(let url):
            ShareExtensionImportStore.acknowledgePendingRecipeURL(matching: url)
        }

        activeShareImportAcknowledgement = nil
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
            let ownedCollections = try await dependencies.collectionRepository.fetchUserCollections(
                ownerId: CurrentUserSession.shared.userId
            )

            sidebarCollections = ownedCollections.sorted { $0.updatedAt > $1.updatedAt }

            if case let .collection(collectionID) = selectedTab,
               !sidebarCollections.contains(where: { $0.id == collectionID }) {
                selectedTab = .cook
            }
        } catch {
            AppLogger.general.warning("⚠️ Failed to refresh sidebar collections: \(error.localizedDescription)")
        }
    }

    private func scheduleSidebarCollectionsRefresh(delayNanoseconds: UInt64 = 150_000_000) {
        sidebarRefreshTask?.cancel()
        sidebarRefreshTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await refreshSidebarCollections()
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
    MainTabView(dependencies: .preview(), preloadedData: nil, pendingSharedContent: .constant(nil))
}
