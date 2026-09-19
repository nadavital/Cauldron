//
//  RecipeRowView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import SwiftUI

/// Reusable recipe row view for list displays
struct RecipeRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        timeAndYield
                        firstTag
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            timeAndYield
                            firstTag
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 6) {
                            timeAndYield
                            firstTag
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 68)
        .padding(.vertical, 4)
    }

    private var timeAndYield: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                timeLabel
                Text(recipe.yields)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 4) {
                timeLabel
                Text(recipe.yields)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var timeLabel: some View {
        if let time = recipe.displayTime {
            Label(time, systemImage: "clock")
        }
    }

    @ViewBuilder
    private var firstTag: some View {
        if let tag = recipe.tags.first {
            TagView(tag)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .onTapGesture { onTagTap?(tag) }
        }
    }
    
}

#Preview {
    let dependencies = DependencyContainer.preview()
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
