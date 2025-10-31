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
    @Environment(\.dismiss) private var dismiss

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

    private var recipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recipes")
                .font(.title3)
                .fontWeight(.bold)

            ForEach(recipes) { recipe in
                NavigationLink {
                    // Navigate to SharedRecipeDetailView for consistency
                    // Since these are recipes from a shared collection
                    if let sharedRecipe = createSharedRecipe(from: recipe) {
                        SharedRecipeDetailView(
                            sharedRecipe: sharedRecipe,
                            dependencies: dependencies,
                            onCopy: {
                                await copyRecipe(recipe)
                            },
                            onRemove: {
                                // Not applicable for collection recipes
                            }
                        )
                    } else {
                        // Fallback to regular recipe detail if we can't create SharedRecipe
                        RecipeDetailView(recipe: recipe, dependencies: dependencies)
                    }
                } label: {
                    RecipeRowView(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Actions

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        guard !collection.recipeIds.isEmpty else {
            recipes = []
            return
        }

        // Fetch recipes that are in this collection
        // We need to fetch them from CloudKit PUBLIC database since they're shared
        var fetchedRecipes: [Recipe] = []

        for recipeId in collection.recipeIds {
            do {
                // Try to fetch as a public recipe
                let recipe = try await dependencies.cloudKitService.fetchPublicRecipe(
                    recipeId: recipeId,
                    ownerId: collection.userId
                )
                fetchedRecipes.append(recipe)
            } catch {
                AppLogger.general.warning("Failed to fetch recipe \(recipeId) from shared collection: \(error.localizedDescription)")
                // Continue loading other recipes even if one fails
            }
        }

        recipes = fetchedRecipes
        AppLogger.general.info("✅ Loaded \(recipes.count) recipes for shared collection: \(collection.name)")
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
            // Create a copy of the recipe owned by the current user
            let copiedRecipe = Recipe(
                id: UUID(), // New ID for the copy
                title: recipe.title,
                ingredients: recipe.ingredients,
                steps: recipe.steps,
                yields: recipe.yields,
                totalMinutes: recipe.totalMinutes,
                tags: recipe.tags,
                nutrition: recipe.nutrition,
                sourceURL: recipe.sourceURL,
                sourceTitle: recipe.sourceTitle,
                notes: recipe.notes,
                imageURL: recipe.imageURL,
                isFavorite: false,
                visibility: .privateRecipe, // Make it private by default
                ownerId: userId, // Set the current user as owner
                cloudRecordName: nil, // Clear to ensure new CloudKit record
                createdAt: Date(),
                updatedAt: Date()
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
