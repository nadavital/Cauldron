//
//  MainTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import SwiftUI
import Combine

/// Main tab-based navigation view
struct MainTabView: View {
    let dependencies: DependencyContainer
    
    var body: some View {
        TabView {     
            Tab("Cook", systemImage: "flame.fill") {
                CookTabView(dependencies: dependencies)
            }
            
            Tab("Pantry", systemImage: "cabinet") {
                PantryView(dependencies: dependencies)
            }
            
            Tab("Groceries", systemImage: "cart") {
                GroceriesView(dependencies: dependencies)
            }
            
            Tab("Sharing", systemImage: "person.2") {
                SharingTabView(dependencies: dependencies)
            }
            
            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                SearchTabView(dependencies: dependencies)
            }
        }
        .tint(.cauldronOrange)
    }
}

#Preview {
    MainTabView(dependencies: .preview())
}
