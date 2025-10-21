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
    case pantry
    case groceries
    case sharing
    case search
}

/// Main tab-based navigation view
struct MainTabView: View {
    let dependencies: DependencyContainer
    @State private var selectedTab: AppTab = .cook

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Cook", systemImage: "flame.fill", value: .cook) {
                CookTabView(dependencies: dependencies)
            }

            Tab("Pantry", systemImage: "cabinet", value: .pantry) {
                PantryView(dependencies: dependencies)
            }

            Tab("Groceries", systemImage: "cart", value: .groceries) {
                GroceriesView(dependencies: dependencies)
            }

            Tab("Sharing", systemImage: "person.2", value: .sharing) {
                SharingTabView(dependencies: dependencies)
            }

            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchTabView(dependencies: dependencies)
            }
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
            // Switch to Sharing tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Sharing tab from notification")
            selectedTab = .sharing
        }
    }
}

#Preview {
    MainTabView(dependencies: .preview())
}
