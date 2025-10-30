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
    @Published var sharedCollections: [Collection] = []
    @Published var isLoading = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var alertMessage = ""

    private(set) var dependencies: DependencyContainer?
    private var hasLoadedOnce = false

    // Track which shared recipes have been saved as RecipeReferences
    // Maps recipe.id -> reference.id
    private var savedReferences: [UUID: UUID] = [:]

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

            // Load RecipeReferences to track which recipes have been saved
            await loadSavedReferences()

            // Load shared collections from friends
            await loadSharedCollections()
        } catch {
            AppLogger.general.error("Failed to load shared recipes: \(error.localizedDescription)")
            alertMessage = "Failed to load shared recipes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Load shared collections from friends
    private func loadSharedCollections() async {
        guard let dependencies = dependencies else { return }

        do {
            guard let currentUserId = CurrentUserSession.shared.userId else {
                sharedCollections = []
                return
            }

            // Get list of friend user IDs
            let connections = try await dependencies.connectionRepository.fetchAcceptedConnections(forUserId: currentUserId)

            let friendIds = connections.compactMap { connection in
                connection.otherUserId(currentUserId: currentUserId)
            }

            guard !friendIds.isEmpty else {
                sharedCollections = []
                return
            }

            // Fetch shared collections from friends
            sharedCollections = try await dependencies.cloudKitService.fetchSharedCollections(friendIds: friendIds)
            AppLogger.general.info("Loaded \(self.sharedCollections.count) shared collections")
        } catch {
            AppLogger.general.warning("Failed to load shared collections: \(error.localizedDescription)")
            sharedCollections = []
            // Non-critical failure - don't show error alert
        }
    }

    /// Load saved RecipeReferences to track which shared recipes the user has saved
    private func loadSavedReferences() async {
        guard let dependencies = dependencies,
              let userId = CurrentUserSession.shared.userId else {
            return
        }

        do {
            let references = try await dependencies.recipeReferenceManager.fetchReferences(for: userId)

            // Build map of recipe ID -> reference ID
            savedReferences.removeAll()
            for reference in references {
                savedReferences[reference.originalRecipeId] = reference.id
            }

            AppLogger.general.info("Loaded \(references.count) saved recipe references for tracking")
        } catch {
            AppLogger.general.warning("Failed to load saved references: \(error.localizedDescription)")
            // Non-critical failure - continue without reference tracking
        }
    }

    /// Check if a shared recipe has been saved as a RecipeReference
    func hasReference(for recipeId: UUID) -> Bool {
        savedReferences[recipeId] != nil
    }
    
    func copyToPersonalCollection(_ sharedRecipe: SharedRecipe) async {
        guard let dependencies = dependencies else { return }
        do {
            let copiedRecipe = try await dependencies.sharingService.copySharedRecipeToPersonal(sharedRecipe)
            AppLogger.general.info("Copied shared recipe to personal collection: \(copiedRecipe.title)")
            // Toast notification is shown in SharedRecipeDetailView
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
}
