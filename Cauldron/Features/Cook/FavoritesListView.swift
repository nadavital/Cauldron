//
//  FavoritesListView.swift
//  Cauldron
//
//  Full list view for favorite recipes
//

import SwiftUI
import os

/// Full list view for favorite recipes
struct FavoritesListView: View {
    let recipes: [Recipe]
    let dependencies: DependencyContainer

    @State private var localRecipes: [Recipe]

    init(recipes: [Recipe], dependencies: DependencyContainer) {
        self.recipes = recipes
        self.dependencies = dependencies
        self._localRecipes = State(initialValue: recipes)
    }

    var body: some View {
        List {
            Section {
                Text("Recipes you've marked as favorites")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(localRecipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                    RecipeRowView(recipe: recipe, dependencies: dependencies)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task {
                            await deleteRecipe(recipe)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)

                    Button {
                        Task {
                            try? await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                            // Remove from local list since this is favorites view
                            localRecipes.removeAll { $0.id == recipe.id }
                        }
                    } label: {
                        Label("Unfavorite", systemImage: "star.slash")
                    }
                    .tint(.yellow)
                }
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            localRecipes = recipes
        }
        .onChange(of: recipes) { newRecipes in
            localRecipes = newRecipes
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { notification in
            if let deletedRecipeId = notification.object as? UUID {
                localRecipes.removeAll { $0.id == deletedRecipeId }
            }
        }
    }

    private func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await dependencies.recipeRepository.delete(id: recipe.id)
            // UI update handled by RecipeDeleted notification listener
        } catch {
            AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
        }
    }
}
