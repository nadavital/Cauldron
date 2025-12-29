//
//  RecipeNutritionSection.swift
//  Cauldron
//
//  Displays nutrition information for a recipe
//

import SwiftUI

struct RecipeNutritionSection: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Nutrition", systemImage: "chart.bar.fill")
                .font(.title2)
                .fontWeight(.bold)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let calories = nutrition.calories {
                    NutritionItem(label: "Calories", value: "\(Int(calories))")
                }
                if let protein = nutrition.protein {
                    NutritionItem(label: "Protein", value: "\(Int(protein))g")
                }
                if let carbs = nutrition.carbohydrates {
                    NutritionItem(label: "Carbs", value: "\(Int(carbs))g")
                }
                if let fat = nutrition.fat {
                    NutritionItem(label: "Fat", value: "\(Int(fat))g")
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

private struct NutritionItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cauldronOrange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    RecipeNutritionSection(nutrition: Nutrition(
        calories: 350,
        protein: 12,
        fat: 14,
        carbohydrates: 45
    ))
    .padding()
}
