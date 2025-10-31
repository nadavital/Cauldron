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

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Cook", systemImage: "flame.fill", value: .cook) {
                CookTabView(dependencies: dependencies, preloadedData: preloadedData)
            }

            Tab("Groceries", systemImage: "cart", value: .groceries) {
                GroceriesView(dependencies: dependencies)
            }

            Tab("Friends", systemImage: "person.2.fill", value: .sharing) {
                SharingTabView(dependencies: dependencies)
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(dependencies: dependencies)
            }
        }
        .tabViewBottomAccessory {
            // Persistent cook mode banner (only visible when cook mode is active)
            if dependencies.cookModeCoordinator.isActive {
                CookModeBanner(coordinator: dependencies.cookModeCoordinator)
            }
        }
        .sheet(isPresented: Binding(
            get: { dependencies.cookModeCoordinator.showFullScreen },
            set: { dependencies.cookModeCoordinator.showFullScreen = $0 }
        )) {
            // Sheet presentation for cook mode (presented when banner is tapped or cook mode starts)
            if let recipe = dependencies.cookModeCoordinator.currentRecipe {
                NavigationStack {
                    CookModeView(
                        recipe: recipe,
                        coordinator: dependencies.cookModeCoordinator,
                        dependencies: dependencies
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
            // Switch to Friends tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Friends tab from notification")
            selectedTab = .sharing
        }
    }
}

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil)
}
