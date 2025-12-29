//
//  RecipeRelatedSection.swift
//  Cauldron
//
//  Displays related recipes for a recipe
//

import SwiftUI

struct RecipeRelatedSection: View {
    let relatedRecipes: [Recipe]
    let dependencies: DependencyContainer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Related Recipes", systemImage: "link")
                .font(.title2)
                .fontWeight(.bold)

            VStack(spacing: 0) {
                ForEach(relatedRecipes) { relatedRecipe in
                    NavigationLink(destination: RecipeDetailView(recipe: relatedRecipe, dependencies: dependencies)) {
                        RecipeRowView(recipe: relatedRecipe, dependencies: dependencies)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if relatedRecipe.id != relatedRecipes.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
        .padding()
        .cardStyle()
    }
}

#Preview {
    RecipeRelatedSection(
        relatedRecipes: [
            Recipe(title: "Related Recipe 1", ingredients: [], steps: []),
            Recipe(title: "Related Recipe 2", ingredients: [], steps: [])
        ],
        dependencies: .preview()
    )
    .padding()
}
