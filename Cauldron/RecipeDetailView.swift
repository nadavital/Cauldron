import SwiftUI

struct RecipeDetailView: View {
    var recipe: Recipe
    var deleteAction: ((UUID) -> Void)? // Make it optional if not always passed
    @Binding var recipes: [Recipe] // Add binding for recipes
    @Environment(\.dismiss) var dismiss // To dismiss the view after deletion

    // State for showing confirmation alert
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false // State to present AddRecipeView for editing

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(recipe.name)
                    .font(.system(.largeTitle, design: .serif))
                    .fontWeight(.bold)
                    .padding(.bottom, 8)

                // Display Image if available
                if let imageData = recipe.imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300) // Allow more height
                        .cornerRadius(12)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    // Optional: Placeholder if no image
                    Rectangle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 200)
                        .cornerRadius(12)
                        .overlay(Text("No Image").foregroundColor(.gray))
                        .padding(.bottom, 8)
                }

                // Details Section
                GroupBox(label: Label("Details", systemImage: "doc.text")) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Prep Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(recipe.prepTime) min")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Cook Time")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(recipe.cookTime) min")
                                .font(.headline)
                        }
                        Spacer()
                        VStack(alignment: .leading) {
                            Text("Servings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(recipe.servings)")
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 8) // Applied here
                }

                // Tags Section
                if !recipe.tags.isEmpty {
                    GroupBox(label: Label("Tags", systemImage: "tag.fill")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(recipe.tags), id: \.self) { tagID in
                                    if let tag = AllRecipeTags.shared.getTag(byId: tagID) {
                                        HStack(spacing: 4) {
                                            Image(systemName: tag.iconName)
                                                .font(.caption)
                                            Text(tag.name)
                                                .font(.caption)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.blue.opacity(0.7))
                                        .foregroundColor(.white)
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.vertical, 4) // Padding for items inside the HStack of the ScrollView
                        }
                        .padding(.vertical, 4) // Padding for the ScrollView itself to ensure content isn't cut off if GroupBox has its own padding
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Ingredients Section
                GroupBox(label: Label("Ingredients", systemImage: "list.bullet.clipboard")) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients) { ingredient in
                            HStack(alignment: .top) {
                                Text("•")
                                    .font(.headline)
                                VStack(alignment: .leading) {
                                    Text(ingredient.name)
                                        .fontWeight(.medium)
                                    Text("\(ingredient.quantity.formatted()) \(ingredient.unit.rawValue)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8) // Applied here
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Instructions Section
                GroupBox(label: Label("Instructions", systemImage: "list.number")) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .top) {
                                Text("\(index + 1).")
                                    .fontWeight(.bold)
                                    .padding(.trailing, 4)
                                Text(instruction)
                            }
                        }
                    }
                    .padding(.vertical, 8) // Applied here
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { // Edit button
                Button("Edit") {
                    showingEditSheet = true // Present the edit sheet
                }
            }
            if deleteAction != nil {
                ToolbarItem(placement: .destructiveAction) { // For delete button
                    Button {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .alert("Delete Recipe?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let deleteAction = deleteAction {
                    deleteAction(recipe.id)
                    dismiss() // Dismiss the detail view
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete \"\(recipe.name)\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingEditSheet) {
            AddRecipeView(recipes: $recipes, recipeToEdit: recipe)
        }
    }
}

#Preview {
    // Sample data for preview - needs a @State var for the binding
    struct PreviewWrapper: View {
        @State var sampleRecipes: [Recipe] = [
            Recipe(name: "Classic Pancakes Super Delicious and Fluffy", 
                    ingredients: [
                        Ingredient(name: "All-Purpose Flour", quantity: 1.5, unit: .cups),
                        Ingredient(name: "Granulated Sugar", quantity: 2, unit: .tbsp),
                        Ingredient(name: "Baking Powder", quantity: 2, unit: .tsp),
                        Ingredient(name: "Salt", quantity: 0.5, unit: .tsp),
                        Ingredient(name: "Milk", quantity: 1.25, unit: .cups),
                        Ingredient(name: "Large Egg", quantity: 1, unit: .pieces),
                        Ingredient(name: "Melted Butter", quantity: 3, unit: .tbsp)
                    ], 
                    instructions: ["Whisk together flour, sugar, baking powder, and salt in a large bowl.", "In a separate bowl, whisk together milk, egg, and melted butter.", "Pour the wet ingredients into the dry ingredients and mix until just combined (do not overmix; a few lumps are okay).", "Heat a lightly oiled griddle or frying pan over medium heat.", "Pour or scoop the batter onto the griddle, using approximately 1/4 cup for each pancake.", "Cook for 2-3 minutes per side, or until golden brown and cooked through.", "Serve warm with your favorite toppings."], 
                    prepTime: 10, cookTime: 15, servings: 4, 
                    imageData: nil, 
                    tags: ["meal_breakfast", "attr_kid_friendly", "method_quick_easy"])
        ]
        var recipe: Recipe { sampleRecipes[0] } // get the first recipe for detail view

        var body: some View {
            NavigationView { // Wrap in NavigationView for preview
                RecipeDetailView(recipe: recipe, 
                                 deleteAction: { id in print("Preview: Delete recipe with id \(id)") }, 
                                 recipes: $sampleRecipes)
            }
        }
    }
    return PreviewWrapper()
} 
