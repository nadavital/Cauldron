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
    
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var localRecipes: [Recipe]
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    init(recipes: [Recipe], dependencies: DependencyContainer) {
        self.recipes = recipes
        self.dependencies = dependencies
        self._localRecipes = State(initialValue: recipes)
    }

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }
    
    var body: some View {
        contentView
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                recipeLayoutMenu
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if usesGridRecipeLayout {
            gridContent
        } else {
            listContent
        }
    }

    private var listContent: some View {
        List {
            ForEach(localRecipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                    RecipeRowView(recipe: recipe, dependencies: dependencies)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    deleteButton(for: recipe)
                    favoriteButton(for: recipe)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: recipeGridColumns, spacing: 16) {
                ForEach(localRecipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                        RecipeCardView(recipe: recipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        deleteButton(for: recipe)
                        favoriteButton(for: recipe)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var recipeLayoutMenu: some View {
        RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
            storedRecipeLayoutMode = mode.rawValue
        }
    }

    private func deleteButton(for recipe: Recipe) -> some View {
        Button(role: .destructive) {
            Task {
                await deleteRecipe(recipe)
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
        .tint(.red)
    }

    private func favoriteButton(for recipe: Recipe) -> some View {
        Button {
            Task {
                try? await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
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

    private var recipeGridColumns: [GridItem] {
        RecipeLayoutMode.defaultGridColumns
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
