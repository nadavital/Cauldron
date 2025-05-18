import SwiftUI

struct RecipeDetailView: View {
    var recipe: Recipe
    var deleteAction: ((UUID) -> Void)?
    @Binding var recipes: [Recipe]
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var dominantColor: Color = Color(.systemGroupedBackground)
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Enhanced background with the dominant color
                Group {
                    if colorScheme == .dark {
                        darkModeBackground
                    } else {
                        lightModeBackground
                    }
                }
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Header with recipe image
                        RecipeHeaderView(
                            name: recipe.name,
                            imageData: recipe.imageData,
                            height: 400,
                            dominantColor: $dominantColor
                        )
                        .cornerRadius(16)
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        // Content sections
                        VStack(spacing: 20) {
                            // Timing & Servings
                            SectionContainer {
                                VStack(alignment: .leading) {
                                    SectionHeaderView(title: "Overview", iconName: "timer")
                                    
                                    RecipeTimingView(
                                        prepTime: recipe.prepTime,
                                        cookTime: recipe.cookTime,
                                        servings: recipe.servings
                                    )
                                }
                            }
                            
                            // Tags Section (if tags exist)
                            if !recipe.tags.isEmpty {
                                SectionContainer {
                                    VStack(alignment: .leading) {
                                        SectionHeaderView(title: "Tags", iconName: "tag.fill")
                                        
                                        RecipeTagsView(tagIDs: recipe.tags)
                                    }
                                }
                            }
                            
                            // Ingredients Section
                            SectionContainer {
                                VStack(alignment: .leading) {
                                    SectionHeaderView(title: "Ingredients", iconName: "list.bullet.clipboard")
                                    
                                    ForEach(recipe.ingredients) { ingredient in
                                        RecipeIngredientRow(ingredient: ingredient)
                                        
                                        if ingredient != recipe.ingredients.last {
                                            Divider()
                                                .padding(.vertical, 4)
                                        }
                                    }
                                }
                            }
                            
                            // Instructions Section
                            SectionContainer {
                                VStack(alignment: .leading) {
                                    SectionHeaderView(title: "Instructions", iconName: "list.number")
                                    
                                    ForEach(Array(recipe.instructions.enumerated()), id: \.offset) { index, instruction in
                                        RecipeInstructionRow(index: index, instruction: instruction)
                                        
                                        if index < recipe.instructions.count - 1 {
                                            Divider()
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                            }
                            
                            Spacer(minLength: 60)
                        }
                        .padding(.horizontal)
                        .padding(.top, 20)
                        .padding(.bottom, 50)
                    }
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(false)
        // Simplify toolbar implementation to avoid ambiguity
        .navigationBarItems(
            trailing: HStack(spacing: 16) {
                Button(action: { showingEditSheet = true }) {
                    Image(systemName: "pencil")
                }
                
                if deleteAction != nil {
                    Button(action: { showingDeleteAlert = true }) {
                        Image(systemName: "trash")

                    }
                }
            }
        )
        .alert("Delete Recipe?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let deleteAction = deleteAction {
                    deleteAction(recipe.id)
                    dismiss()
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
    
    // Enhanced background for light mode with gradient
    private var lightModeBackground: some View {
        ZStack {
            // Base solid color
            dominantColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: dominantColor)
            
            // New gradient overlay for light mode
            LinearGradient(
                colors: [
                    dominantColor.opacity(0.8),
                    dominantColor.opacity(0.5),
                    Color.white.opacity(0.6)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
    
    // Enhanced background for dark mode with more pronounced gradient
    private var darkModeBackground: some View {
        ZStack {
            // Base solid color with adjusted brightness
            Color.black
                .ignoresSafeArea()
            
            // Enhanced gradient with more color variation and opacity
            LinearGradient(
                colors: [
                    dominantColor.opacity(0.7),
                    dominantColor.opacity(0.4),
                    Color.black.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }
}

// Helper preference key for scroll tracking
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Section components with thickMaterial backgrounds
struct SectionContainer<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    var content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thickMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
            )
    }
}

struct SectionHeaderView: View {
    var title: String
    var iconName: String
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .foregroundColor(.accentColor)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.bottom, 12)
    }
}

#Preview {
    // Sample data for preview
    struct PreviewWrapper: View {
        @State var sampleRecipes: [Recipe] = [
            Recipe(name: "Classic Pancakes", 
                  ingredients: [
                      Ingredient(name: "All-Purpose Flour", quantity: 1.5, unit: .cups),
                      Ingredient(name: "Granulated Sugar", quantity: 2, unit: .tbsp),
                      Ingredient(name: "Baking Powder", quantity: 2, unit: .tsp),
                      Ingredient(name: "Salt", quantity: 0.5, unit: .tsp),
                      Ingredient(name: "Milk", quantity: 1.25, unit: .cups),
                      Ingredient(name: "Large Egg", quantity: 1, unit: .pieces),
                      Ingredient(name: "Melted Butter", quantity: 3, unit: .tbsp)
                  ], 
                  instructions: ["Whisk together flour, sugar, baking powder, and salt in a large bowl.", 
                                "In a separate bowl, whisk together milk, egg, and melted butter.", 
                                "Pour the wet ingredients into the dry ingredients and mix until just combined (do not overmix; a few lumps are okay).", 
                                "Heat a lightly oiled griddle or frying pan over medium heat.", 
                                "Pour or scoop the batter onto the griddle, using approximately 1/4 cup for each pancake.", 
                                "Cook for 2-3 minutes per side, or until golden brown and cooked through.", 
                                "Serve warm with your favorite toppings."], 
                  prepTime: 10, 
                  cookTime: 15, 
                  servings: 4, 
                  imageData: SampleImageLoader.breakfastImage, 
                  tags: ["meal_breakfast", "attr_kid_friendly", "method_quick_easy"])
        ]
        
        var recipe: Recipe { sampleRecipes[0] }

        var body: some View {
            NavigationView {
                RecipeDetailView(recipe: recipe, 
                                deleteAction: { id in print("Preview: Delete recipe with id \(id)") }, 
                                recipes: $sampleRecipes)
            }
        }
    }
    return PreviewWrapper()
}
