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
                VStack {
                    Spacer()
                    Image(systemName: "fork.knife.circle") // Or another relevant icon
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                        .padding(.bottom)
                    Text("No Recipes Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Tap the '+' button to add your first recipe.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 300) // Ensure it takes some space
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(recipes) { recipe in
                        ZStack(alignment: .topTrailing) { // ZStack for delete button overlay
                            NavigationLink(destination: RecipeDetailView(recipe: recipe, 
                                                                       deleteAction: deleteAction,
                                                                       recipes: $recipes)) { // Pass $recipes
                                RecipeCardView(recipe: recipe)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isEditMode) // Disable navigation in edit mode

                            if isEditMode {
                                Button {
                                    withAnimation {
                                        deleteAction(recipe.id)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                        .padding(6) // Adjust padding for better tap area
                                        .background(Circle().fill(Color.white.opacity(0.8)))
                                }
                                .padding([.top, .trailing], 6) // Position the button
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
            for (index, recipe) in recipes.enumerated() {
                print("Recipe \(index): \(recipe.name)")
            }
        }
    }
}

struct RecipeCardView: View {
    var recipe: Recipe

    var body: some View {
        VStack(alignment: .leading) {
            // Display image or placeholder
            Group {
                if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill() // Changed to Fill for better card appearance
                        .frame(height: 120)
                        .clipped() // Clip to bounds
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .frame(height: 120)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                        )
                }
            }
            
            Text(recipe.name)
                .font(.headline)
                .lineLimit(2)
                .padding(.top, 8)
            
            Text("\(recipe.prepTime + recipe.cookTime) min | \(recipe.servings) servings")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
            
            Spacer() // Pushes content to the top of the card if varying heights
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 3)
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
               tags: ["meal_breakfast", "method_quick_easy"]),
        Recipe(name: "Spaghetti Bolognese with a Very Long Name to Test Wrapping", 
               ingredients: [Ingredient(name: "Spaghetti", quantity: 500, unit: .grams)], 
               instructions: ["Cook & Eat"], 
               prepTime: 15, cookTime: 30, servings: 6, 
               imageData: nil, 
               tags: ["cuisine_italian", "meal_dinner"])
    ]
    return NavigationView { // Add NavigationView for title and links to work in preview
        RecipeGridView(recipes: $sampleRecipes, isEditMode: true, deleteAction: { _ in print("Delete tapped in preview") })
            .navigationTitle("Recipes")
    }
} 
