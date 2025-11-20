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
    let dependencies: DependencyContainer
    var onTagTap: ((Tag) -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail image
            RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)

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

                    if !recipe.tags.isEmpty, onTagTap != nil {
                        // Show only first tag to prevent overflow - tappable if callback provided
                        TagView(recipe.tags.first!)
                            .frame(maxWidth: 120)
                            .lineLimit(1)
                            .onTapGesture {
                                onTagTap?(recipe.tags.first!)
                            }
                    } else if !recipe.tags.isEmpty {
                        // Show tag but not tappable
                        TagView(recipe.tags.first!)
                            .frame(maxWidth: 120)
                            .lineLimit(1)
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
    let dependencies = try! DependencyContainer.preview()
    return NavigationStack {
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
                ),
                dependencies: dependencies
            )
        }
    }
}
