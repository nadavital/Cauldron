import SwiftUI

struct RecipeIngredientsView: View {
    var ingredients: [Ingredient]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if ingredients.isEmpty {
                Text("No ingredients yet.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
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
        }
        .accessibilityLabel("Recipe ingredients")
    }
}


extension Ingredient {
    var quantityString: String {
        // Handle common fraction representations for quantities less than and equal to 1
        let epsilon = 0.0001
        let denominators = [2, 4, 3, 8]
        for denom in denominators {
            let numeratorDouble = quantity * Double(denom)
            let rounded = numeratorDouble.rounded()
            if abs(rounded - numeratorDouble) < epsilon {
                let numerator = Int(rounded)
                let whole = numerator / denom
                let remainder = numerator % denom
                if whole > 0 && remainder > 0 {
                    return "\(whole) \(remainder)/\(denom)"
                } else if whole > 0 {
                    return "\(whole)"
                } else if remainder > 0 {
                    return "\(remainder)/\(denom)"
                }
            }
        }
        
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        
        return formatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
    }
    
    var unitString: String {
        // First check for custom unit name
        if let customName = customUnitName, !customName.isEmpty {
            return customName
        }
        // Otherwise use standard displayName
        return unit.displayName(for: quantity)
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
