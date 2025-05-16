import SwiftUI

struct RecipeIngredientRow: View {
    var ingredient: Ingredient
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Quantity and unit with better styling
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(ingredient.quantityString)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(ingredient.unitString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, alignment: .leading)
            
            // Ingredient name
            Text(ingredient.name)
                .font(.body)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// Preview
#Preview {
    VStack(spacing: 0) {
        RecipeIngredientRow(
            ingredient: Ingredient(name: "All-Purpose Flour", quantity: 1.5, unit: .cups)
        )
        Divider()
        RecipeIngredientRow(
            ingredient: Ingredient(name: "Granulated Sugar", quantity: 2, unit: .tbsp)
        )
        Divider()
        RecipeIngredientRow(
            ingredient: Ingredient(name: "Large Eggs", quantity: 2, unit: .pieces)
        )
    }
    .padding()
    .background(Color(.systemBackground))
    .cornerRadius(12)
    .padding()
}