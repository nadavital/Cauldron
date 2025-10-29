//
//  CollectionDetailView.swift
//  Cauldron
//
//  Created by Claude on 10/29/25.
//

import SwiftUI
import os

struct CollectionDetailView: View {
    let collection: Collection
    let dependencies: DependencyContainer

    @State private var recipes: [Recipe] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var showingEditSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return recipes
        }
        return recipes.filter { recipe in
            recipe.title.localizedCaseInsensitiveContains(searchText) ||
            recipe.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        List {
            // Header with collection info
            Section {
                VStack(spacing: 16) {
                    // Icon
                    if let emoji = collection.emoji {
                        ZStack {
                            Circle()
                                .fill(collectionColor.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Text(emoji)
                                .font(.system(size: 50))
                        }
                    } else {
                        ZStack {
                            Circle()
                                .fill(collectionColor.opacity(0.15))
                                .frame(width: 80, height: 80)

                            Image(systemName: "folder.fill")
                                .font(.system(size: 40))
                                .foregroundColor(collectionColor)
                        }
                    }

                    // Name and count
                    VStack(spacing: 4) {
                        Text(collection.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)

                        Text("\(collection.recipeCount) recipe\(collection.recipeCount == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Visibility badge
                    HStack(spacing: 4) {
                        Image(systemName: visibilityIcon)
                            .font(.caption)
                        Text(visibilityText)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            // Recipes
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if filteredRecipes.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)

                        Text(searchText.isEmpty ? "No recipes in this collection" : "No recipes found")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if searchText.isEmpty {
                            Text("Add recipes from the recipe detail view")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredRecipes) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe, dependencies: dependencies)
                        } label: {
                            RecipeRowView(recipe: recipe)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await removeRecipe(recipe)
                                }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Collection", systemImage: "pencil")
                    }

                    Button {
                        shareCollection()
                    } label: {
                        Label("Share Collection", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            CollectionFormView(collectionToEdit: collection)
                .environment(\.dependencies, dependencies)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await loadRecipes()
        }
        .refreshable {
            await loadRecipes()
        }
    }

    // MARK: - Actions

    private func loadRecipes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch all recipes (owned + referenced)
            var allRecipes = try await dependencies.recipeRepository.fetchAll()

            // Add referenced recipes if available
            if let userId = CurrentUserSession.shared.userId {
                let references = try await dependencies.cloudKitService.fetchRecipeReferences(forUserId: userId)

                for reference in references {
                    // Fetch the actual recipe from public database if needed
                    // For now, we'll just use local recipes
                }
            }

            // Filter to only recipes in this collection
            recipes = allRecipes.filter { recipe in
                collection.recipeIds.contains(recipe.id)
            }

            AppLogger.general.info("✅ Loaded \(recipes.count) recipes for collection: \(collection.name)")
        } catch {
            AppLogger.general.error("❌ Failed to load recipes: \(error.localizedDescription)")
            errorMessage = "Failed to load recipes: \(error.localizedDescription)"
            showError = true
        }
    }

    private func removeRecipe(_ recipe: Recipe) async {
        do {
            try await dependencies.collectionRepository.removeRecipe(recipe.id, from: collection.id)
            await loadRecipes()  // Refresh list
            AppLogger.general.info("✅ Removed recipe from collection")
        } catch {
            AppLogger.general.error("❌ Failed to remove recipe: \(error.localizedDescription)")
            errorMessage = "Failed to remove recipe: \(error.localizedDescription)"
            showError = true
        }
    }

    private func shareCollection() {
        // TODO: Implement collection sharing
        AppLogger.general.info("Share collection: \(collection.name)")
    }

    // MARK: - Helpers

    private var collectionColor: Color {
        if let colorHex = collection.color {
            return Color(hex: colorHex) ?? .cauldronOrange
        }
        return .cauldronOrange
    }

    private var visibilityIcon: String {
        switch collection.visibility {
        case .privateRecipe:
            return "lock.fill"
        case .friendsOnly:
            return "person.2.fill"
        case .publicRecipe:
            return "globe"
        }
    }

    private var visibilityText: String {
        switch collection.visibility {
        case .privateRecipe:
            return "Private"
        case .friendsOnly:
            return "Friends"
        case .publicRecipe:
            return "Public"
        }
    }
}

#Preview {
    NavigationStack {
        CollectionDetailView(
            collection: Collection.new(name: "Holiday Foods", userId: UUID()),
            dependencies: DependencyContainer.preview()
        )
    }
}
