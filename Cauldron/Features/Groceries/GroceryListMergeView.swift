//
//  GroceryListMergeView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI
import os

/// View for creating a grocery list from multiple recipes
struct GroceryListMergeView: View {
    let dependencies: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    
    @State private var allRecipes: [Recipe] = []
    @State private var selectedRecipeIds: Set<UUID> = []
    @State private var listTitle = ""
    @State private var isCreating = false
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
                Section {
                    TextField("List Name", text: $listTitle)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Grocery List Name")
                } footer: {
                    Text("Choose recipes to combine into one shopping list")
                }
                
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
            .navigationTitle("Create Shopping List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await createMergedList()
                        }
                    }
                    .disabled(listTitle.isEmpty || selectedRecipeIds.isEmpty || isCreating)
                }
            }
            .task {
                await loadRecipes()
            }
            .alert("List Created!", isPresented: $showSuccess) {
                Button("Done") {
                    dismiss()
                }
            } message: {
                Text("Your shopping list '\(listTitle)' has been created with merged ingredients.")
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
    
    private func createMergedList() async {
        isCreating = true
        defer { isCreating = false }
        
        do {
            // Generate grocery items from each recipe
            var allGroceryLists: [[GroceryItem]] = []
            
            for recipe in selectedRecipes {
                let items = try await dependencies.groceryService.generateGroceryList(from: recipe)
                allGroceryLists.append(items)
            }
            
            // Merge the lists
            let mergedItems = await dependencies.groceryService.mergeGroceryLists(allGroceryLists)
            
            // Create the grocery list
            let listId = try await dependencies.groceryRepository.createList(title: listTitle)
            
            // Add all merged items
            for item in mergedItems {
                try await dependencies.groceryRepository.addItem(
                    listId: listId,
                    name: item.name,
                    quantity: item.quantity
                )
            }
            
            showSuccess = true
            
        } catch {
            AppLogger.general.error("Failed to create merged grocery list: \(error.localizedDescription)")
        }
    }
}

#Preview {
    GroceryListMergeView(dependencies: .preview())
}
