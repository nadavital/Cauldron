import SwiftUI

struct RecipeGridView: View {
    @Binding var recipes: [Recipe]
    var isEditMode: Bool
    var deleteAction: (UUID) -> Void

    // Define the grid layout
    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if recipes.isEmpty {
                EmptyStateView()
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(recipes) { recipe in
                        ZStack(alignment: .topTrailing) { // ZStack for delete button overlay
                            NavigationLink(destination: RecipeDetailView(recipe: recipe, 
                                                                       deleteAction: deleteAction,
                                                                       recipes: $recipes)) { 
                                RecipeCardView(recipe: recipe)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isEditMode) // Disable navigation in edit mode

                            if isEditMode {
                                DeleteButton(recipe: recipe, deleteAction: deleteAction)
                            }
                        }
                    }
                }
                .padding()
                // Use recipes.count as an ID to refresh when the count changes
                .id("recipes-grid-\(recipes.count)")
            }
        }
        .onAppear {
            print("RecipeGridView appeared with \(recipes.count) recipes")
        }
    }
}

#Preview {
    // Sample data for preview
    @Previewable @State var sampleRecipes: [Recipe] = [
        Recipe(name: "Pancakes", 
               ingredients: [Ingredient(name: "Flour", quantity: 1.5, unit: .cups)], 
               instructions: ["Mix & Cook"], 
               prepTime: 10, cookTime: 15, servings: 4, 
               imageData: nil, 
               tags: ["meal_breakfast", "method_quick_easy"],
               description: "Fluffy pancakes perfect for breakfast."),
        Recipe(name: "Spaghetti Bolognese", 
               ingredients: [Ingredient(name: "Spaghetti", quantity: 500, unit: .grams)], 
               instructions: ["Cook & Eat"], 
               prepTime: 15, cookTime: 30, servings: 6, 
               imageData: nil, 
               tags: ["cuisine_italian", "meal_dinner"],
               description: "Classic Italian pasta with rich meat sauce.")
    ]
    return NavigationView {
        RecipeGridView(recipes: $sampleRecipes, isEditMode: true, deleteAction: { _ in print("Delete tapped in preview") })
            .navigationTitle("Recipes")
    }
} 