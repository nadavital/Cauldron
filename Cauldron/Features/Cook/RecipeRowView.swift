//
//  RecipeRowView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI

/// Reusable recipe row view for list displays
struct RecipeRowView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail image
            if let imageURL = recipe.imageURL,
               let image = loadImage(filename: imageURL.lastPathComponent) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // Placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color.cauldronOrange.opacity(0.3), Color.cauldronOrange.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .foregroundColor(.cauldronOrange.opacity(0.6))
                            .font(.body)
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    if let time = recipe.displayTime {
                        Label(time, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(recipe.yields)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !recipe.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(recipe.tags.prefix(2)) { tag in
                                Text(tag.name)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cauldronOrange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
        }
        .frame(minHeight: 68)
        .padding(.vertical, 4)
    }
    
    private func loadImage(filename: String) -> UIImage? {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageURL = documentsURL.appendingPathComponent("RecipeImages").appendingPathComponent(filename)
        
        guard let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }
        return UIImage(data: imageData)
    }
}

#Preview {
    NavigationStack {
        List {
            RecipeRowView(
                recipe: Recipe(
                    title: "Sample Recipe with a Long Title That Spans Multiple Lines",
                    ingredients: [
                        Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup)),
                        Ingredient(name: "Sugar", quantity: Quantity(value: 1, unit: .cup))
                    ],
                    steps: [
                        CookStep(index: 0, text: "Mix ingredients", timers: []),
                        CookStep(index: 1, text: "Bake for 30 minutes", timers: [.minutes(30)])
                    ],
                    yields: "4 servings",
                    totalMinutes: 45,
                    tags: [Tag(name: "Dessert"), Tag(name: "Quick")]
                )
            )
        }
    }
}
