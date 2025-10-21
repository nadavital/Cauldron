//
//  SharingTabViewModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftUI
import Combine
import os

@MainActor
class SharingTabViewModel: ObservableObject {
    static let shared = SharingTabViewModel()

    @Published var sharedRecipes: [SharedRecipe] = []
    @Published var isLoading = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""

    private(set) var dependencies: DependencyContainer?
    private var hasLoadedOnce = false

    private init() {
        // Private init for singleton
    }

    func configure(dependencies: DependencyContainer) {
        self.dependencies = dependencies
    }

    func loadSharedRecipes() async {
        guard let dependencies = dependencies else {
            AppLogger.general.warning("SharingTabViewModel not configured with dependencies")
            return
        }

        // Only show loading indicator on first load
        // After that, show cached data while refreshing in background
        if !hasLoadedOnce {
            isLoading = true
        }
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            sharedRecipes = try await dependencies.sharingService.getSharedRecipes()
            AppLogger.general.info("Loaded \(self.sharedRecipes.count) shared recipes")
        } catch {
            AppLogger.general.error("Failed to load shared recipes: \(error.localizedDescription)")
            alertMessage = "Failed to load shared recipes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    func copyToPersonalCollection(_ sharedRecipe: SharedRecipe) async {
        guard let dependencies = dependencies else { return }
        do {
            let copiedRecipe = try await dependencies.sharingService.copySharedRecipeToPersonal(sharedRecipe)
            alertMessage = "'\(copiedRecipe.title)' has been copied to your recipes!"
            showSuccessAlert = true
            AppLogger.general.info("Copied shared recipe to personal collection")
        } catch {
            AppLogger.general.error("Failed to copy recipe: \(error.localizedDescription)")
            alertMessage = "Failed to copy recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    func removeSharedRecipe(_ sharedRecipe: SharedRecipe) async {
        guard let dependencies = dependencies else { return }
        do {
            try await dependencies.sharingService.removeSharedRecipe(sharedRecipe)
            await loadSharedRecipes() // Refresh the list
            AppLogger.general.info("Removed shared recipe")
        } catch {
            AppLogger.general.error("Failed to remove shared recipe: \(error.localizedDescription)")
            alertMessage = "Failed to remove shared recipe: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
    
    func createDemoUsers() async {
        guard let dependencies = dependencies else { return }
        do {
            try await dependencies.sharingService.createDemoUsers()
            alertMessage = "Demo users created successfully!"
            showSuccessAlert = true
        } catch {
            AppLogger.general.error("Failed to create demo users: \(error.localizedDescription)")
            alertMessage = "Failed to create demo users: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
