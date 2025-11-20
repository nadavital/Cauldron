//
//  RecentlyCookedListView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import SwiftUI
import os

/// Full list view for recently cooked recipes
struct RecentlyCookedListView: View {
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
                            // Update the local recipe in the list
                            if let index = localRecipes.firstIndex(where: { $0.id == recipe.id }) {
                                var updatedRecipe = localRecipes[index]
                                updatedRecipe = Recipe(
                                    id: updatedRecipe.id,
                                    title: updatedRecipe.title,
                                    ingredients: updatedRecipe.ingredients,
                                    steps: updatedRecipe.steps,
                                    yields: updatedRecipe.yields,
                                    totalMinutes: updatedRecipe.totalMinutes,
                                    tags: updatedRecipe.tags,
                                    nutrition: updatedRecipe.nutrition,
                                    sourceURL: updatedRecipe.sourceURL,
                                    sourceTitle: updatedRecipe.sourceTitle,
                                    notes: updatedRecipe.notes,
                                    imageURL: updatedRecipe.imageURL,
                                    isFavorite: !updatedRecipe.isFavorite,
                                    createdAt: updatedRecipe.createdAt,
                                    updatedAt: updatedRecipe.updatedAt
                                )
                                localRecipes[index] = updatedRecipe
                            }
                        }
                    } label: {
                        Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "star.slash" : "star.fill")
                    }
                    .tint(.yellow)
                }
            }
        }
        .navigationTitle("Recently Cooked")
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
