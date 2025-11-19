//
//  CookTabView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import SwiftUI
import os

/// Main Cook tab - central hub for recipe discovery and cooking
struct CookTabView: View {
    @StateObject private var viewModel: CookTabViewModel
    @State private var showingImporter = false
    @State private var showingEditor = false
    @State private var showingAIGenerator = false
    @State private var selectedRecipe: Recipe?
    @State private var recipeToDelete: Recipe?
    @State private var showDeleteConfirmation = false
    @State private var showSessionConflictAlert = false
    @State private var isAIAvailable = false
    @State private var collectionImageCache: [UUID: [URL?]] = [:]  // Cache recipe images by collection ID

    init(dependencies: DependencyContainer, preloadedData: PreloadedRecipeData?) {
        _viewModel = StateObject(wrappedValue: CookTabViewModel(dependencies: dependencies, preloadedData: preloadedData))
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // My Collections
                    collectionsSection

                    // Recently Cooked
                    if !viewModel.recentlyCookedRecipes.isEmpty {
                        recentlyCookedSection
                    }

                    // Favorites
                    if !viewModel.favoriteRecipes.isEmpty {
                        favoritesSection
                    }

                    // All Recipes
                    allRecipesSection
                }
                .padding()
            }
            .navigationTitle("Cook")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    AddRecipeMenu(
                        dependencies: viewModel.dependencies,
                        showingEditor: $showingEditor,
                        showingAIGenerator: $showingAIGenerator,
                        showingImporter: $showingImporter
                    )
                }
            }
            .sheet(isPresented: $showingImporter, onDismiss: {
                // Refresh data when importer is dismissed
                Task {
                    await viewModel.loadData()
                }
            }) {
                ImporterView(dependencies: viewModel.dependencies)
            }
            .sheet(isPresented: $showingEditor, onDismiss: {
                // Refresh data when editor is dismissed
                Task {
                    await viewModel.loadData()
                }
            }) {
                RecipeEditorView(dependencies: viewModel.dependencies, recipe: selectedRecipe)
            }
            .sheet(isPresented: $showingAIGenerator, onDismiss: {
                // Refresh data when AI generator is dismissed
                Task {
                    await viewModel.loadData()
                }
            }) {
                AIRecipeGeneratorView(dependencies: viewModel.dependencies)
            }
            .alert("Recipe Already Cooking", isPresented: $showSessionConflictAlert) {
                Button("Cancel", role: .cancel) {}
                Button("End & Start New") {
                    Task {
                        await viewModel.dependencies.cookModeCoordinator.startPendingRecipe()
                    }
                }
            } message: {
                if let currentRecipe = viewModel.dependencies.cookModeCoordinator.currentRecipe,
                   let pendingRecipe = selectedRecipe {
                    Text("End '\(currentRecipe.title)' to start cooking '\(pendingRecipe.title)'?")
                }
            }
            .alert("Delete Recipe?", isPresented: $showDeleteConfirmation, presenting: recipeToDelete) { recipe in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteRecipe(recipe)
                }
            } message: { recipe in
                Text("Are you sure you want to delete \"\(recipe.title)\"? This cannot be undone.")
            }
            .task {
                // Check if Apple Intelligence is available
                isAIAvailable = await viewModel.dependencies.foundationModelsService.isAvailable
            }
            .refreshable {
                // Force sync when user pulls to refresh
                await viewModel.loadData(forceSync: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeAdded"))) { _ in
                // Refresh when a recipe is added from another tab
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CollectionAdded"))) { _ in
                // Refresh when a collection is added from another tab
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeDeleted"))) { _ in
                // Refresh when a recipe is deleted from another tab
                Task {
                    await viewModel.loadData()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecipeUpdated"))) { _ in
                // Refresh when a recipe is updated (e.g., edited from detail view)
                Task {
                    await viewModel.loadData()
                }
            }
        }
    }

    private var recentlyCookedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.cauldronOrange)
                Text("Recently Cooked")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                NavigationLink(destination: RecentlyCookedListView(recipes: viewModel.recentlyCookedRecipes, dependencies: viewModel.dependencies)) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.recentlyCookedRecipes.prefix(10)) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)) {
                            RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            recipeContextMenu(for: recipe)
                        } preview: {
                            RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                                .padding()
                                .background(Color(.systemBackground))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Favorites")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                NavigationLink(destination: FavoritesListView(recipes: viewModel.favoriteRecipes, dependencies: viewModel.dependencies)) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.favoriteRecipes.prefix(10)) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)) {
                            RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            recipeContextMenu(for: recipe)
                        } preview: {
                            RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                                .padding()
                                .background(Color(.systemBackground))
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.cauldronOrange)
                Text("My Collections")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()

                NavigationLink(destination: CollectionsListView(dependencies: viewModel.dependencies)) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }

            if viewModel.collections.isEmpty {
                Text("Organize your recipes into collections")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.collections.prefix(10)) { collection in
                            NavigationLink(destination: CollectionDetailView(collection: collection, dependencies: viewModel.dependencies)) {
                                CollectionCardView(
                                    collection: collection,
                                    recipeImages: collectionImageCache[collection.id] ?? []
                                )
                            }
                            .buttonStyle(.plain)
                            .task(id: collection.id) {
                                // Load recipe images if not cached
                                if collectionImageCache[collection.id] == nil {
                                    let images = await viewModel.getRecipeImages(for: collection)
                                    collectionImageCache[collection.id] = images
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var allRecipesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    Text("All Recipes")
                        .font(.title2)
                        .fontWeight(.bold)
                } icon: {
                    Image(systemName: "fork.knife")
                        .foregroundColor(.cauldronOrange)
                }

                Spacer()
                
                NavigationLink(destination: AllRecipesListView(recipes: viewModel.allRecipes, dependencies: viewModel.dependencies)) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.cauldronOrange)
                }
            }
            
            if viewModel.allRecipes.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(viewModel.allRecipes.prefix(10)) { recipe in
                            NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: viewModel.dependencies)) {
                                RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                recipeContextMenu(for: recipe)
                            } preview: {
                                RecipeCardView(recipe: recipe, dependencies: viewModel.dependencies)
                                    .frame(width: 200)
                                    .padding()
                                    .background(Color(.systemBackground))
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Recipes Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Add your first recipe to get started")
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                // AI Generation button (if available)
                if isAIAvailable {
                    Button {
                        showingAIGenerator = true
                    } label: {
                        HStack {
                            Image(systemName: "apple.intelligence")
                            Text("Generate with AI")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }

                HStack(spacing: 16) {
                    Button {
                        showingEditor = true
                    } label: {
                        Label("Create", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)

                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cauldronOrange)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }
    
    
    @ViewBuilder
    private func recipeContextMenu(for recipe: Recipe) -> some View {
        Button {
            handleStartCooking(recipe: recipe)
        } label: {
            Label("Start Cooking", systemImage: "flame.fill")
        }
        
        Button {
            Task {
                try? await viewModel.dependencies.recipeRepository.toggleFavorite(id: recipe.id)
                await viewModel.loadData()
            }
        } label: {
            Label(recipe.isFavorite ? "Unfavorite" : "Favorite", systemImage: recipe.isFavorite ? "star.slash" : "star.fill")
        }
        
        Button {
            selectedRecipe = recipe
            showingEditor = true
        } label: {
            Label("Edit Recipe", systemImage: "pencil")
        }
        
        Button(role: .destructive) {
            recipeToDelete = recipe
            showDeleteConfirmation = true
        } label: {
            Label("Delete Recipe", systemImage: "trash")
                .foregroundStyle(.red)
        }
    }
    
    private func handleStartCooking(recipe: Recipe) {
        // Check if different recipe is already cooking
        if viewModel.dependencies.cookModeCoordinator.isActive,
           let currentRecipe = viewModel.dependencies.cookModeCoordinator.currentRecipe,
           currentRecipe.id != recipe.id {
            // Show conflict alert
            selectedRecipe = recipe
            viewModel.dependencies.cookModeCoordinator.pendingRecipe = recipe
            showSessionConflictAlert = true
        } else {
            // Start cooking
            Task {
                await viewModel.dependencies.cookModeCoordinator.startCooking(recipe)
            }
        }
    }

    private func deleteRecipe(_ recipe: Recipe) {
        Task {
            do {
                try await viewModel.dependencies.recipeRepository.delete(id: recipe.id)
                await viewModel.loadData()
            } catch {
                AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Category Card View

struct CategoryCardView: View {
    let categoryName: String
    let recipeCount: Int
    
    var categoryIcon: String {
        // Map category names to appropriate SF Symbols
        let lowercased = categoryName.lowercased()
        
        if lowercased.contains("breakfast") { return "sun.horizon.fill" }
        if lowercased.contains("lunch") { return "sun.max.fill" }
        if lowercased.contains("dinner") { return "moon.stars.fill" }
        if lowercased.contains("dessert") { return "birthday.cake.fill" }
        if lowercased.contains("snack") { return "leaf.fill" }
        if lowercased.contains("appetizer") { return "flame.fill" }
        if lowercased.contains("soup") { return "drop.fill" }
        if lowercased.contains("salad") { return "carrot.fill" }
        if lowercased.contains("italian") { return "fork.knife" }
        if lowercased.contains("mexican") { return "flame.fill" }
        if lowercased.contains("asian") || lowercased.contains("chinese") || lowercased.contains("japanese") { return "takeoutbag.and.cup.and.straw.fill" }
        if lowercased.contains("american") { return "star.fill" }
        if lowercased.contains("indian") { return "burst.fill" }
        if lowercased.contains("vegetarian") || lowercased.contains("vegan") { return "leaf.fill" }
        if lowercased.contains("quick") || lowercased.contains("easy") || lowercased.contains("30") { return "clock.fill" }
        if lowercased.contains("healthy") { return "heart.fill" }
        if lowercased.contains("comfort") { return "house.fill" }
        
        return "fork.knife.circle.fill"
    }
    
    var categoryColor: Color {
        let lowercased = categoryName.lowercased()
        
        if lowercased.contains("breakfast") { return .orange }
        if lowercased.contains("lunch") { return .yellow }
        if lowercased.contains("dinner") { return .purple }
        if lowercased.contains("dessert") { return .pink }
        if lowercased.contains("snack") { return .green }
        if lowercased.contains("vegetarian") || lowercased.contains("vegan") { return .green }
        if lowercased.contains("quick") || lowercased.contains("easy") { return .blue }
        if lowercased.contains("healthy") { return .mint }
        
        return .cauldronOrange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                
                Image(systemName: categoryIcon)
                    .font(.system(size: 24))
                    .foregroundColor(categoryColor)
            }
            
            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(categoryName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cauldronSecondaryBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Recipe Card View (horizontal scroll cards)

struct RecipeCardView: View {
    let recipe: Recipe
    let dependencies: DependencyContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Image with badges
            ZStack(alignment: .topTrailing) {
                RecipeImageView(cardImageURL: recipe.imageURL, recipeImageService: dependencies.recipeImageService)

                // Favorite indicator (top-right)
                if recipe.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(8)
                }
            }
            .frame(width: 240, height: 160)
            
            // Title - single line for clean look
            Text(recipe.title)
                .font(.headline)
                .lineLimit(1)
                .frame(width: 240, height: 20, alignment: .leading)

            // Metadata row - fixed height for alignment
            HStack(spacing: 4) {
                // Time - always reserve space
                if let time = recipe.displayTime {
                    Label(time, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(" ")
                        .font(.caption)
                        .frame(width: 60)
                }

                Spacer()

                // Tag - always reserve space
                if !recipe.tags.isEmpty, let firstTag = recipe.tags.first {
                    TagView(firstTag)
                        .scaleEffect(0.9) // Scale down slightly for the card
                        .frame(maxWidth: 100, alignment: .trailing)
                } else {
                    Text(" ")
                        .font(.caption2)
                        .frame(width: 60)
                }
            }
            .frame(width: 240, height: 20)
        }
        .frame(width: 240)
    }

}

#Preview {
    CookTabView(dependencies: .preview(), preloadedData: nil)
}
