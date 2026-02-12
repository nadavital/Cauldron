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
enum AppTab: String, Hashable {
    case cook
    case groceries
    case sharing
    case search
}

/// Main tab-based navigation view
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    let dependencies: DependencyContainer
    let preloadedData: PreloadedRecipeData?
    @State private var selectedTab: AppTab = .cook
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

    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        self.dependencies = dependencies
        self.preloadedData = preloadedData
        self.connectionManager = dependencies.connectionManager
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Cook", systemImage: "flame.fill", value: .cook) {
                CookTabView(dependencies: dependencies, preloadedData: preloadedData)
            }

            Tab("Groceries", systemImage: "cart", value: .groceries) {
                GroceriesView(dependencies: dependencies)
            }

            Tab("Friends", systemImage: "person.2.fill", value: .sharing) {
                FriendsTabView(dependencies: dependencies)
            }
            .badge(connectionManager.pendingRequestsCount)

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(dependencies: dependencies, navigationPath: $searchNavigationPath)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: isCookModeActive) {
            CookModeBanner(coordinator: dependencies.cookModeCoordinator)
                .contentShape(Rectangle())
                .onTapGesture {
                    dependencies.cookModeCoordinator.expandToFullScreen()
                }
        }
        .sheet(isPresented: Binding(
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            openPendingImporterIfNeeded()
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
}

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil)
}
