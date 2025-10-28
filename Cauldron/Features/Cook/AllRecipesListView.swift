//
//  AllRecipesListView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import SwiftUI
import os

/// Full list view for all recipes with filtering options
struct AllRecipesListView: View {
    let recipes: [Recipe]
    let dependencies: DependencyContainer
    
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var sortOption: SortOption = .recent
    @State private var recipeToDelete: Recipe?
    @State private var showDeleteConfirmation = false
    @State private var localRecipes: [Recipe]
    @State private var showingImporter = false
    @State private var showingEditor = false
    @State private var showingAIGenerator = false
    @State private var selectedRecipe: Recipe?
    
    init(recipes: [Recipe], dependencies: DependencyContainer) {
        self.recipes = recipes
        self.dependencies = dependencies
        self._localRecipes = State(initialValue: recipes)
    }
    
    enum SortOption: String, CaseIterable {
        case recent = "Recently Added"
        case name = "Name (A-Z)"
        case time = "Cooking Time"
        
        var systemImage: String {
            switch self {
            case .recent: return "clock"
            case .name: return "textformat.abc"
            case .time: return "timer"
            }
        }
    }
    
    var allTags: [String] {
        var tags = Set<String>()
        for recipe in localRecipes {
            for tag in recipe.tags {
                tags.insert(tag.name)
            }
        }
        return Array(tags).sorted()
    }
    
    var filteredAndSortedRecipes: [Recipe] {
        var filtered = localRecipes
        
        // Apply search filter
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            filtered = filtered.filter { recipe in
                recipe.title.lowercased().contains(lowercased) ||
                recipe.tags.contains(where: { $0.name.lowercased().contains(lowercased) })
            }
        }
        
        // Apply tag filter
        if let selectedTag = selectedTag {
            filtered = filtered.filter { recipe in
                recipe.tags.contains(where: { $0.name == selectedTag })
            }
        }
        
        // Apply sort
        switch sortOption {
        case .recent:
            filtered = filtered.sorted { $0.createdAt > $1.createdAt }
        case .name:
            filtered = filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .time:
            filtered = filtered.sorted { ($0.totalMinutes ?? Int.max) < ($1.totalMinutes ?? Int.max) }
        }
        
        return filtered
    }
    
    var body: some View {
        List {
            // Active filters
            if selectedTag != nil {
                Section {
                    HStack {
                        Text("Tag: \(selectedTag!)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cauldronOrange.opacity(0.2))
                            .cornerRadius(6)
                        
                        Spacer()
                        
                        Button("Clear") {
                            selectedTag = nil
                        }
                        .font(.caption)
                    }
                }
            }
            
            ForEach(filteredAndSortedRecipes) { recipe in
                NavigationLink(destination: RecipeDetailView(recipe: recipe, dependencies: dependencies)) {
                    RecipeRowView(recipe: recipe)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        recipeToDelete = recipe
                        showDeleteConfirmation = true
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
        .navigationTitle("All Recipes")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search recipes")
        .onAppear {
            localRecipes = recipes
        }
        .onChange(of: recipes) { newRecipes in
            localRecipes = newRecipes
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirmation, presenting: recipeToDelete) { recipe in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecipe(recipe)
            }
        } message: { recipe in
            Text("Are you sure you want to delete \"\(recipe.title)\"? This cannot be undone.")
        }
        .sheet(isPresented: $showingImporter, onDismiss: {
            // Refresh recipes when importer is dismissed
            Task {
                do {
                    localRecipes = try await dependencies.recipeRepository.fetchAll()
                } catch {
                    AppLogger.general.error("Failed to refresh recipes: \(error.localizedDescription)")
                }
            }
        }) {
            ImporterView(dependencies: dependencies)
        }
        .sheet(isPresented: $showingEditor) {
            RecipeEditorView(dependencies: dependencies, recipe: selectedRecipe)
        }
        .sheet(isPresented: $showingAIGenerator) {
            AIRecipeGeneratorView(dependencies: dependencies)
        }
        .toolbar {
            // Filter/Sort menu (left position for consistency)
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Sort section
                    Menu {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortOption = option
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }

                    // Filter section
                    Menu {
                        Button {
                            selectedTag = nil
                        } label: {
                            HStack {
                                Text("All Tags")
                                if selectedTag == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        ForEach(allTags, id: \.self) { tag in
                            Button {
                                selectedTag = tag
                            } label: {
                                HStack {
                                    Text(tag)
                                    if selectedTag == tag {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Filter by Tag", systemImage: "tag")
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }

            // Add recipe menu (right position)
            ToolbarItem(placement: .navigationBarTrailing) {
                AddRecipeMenu(
                    dependencies: dependencies,
                    showingEditor: $showingEditor,
                    showingAIGenerator: $showingAIGenerator,
                    showingImporter: $showingImporter
                )
            }
        }
    }
    
    private func deleteRecipe(_ recipe: Recipe) {
        Task {
            do {
                try await dependencies.recipeRepository.delete(id: recipe.id)
                localRecipes.removeAll { $0.id == recipe.id }
            } catch {
                AppLogger.general.error("Failed to delete recipe: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Filter Sheet

struct FilterSheet: View {
    let allTags: [String]
    @Binding var selectedTag: String?
    @Binding var sortOption: AllRecipesListView.SortOption
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Sort By") {
                    ForEach(AllRecipesListView.SortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            HStack {
                                Label(option.rawValue, systemImage: option.systemImage)
                                    .foregroundColor(.primary)
                                Spacer()
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.cauldronOrange)
                                }
                            }
                        }
                    }
                }
                
                Section("Filter by Tag") {
                    Button {
                        selectedTag = nil
                    } label: {
                        HStack {
                            Text("All Tags")
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedTag == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.cauldronOrange)
                            }
                        }
                    }
                    
                    ForEach(allTags, id: \.self) { tag in
                        Button {
                            selectedTag = tag
                        } label: {
                            HStack {
                                Text(tag)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedTag == tag {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.cauldronOrange)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
