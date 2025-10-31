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
    @Namespace private var cookModeNamespace
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Group {
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
            .if(dependencies.cookModeCoordinator.isActive) { view in
                view.tabViewBottomAccessory {
                    CookModeBanner(
                        coordinator: dependencies.cookModeCoordinator,
                        namespace: cookModeNamespace
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openExpanded()
                    }
                }
            }
        }
        // Expanded overlay (same hierarchy allows matchedGeometryEffect to work)
        .overlay(alignment: .bottom) {
            if dependencies.cookModeCoordinator.showFullScreen,
               let recipe = dependencies.cookModeCoordinator.currentRecipe {
                NavigationStack {
                    CookModeView(
                        recipe: recipe,
                        coordinator: dependencies.cookModeCoordinator,
                        dependencies: dependencies,
                        namespace: cookModeNamespace
                    )
                }
                .offset(y: dragOffset)
                .gesture(dragToDismiss)
                .transition(.identity)
                .zIndex(1)
                .background(
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            closeExpanded()
                        }
                )
            }
        }
        .tint(.cauldronOrange)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NavigateToConnections"))) { _ in
            // Switch to Friends tab when connection notification is tapped
            AppLogger.general.info("📍 Switching to Friends tab from notification")
            selectedTab = .sharing
        }
    }

    // MARK: - Gestures & Helpers

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                let shouldClose = value.translation.height > 120 || value.predictedEndTranslation.height > 200
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                    if shouldClose {
                        dependencies.cookModeCoordinator.minimizeToBackground()
                    }
                    dragOffset = 0
                }
                if shouldClose {
                    lightHaptic()
                }
            }
    }

    private func openExpanded() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            dependencies.cookModeCoordinator.expandToFullScreen()
        }
        lightHaptic()
    }

    private func closeExpanded() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            dependencies.cookModeCoordinator.minimizeToBackground()
            dragOffset = 0
        }
    }

    private func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    MainTabView(dependencies: .preview(), preloadedData: nil)
}
