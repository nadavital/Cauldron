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
            // Thumbnail image with reference badge overlay
            RecipeImageView(thumbnailImageURL: recipe.imageURL)
                .overlay(
                    Group {
                        if recipe.isReference {
                            // Reference badge in top-left corner
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color(red: 0.5, green: 0.0, blue: 0.0).opacity(0.9))
                                .clipShape(Circle())
                                .shadow(radius: 2)
                        }
                    },
                    alignment: .topLeading
                )
                .padding(recipe.isReference ? 4 : 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(recipe.title)
                        .font(.headline)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    // Favorite indicator
                    if recipe.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .fixedSize()
                    }
                }

                HStack(spacing: 8) {
                    if let time = recipe.displayTime {
                        Label(time, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }

                    Text(recipe.yields)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()

                    Spacer(minLength: 4)

                    if !recipe.tags.isEmpty {
                        // Show only first tag to prevent overflow
                        Text(recipe.tags.first!.name)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cauldronOrange.opacity(0.2))
                            .foregroundColor(.cauldronOrange)
                            .cornerRadius(4)
                            .frame(maxWidth: 100)
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
