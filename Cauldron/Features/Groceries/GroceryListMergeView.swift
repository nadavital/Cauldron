//
//  GroceryListMergeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI
import os

/// View for adding recipes to the unified grocery list
struct GroceryListMergeView: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    @State private var allRecipes: [Recipe] = []
    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var isAdding = false
    @State private var showSuccess = false
    @State private var searchText = ""
    
    var filteredRecipes: [Recipe] {
        if searchText.isEmpty {
            return allRecipes
        }
        return allRecipes.filter { recipe in
            recipe.title.lowercased().contains(searchText.lowercased())
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Select Recipes") {
                    if allRecipes.isEmpty {
                        Text("No recipes found")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(filteredRecipes) { recipe in
                            Button {
                                toggleRecipeSelection(recipe.id)
                            } label: {
                                HStack {
                                    Image(systemName: selectedRecipeIds.contains(recipe.id) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedRecipeIds.contains(recipe.id) ? .cauldronOrange : .secondary)
                                    
                                    VStack(alignment: .leading) {
                                        Text(recipe.title)
                                            .foregroundColor(.primary)
                                        Text("\(recipe.ingredients.count) ingredients")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                if !selectedRecipeIds.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(selectedRecipeIds.count) recipe(s) selected")
                                .font(.headline)
                            
                            let totalIngredients = selectedRecipes.reduce(0) { $0 + $1.ingredients.count }
                            Text("~\(totalIngredients) ingredients (duplicates will be merged)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search recipes")
            .navigationTitle("Add from Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await addRecipesToList()
                        }
                    }
                    .disabled(selectedRecipeIds.isEmpty || isAdding)
                }
            }
            .task {
                await loadRecipes()
            }
            .alert("Recipes Added!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("\(selectedRecipeIds.count) recipe(s) have been added to your grocery list.")
            }
        }
    }
    
    private var selectedRecipes: [Recipe] {
        allRecipes.filter { selectedRecipeIds.contains($0.id) }
    }
    
    private func toggleRecipeSelection(_ id: UUID) {
        if selectedRecipeIds.contains(id) {
            selectedRecipeIds.remove(id)
        } else {
            selectedRecipeIds.insert(id)
        }
    }
    
    private func loadRecipes() async {
        do {
            allRecipes = try await dependencies.recipeRepository.fetchAll()
        } catch {
            AppLogger.general.error("Failed to load recipes: \(error.localizedDescription)")
        }
    }
    
    private func addRecipesToList() async {
        isAdding = true
        defer { isAdding = false }

        do {
            // Add each recipe's ingredients to the unified list
            for recipe in selectedRecipes {
                let items = try await dependencies.groceryService.generateGroceryList(from: recipe)

                // Convert to the format needed for addItemsFromRecipe
                let itemTuples: [(name: String, quantity: Quantity?)] = items.map { ($0.name, $0.quantity) }

                try await dependencies.groceryRepository.addItemsFromRecipe(
                    recipeID: recipe.id.uuidString,
                    recipeName: recipe.title,
                    items: itemTuples
                )
            }

            showSuccess = true

        } catch {
            AppLogger.general.error("Failed to add recipes to grocery list: \(error.localizedDescription)")
        }
    }
}

#Preview {
    GroceryListMergeView(dependencies: .preview())
}
