//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 5/6/25.
//

import SwiftUI

struct ContentView: View {
    // Sample data - replace with actual data management later
    @State var recipes: [Recipe] = [
        Recipe(name: "Pancakes", 
               ingredients: [
                Ingredient(name: "Flour", quantity: 1.5, unit: .cups),
                Ingredient(name: "Milk", quantity: 1.25, unit: .cups),
                Ingredient(name: "Egg", quantity: 1, unit: .pieces),
                Ingredient(name: "Sugar", quantity: 2, unit: .tbsp),
                Ingredient(name: "Baking Powder", quantity: 2, unit: .tsp)
               ], 
               instructions: ["Mix ingredients", "Cook on griddle"], 
               prepTime: 10, cookTime: 15, servings: 4, 
               imageData: nil,
               tags: ["meal_breakfast", "attr_kid_friendly", "method_quick_easy"]),
        Recipe(name: "Spaghetti Bolognese", 
               ingredients: [
                Ingredient(name: "Spaghetti", quantity: 500, unit: .grams),
                Ingredient(name: "Ground Beef", quantity: 500, unit: .grams),
                Ingredient(name: "Tomato Sauce", quantity: 1, unit: .pieces) // Assuming 'pieces' for can
               ], 
               instructions: ["Cook spaghetti", "Brown beef", "Add sauce and simmer"], 
               prepTime: 15, cookTime: 30, servings: 6, 
               imageData: nil,
               tags: ["cuisine_italian", "meal_dinner"])
    ]

    @State private var showingAddRecipeView = false
    @State private var isRecipeGridInEditMode: Bool = false

    var body: some View {
        NavigationStack { // Changed from NavigationView to NavigationStack
            RecipeGridView(recipes: $recipes, 
                           isEditMode: isRecipeGridInEditMode, 
                           deleteAction: deleteRecipe)
            .navigationTitle("My Recipes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !recipes.isEmpty {
                        Button(isRecipeGridInEditMode ? "Done" : "Edit") {
                            isRecipeGridInEditMode.toggle()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { 
                        showingAddRecipeView = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddRecipeView, onDismiss: {
                // Force view refresh when sheet dismisses
                let _ = recipes
                print("Sheet dismissed, recipes count: \(recipes.count)")
            }) {
                AddRecipeView(recipes: $recipes)
            }
            .onChange(of: recipes) { 
                print("ContentView: recipes array changed, now contains \(recipes.count) recipes")
            }
            .onAppear {
                print("ContentView appeared with \(recipes.count) recipes")
            }
        }
    }

    func deleteRecipe(at offsets: IndexSet) {
        recipes.remove(atOffsets: offsets)
    }

    func deleteRecipe(id: UUID) {
        recipes.removeAll { $0.id == id }
        if recipes.isEmpty {
            isRecipeGridInEditMode = false
        }
    }
}

#Preview {
    ContentView()
}
