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
    
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var firestoreManager = FirestoreManager()

    @State private var showingAddRecipeView = false
    @State private var isRecipeGridInEditMode: Bool = false
    @State private var showingSignOutAlert = false
    @State private var showingProfileView = false

    var body: some View {
        NavigationStack { // Changed from NavigationView to NavigationStack
            RecipeGridView(recipes: $recipes, 
                           isEditMode: isRecipeGridInEditMode, 
                           deleteAction: deleteRecipe)
            .navigationTitle("My Recipes")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        if !recipes.isEmpty {
                            Button(isRecipeGridInEditMode ? "Done" : "Edit") {
                                isRecipeGridInEditMode.toggle()
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { 
                            showingAddRecipeView = true
                        }) {
                            Image(systemName: "plus")
                        }
                        
                        Menu {
                            Button(action: {
                                showingProfileView = true
                            }) {
                                Label("Profile", systemImage: "person.circle")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                showingSignOutAlert = true
                            }) {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
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
            .sheet(isPresented: $showingProfileView) {
                ProfileView()
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Sign Out", role: .destructive) {
                    // Clear local data before signing out
                    recipes.removeAll()
                    isRecipeGridInEditMode = false
                    authViewModel.signOut()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to sign out?")
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
