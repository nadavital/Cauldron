//
//  RecipeIngredientsSection.swift
//  Cauldron
//
//  Displays the ingredients list for a recipe
//

import SwiftUI

struct RecipeIngredientsSection: View {
    let ingredients: [Ingredient]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ingredients", systemImage: "basket")
                .font(.title2)
                .fontWeight(.bold)

            ForEach(sortedSections, id: \.self) { section in
                VStack(alignment: .leading, spacing: 8) {
                    if section != "Main" {
                        Text(section)
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    ForEach(groupedIngredients[section] ?? []) { ingredient in
                        IngredientRow(ingredient: ingredient)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .cardStyle()
    }

    private var groupedIngredients: [String: [Ingredient]] {
        Dictionary(grouping: ingredients) { $0.section ?? "Main" }
    }

    private var sortedSections: [String] {
        groupedIngredients.keys.sorted { section1, section2 in
            if section1 == "Main" { return true }
            if section2 == "Main" { return false }

            let index1 = ingredients.firstIndex { $0.section == section1 } ?? 0
            let index2 = ingredients.firstIndex { $0.section == section2 } ?? 0
            return index1 < index2
        }
    }
}

private struct IngredientRow: View {
    let ingredient: Ingredient

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundColor(.cauldronOrange)
                .padding(.top, 6)
                .fixedSize()

            Text(ingredient.displayString)
                .font(.body)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

#Preview {
    RecipeIngredientsSection(ingredients: [
        Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup)),
        Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup)),
        Ingredient(name: "Eggs", quantity: Quantity(value: 3, unit: .piece))
    ])
    .padding()
}
