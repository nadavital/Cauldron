//
//  SharedCollectionDetailView.swift
//  Cauldron
//
//  Created by Claude on 10/30/25.
//

import SwiftUI
import os

struct SharedCollectionDetailView: View {
    let collection: Collection
    let dependencies: DependencyContainer

    @State private var recipes: [Recipe] = []
    @State private var isLoading = true
    @State private var isSavingReference = false
    @State private var hasExistingReference = false
    @State private var isCheckingReference = true
    @State private var showReferenceToast = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var hiddenRecipeCount = 0
    @State private var isFriendWithOwner = false
    @Environment(\.dismiss) private var dismiss

    private var loader: SharedCollectionLoader {
        SharedCollectionLoader(dependencies: dependencies)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Collection Header
                collectionHeaderSection

                // Recipes in this collection
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading recipes...")
                        Spacer()
                    }
                    .padding(.vertical, 40)
                } else if recipes.isEmpty {
                    emptyStateSection
                } else {
                    recipesSection

                    // Show info if some recipes are hidden
                    if hiddenRecipeCount > 0 {
                        hiddenRecipesInfoSection
                    }
                }
            }
            .padding()
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Save Collection Reference (bookmark)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task {
                        await saveCollectionReference()
                    }
                } label: {
                    if isSavingReference {
                        ProgressView()
                    } else if hasExistingReference {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: "bookmark")
                    }
                }
                .disabled(isSavingReference || hasExistingReference || isCheckingReference)
            }
        }
        .toast(isShowing: $showReferenceToast, icon: "bookmark.fill", message: "Collection saved!")
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await checkFriendshipStatus()
            await loadRecipes()
            await checkForExistingReference()
        }
    }

    // MARK: - View Sections

    private var collectionHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon and basic info
            HStack(spacing: 16) {
                // Collection icon
                ZStack {
                    Circle()
                        .fill(collectionColor.opacity(0.15))
                        .frame(width: 80, height: 80)

                    if let emoji = collection.emoji {
                        Text(emoji)
                            .font(.system(size: 50))
                    } else {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundColor(collectionColor)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(collection.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: collection.visibility.icon)
                            .font(.caption)
                        Text(collection.visibility.displayName)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Description if available
            if let description = collection.description, !description.isEmpty {
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
            }

            // Shared collection info banner
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.cauldronOrange)
                Text("This is a shared collection. Save it to access it from your Collections tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.cauldronOrange.opacity(0.1))
            .cornerRadius(12)
        }
    }

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text("No Recipes Yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This collection doesn't have any recipes yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    private var hiddenRecipesInfoSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundColor(.secondary)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(hiddenRecipeCount) private recipe\(hiddenRecipeCount == 1 ? "" : "s") not shown")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("These recipes are private and cannot be viewed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recipes")
                    .font(.title3)
                    .fontWeight(.bold)

                if !recipes.isEmpty {
                    Text("(\(recipes.count))")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            ForEach(recipes) { recipe in
                NavigationLink {
                    // Navigate to RecipeDetailView
                    // Since these are recipes from a shared collection, we provide shared context
                    if let sharedRecipe = createSharedRecipe(from: recipe) {
                        RecipeDetailView(
                            recipe: recipe,
                            dependencies: dependencies,
                            sharedBy: sharedRecipe.sharedBy,
                            sharedAt: sharedRecipe.sharedAt
                        )
                    } else {
                        // Fallback to regular recipe detail
                        RecipeDetailView(recipe: recipe, dependencies: dependencies)
                    }
                } label: {
                    RecipeRowView(recipe: recipe, dependencies: dependencies)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func checkFriendshipStatus() async {
        guard let currentUserId = CurrentUserSession.shared.userId else {
            isFriendWithOwner = false
            return
        }

        // Check if we're friends with the collection owner
        await dependencies.connectionManager.loadConnections(forUserId: currentUserId)
        let connectionStatus = dependencies.connectionManager.connectionStatus(with: collection.userId)
        isFriendWithOwner = connectionStatus?.isAccepted ?? false

        AppLogger.general.info("Friendship status with collection owner: \(isFriendWithOwner)")
    }

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        // Check friendship status first
        await checkFriendshipStatus()

        // Load recipes using shared loader
        let result = await loader.loadRecipes(
            from: collection,
            viewerId: CurrentUserSession.shared.userId,
            isFriend: isFriendWithOwner
        )

        recipes = result.visibleRecipes
        hiddenRecipeCount = result.hiddenRecipeCount

        AppLogger.general.info("✅ Loaded \(recipes.count) visible recipes, \(hiddenRecipeCount) hidden")
    }

    private func saveCollectionReference() async {
        isSavingReference = true
        defer { isSavingReference = false }

        do {
            // Get current user
            guard let userId = CurrentUserSession.shared.userId else {
                AppLogger.general.error("Cannot save collection reference - no current user")
                errorMessage = "Please sign in to save collections"
                showError = true
                return
            }

            // Create collection reference
            let reference = CollectionReference.reference(
                userId: userId,
                collection: collection
            )

            // Save to CloudKit PUBLIC database
            try await dependencies.cloudKitService.saveCollectionReference(reference)

            AppLogger.general.info("Saved collection reference: \(collection.name)")

            // Update tracking state immediately
            hasExistingReference = true

            // Notify other views that a collection was added
            NotificationCenter.default.post(name: NSNotification.Name("CollectionAdded"), object: nil)

            // Show toast notification
            withAnimation {
                showReferenceToast = true
            }

            // Dismiss sheet after toast appears
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            dismiss()
        } catch {
            AppLogger.general.error("Failed to save collection reference: \(error.localizedDescription)")
            errorMessage = "Failed to save collection: \(error.localizedDescription)"
            showError = true
        }
    }

    private func checkForExistingReference() async {
        guard let userId = CurrentUserSession.shared.userId else {
            isCheckingReference = false
            return
        }

        do {
            // Check if user already has a reference to this collection
            let references = try await dependencies.cloudKitService.fetchCollectionReferences(forUserId: userId)
            hasExistingReference = references.contains { $0.originalCollectionId == collection.id }
            isCheckingReference = false

            AppLogger.general.info("Reference check complete - hasExistingReference: \(hasExistingReference)")
        } catch {
            AppLogger.general.error("Failed to check for existing reference: \(error.localizedDescription)")
            isCheckingReference = false
        }
    }

    private func copyRecipe(_ recipe: Recipe) async {
        guard let userId = CurrentUserSession.shared.userId else { return }

        do {
            // Create a copy of the recipe owned by the current user using withOwner()
            let copiedRecipe = recipe.withOwner(
                userId,
                originalCreatorId: recipe.ownerId,
                originalCreatorName: recipe.ownerId != nil ? "Collection Owner" : nil  // TODO: Fetch actual creator name
            )
            try await dependencies.recipeRepository.create(copiedRecipe)

            AppLogger.general.info("✅ Copied recipe: \(recipe.title)")
        } catch {
            AppLogger.general.error("❌ Failed to copy recipe: \(error.localizedDescription)")
        }
    }

    // Helper to create SharedRecipe from Recipe
    private func createSharedRecipe(from recipe: Recipe) -> SharedRecipe? {
        // We need to get user info for the owner
        // For now, create a basic SharedRecipe with minimal owner info
        // In a real app, you might want to fetch the owner's User object
        let owner = User(
            id: collection.userId,
            username: "user",  // We don't have this info readily available
            displayName: "Collection Owner",
            createdAt: Date(),
            profileEmoji: nil,
            profileColor: nil
        )

        return SharedRecipe(
            recipe: recipe,
            sharedBy: owner,
            sharedAt: collection.updatedAt ?? collection.createdAt
        )
    }

    // MARK: - Helpers

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }
}

#Preview {
    NavigationStack {
        SharedCollectionDetailView(
            collection: Collection.new(name: "Holiday Foods", userId: UUID()),
            dependencies: DependencyContainer.preview()
        )
    }
}
