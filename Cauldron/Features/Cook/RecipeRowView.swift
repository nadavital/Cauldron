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
            RecipeImageView(thumbnailImageURL: recipe.imageURL)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    // Indicators
                    HStack(spacing: 4) {
                        // Reference indicator
                        if recipe.isReference {
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.5, green: 0.0, blue: 0.0))
                        }

                        // Favorite indicator
                        if recipe.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                    }
                    .fixedSize()
                }

                HStack(spacing: 8) {
                    if let time = recipe.displayTime {
                        Label(time, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Text(recipe.yields)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if !recipe.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(recipe.tags.prefix(2)) { tag in
                                Text(tag.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cauldronOrange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 68)
        .padding(.vertical, 4)
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
