//
//  AllFriendsListViews.swift
//  Cauldron
//
//  Extracted from FriendsTabView.swift: full-list "See All" screens.
//

import SwiftUI
import os

// MARK: - All Friends' Recipes List View

/// Full list view for friends' recipes (accessed via "See All")
struct AllFriendsRecipesListView: View {
    let recipes: [SharedRecipe]
    let title: String
    let dependencies: DependencyContainer
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage(RecipeLayoutMode.appStorageKey) private var storedRecipeLayoutMode = RecipeLayoutMode.auto.rawValue

    private var resolvedRecipeLayoutMode: RecipeLayoutMode {
        let storedMode = RecipeLayoutMode(rawValue: storedRecipeLayoutMode) ?? .auto
        return storedMode.resolved(for: horizontalSizeClass)
    }

    private var usesGridRecipeLayout: Bool {
        resolvedRecipeLayoutMode == .grid
    }

    var body: some View {
        contentView
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                RecipeLayoutToolbarButton(resolvedMode: resolvedRecipeLayoutMode) { mode in
                    storedRecipeLayoutMode = mode.rawValue
                }
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
            ForEach(recipes) { sharedRecipe in
                NavigationLink(destination: RecipeDetailView(
                    recipe: sharedRecipe.recipe,
                    dependencies: dependencies,
                    sharedBy: sharedRecipe.sharedBy,
                    sharedAt: sharedRecipe.sharedAt
                )) {
                    SharedRecipeRowView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                }
            }
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: RecipeLayoutMode.defaultGridColumns, spacing: 16) {
                ForEach(recipes) { sharedRecipe in
                    NavigationLink(destination: RecipeDetailView(
                        recipe: sharedRecipe.recipe,
                        dependencies: dependencies,
                        sharedBy: sharedRecipe.sharedBy,
                        sharedAt: sharedRecipe.sharedAt
                    )) {
                        RecipeCardView(sharedRecipe: sharedRecipe, dependencies: dependencies)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct AllFriendsCollectionsListView: View {
    let collections: [Collection]
    let dependencies: DependencyContainer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var collectionImageCache: [UUID: [URL?]] = [:]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(collections, id: \.id) { collection in
                    NavigationLink(destination: CollectionDetailView(
                        collection: collection,
                        dependencies: dependencies
                    )) {
                        CollectionCardView(
                            collection: collection,
                            recipeImages: collectionImageCache[collection.id] ?? [],
                            preferredWidth: nil,
                            dependencies: dependencies
                        )
                    }
                    .buttonStyle(.plain)
                    .task(id: collection.id) {
                        if collectionImageCache[collection.id] == nil {
                            let images = await loadRecipeImages(for: collection)
                            collectionImageCache[collection.id] = images
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .navigationTitle("Friends' Collections")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var gridColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 190, maximum: 240), spacing: 12)]
        }
        return [
            GridItem(.flexible(minimum: 150), spacing: 12),
            GridItem(.flexible(minimum: 150), spacing: 12)
        ]
    }

    @MainActor
    private func loadRecipeImages(for collection: Collection) async -> [URL?] {
        await SharedCollectionPreviewLoader.loadPreviewImageURLs(
            for: collection,
            dependencies: dependencies
        )
    }
}
