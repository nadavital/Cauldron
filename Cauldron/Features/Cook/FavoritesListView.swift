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
    private enum RecipeLayoutMode: String {
        case auto
        case compact
        case grid
    }

    let recipes: [Recipe]
    let dependencies: DependencyContainer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var localRecipes: [Recipe]
    @AppStorage("recipes.layoutMode") private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    init(recipes: [Recipe], dependencies: DependencyContainer) {
        self.recipes = recipes
        self.dependencies = dependencies
        self._localRecipes = State(initialValue: recipes)
    }

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        if storedMode == .auto {
            return horizontalSizeClass == .regular ? .grid : .compact
        }
        return storedMode
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
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
                    deleteButton(for: recipe)
                    unfavoriteButton(for: recipe)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recipes you've marked as favorites")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: recipeGridColumns, spacing: 16) {
                    ForEach(localRecipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                            RecipeCardView(recipe: recipe, dependencies: dependencies)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            deleteButton(for: recipe)
                            unfavoriteButton(for: recipe)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var recipeLayoutMenu: some View {
        Menu {
            Button {
                storedRecipeLayoutMode = RecipeLayoutMode.grid.rawValue
            } label: {
                HStack {
                    Label("Grid", systemImage: "square.grid.2x2")
                    if resolvedRecipeLayoutMode == .grid {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                storedRecipeLayoutMode = RecipeLayoutMode.compact.rawValue
            } label: {
                HStack {
                    Label("Compact", systemImage: "list.bullet")
                    if resolvedRecipeLayoutMode == .compact {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Image(systemName: resolvedRecipeLayoutMode == .grid ? "square.grid.2x2" : "list.bullet")
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

    private func unfavoriteButton(for recipe: Recipe) -> some View {
        Button {
            Task {
                try? await dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                localRecipes.removeAll { $0.id == recipe.id }
            }
        } label: {
            Label("Unfavorite", systemImage: "star.slash")
        }
        .tint(.yellow)
    }

    private var recipeGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 16)]
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
