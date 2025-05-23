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
        // Special case for zero
        if quantity == 0 {
            return "0"
        }
        
        // Handle common fraction representations
        let epsilon = 0.0001
        
        // Check for common fractions with higher precision
        if abs(quantity - 0.25) < epsilon {
            return "¼"
        } else if abs(quantity - 0.33) < epsilon || abs(quantity - 1.0/3.0) < epsilon {
            return "⅓"
        } else if abs(quantity - 0.5) < epsilon {
            return "½"
        } else if abs(quantity - 0.67) < epsilon || abs(quantity - 2.0/3.0) < epsilon {
            return "⅔"
        } else if abs(quantity - 0.75) < epsilon {
            return "¾"
        } else if abs(quantity - 0.125) < epsilon {
            return "⅛"
        } else if abs(quantity - 0.375) < epsilon {
            return "⅜"
        } else if abs(quantity - 0.625) < epsilon {
            return "⅝"
        } else if abs(quantity - 0.875) < epsilon {
            return "⅞"
        }
        
        // Handle mixed numbers (whole + fraction)
        let whole = floor(quantity)
        let fraction = quantity - whole
        
        if whole > 0 && fraction > 0 {
            // Handle common fractions in mixed numbers
            if abs(fraction - 0.25) < epsilon {
                return "\(Int(whole)) ¼"
            } else if abs(fraction - 0.33) < epsilon || abs(fraction - 1.0/3.0) < epsilon {
                return "\(Int(whole)) ⅓"
            } else if abs(fraction - 0.5) < epsilon {
                return "\(Int(whole)) ½"
            } else if abs(fraction - 0.67) < epsilon || abs(fraction - 2.0/3.0) < epsilon {
                return "\(Int(whole)) ⅔"
            } else if abs(fraction - 0.75) < epsilon {
                return "\(Int(whole)) ¾"
            } else if abs(fraction - 0.125) < epsilon {
                return "\(Int(whole)) ⅛"
            } else if abs(fraction - 0.375) < epsilon {
                return "\(Int(whole)) ⅜"
            } else if abs(fraction - 0.625) < epsilon {
                return "\(Int(whole)) ⅝"
            } else if abs(fraction - 0.875) < epsilon {
                return "\(Int(whole)) ⅞"
            }
            
            // Try standard fractions for non-common values
            let denominators = [2, 3, 4, 8]
            for denom in denominators {
                let numeratorDouble = fraction * Double(denom)
                let rounded = round(numeratorDouble)
                if abs(rounded - numeratorDouble) < epsilon {
                    let remainder = Int(rounded)
                    if remainder > 0 {
                        return "\(Int(whole)) \(remainder)/\(denom)"
                    }
                }
            }
            
            // Fallback to decimal for mixed numbers that don't fit common fractions
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: quantity)) ?? "\(quantity)"
        } else if whole > 0 {
            // Just a whole number
            return "\(Int(whole))"
        } else {
            // Just a fraction (less than 1)
            let denominators = [2, 3, 4, 8]
            for denom in denominators {
                let numeratorDouble = quantity * Double(denom)
                let rounded = round(numeratorDouble)
                if abs(rounded - numeratorDouble) < epsilon {
                    let numerator = Int(rounded)
                    if numerator > 0 {
                        return "\(numerator)/\(denom)"
                    }
                }
            }
        }
        
        // Fallback to decimal format with up to 2 decimal places
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
