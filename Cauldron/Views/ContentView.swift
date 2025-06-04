//
//  ContentView.swift
//  Cauldron
//
//  Created by Nadav Avital on 5/6/25.
//

import SwiftUI

struct ContentView: View {
    // User's recipe collection - starts empty, will be populated from Firestore
    @State var recipes: [Recipe] = []
    
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var firestoreManager = FirestoreManager()

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
                // Reload recipes from Firestore when sheet dismisses
                Task {
                    await loadRecipes()
                }
            }) {
                AddRecipeView(recipes: $recipes)
            }
            .onChange(of: recipes) { 
                print("ContentView: recipes array changed, now contains \(recipes.count) recipes")
            }
            .onAppear {
                print("ContentView appeared with \(recipes.count) recipes")
                Task {
                    await loadRecipes()
                }
            }
        }
    }

    func loadRecipes() async {
        do {
            let loadedRecipes = try await firestoreManager.loadRecipes()
            await MainActor.run {
                self.recipes = loadedRecipes
                print("Loaded \(recipes.count) recipes from Firestore")
            }
        } catch {
            print("Error loading recipes: \(error)")
        }
    }

    func deleteRecipe(at offsets: IndexSet) {
        for index in offsets {
            let recipe = recipes[index]
            
            // Delete from Firebase
            Task {
                do {
                    try await firestoreManager.deleteRecipe(id: recipe.id)
                    print("Successfully deleted recipe from Firestore")
                } catch {
                    print("Error deleting recipe from Firestore: \(error)")
                }
            }
        }
        
        // Remove from local array
        recipes.remove(atOffsets: offsets)
    }

    func deleteRecipe(id: UUID) {
        // Delete from Firebase
        Task {
            do {
                try await firestoreManager.deleteRecipe(id: id)
                print("Successfully deleted recipe from Firestore")
            } catch {
                print("Error deleting recipe from Firestore: \(error)")
            }
        }
        
        // Remove from local array
        recipes.removeAll { $0.id == id }
        if recipes.isEmpty {
            isRecipeGridInEditMode = false
        }
    }
}

#Preview {
    ContentView()
}
