import SwiftUI

struct RecipeIngredientsView: View {
    var ingredients: [Ingredient]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // No need for section title - handled by parent section view
            
            // Ingredients list with dividers
            ForEach(ingredients.indices, id: \.self) { index in
                VStack(spacing: 0) {
                    RecipeIngredientRow(ingredient: ingredients[index])
                    
                    if index < ingredients.count - 1 {
                        Divider()
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .accessibilityLabel("Recipe ingredients")
    }
}


extension Ingredient {
    var quantityString: String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
    }
    
    var unitString: String {
        switch unit {
        case .cups: return "cups"
        case .tbsp: return "tbsp"
        case .tsp: return "tsp"
        case .ounce: return "oz"
        case .pound: return "lb"
        case .grams: return "g"
        case .pieces: return "pc"
        case .pinch: return "pinch"
        case .ml: return "ml"
        case .liters: return "l"
        case .kg: return "kg"
        case .mg: return "mg"
        case .dash: return "dash"
        }
    }
}

#Preview {
    let ingredients = [
        Ingredient(name: "All-Purpose Flour", quantity: 1.5, unit: .cups),
        Ingredient(name: "Granulated Sugar", quantity: 2, unit: .tbsp),
        Ingredient(name: "Baking Powder", quantity: 2, unit: .tsp),
        Ingredient(name: "Large Eggs", quantity: 2, unit: .pieces),
        Ingredient(name: "Milk", quantity: 1, unit: .cups)
    ]
    
    return RecipeIngredientsView(ingredients: ingredients)
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .padding()
}
