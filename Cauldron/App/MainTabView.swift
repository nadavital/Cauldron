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
    let dependencies: DependencyContainer
    let preloadedData: PreloadedRecipeData?
    @State private var selectedTab: AppTab = .cook
    @ObservedObject private var connectionManager: ConnectionManager

    @State private var searchNavigationPath = NavigationPath()

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
        .toast(
            isShowing: Binding(
                get: { dependencies.cookModeCoordinator.showRecipeDeletedToast },
                set: { dependencies.cookModeCoordinator.showRecipeDeletedToast = $0 }
            ),
            icon: "trash.fill",
            message: "Recipe was deleted"
        )
    }
}

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil)
}
