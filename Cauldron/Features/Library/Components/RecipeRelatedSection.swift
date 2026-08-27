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
    @Namespace private var recipeTransition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderLabel(title: "Related Recipes", systemImage: "link")

            VStack(spacing: 0) {
                ForEach(relatedRecipes) { relatedRecipe in
                    let transitionID = "related-recipe-\(relatedRecipe.id.uuidString)"
                    NavigationLink {
                        RecipeDetailView(recipe: relatedRecipe, dependencies: dependencies)
                            .navigationTransition(.zoom(sourceID: transitionID, in: recipeTransition))
                    } label: {
                        RecipeRowView(recipe: relatedRecipe, dependencies: dependencies)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .matchedTransitionSource(id: transitionID, in: recipeTransition)

                    if relatedRecipe.id != relatedRecipes.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
        .padding()
        .glassCard()
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
