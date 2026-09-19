//
//  RecipeReviewPresentation.swift
//  Cauldron
//
//  Shared read-only recipe presentation for import/review surfaces. It mirrors
//  the saved recipe detail hierarchy without exposing library-only actions.
//

import SwiftUI

struct RecipeReviewPresentation: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let recipe: Recipe
    let dependencies: DependencyContainer
    var sourceDescription: String?
    var attributionName: String?
    var showsHeroImage = true
    var heroHeight: CGFloat? = nil
    var stacksSections = false
    var usesCompactHeader = false

    private var hasHeroImage: Bool {
        showsHeroImage && RecipeDetailDisplayPolicy.hasHeroImage(recipe)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasHeroImage {
                HeroRecipeImageView(
                    recipe: recipe,
                    recipeImageService: dependencies.recipeImageService,
                    height: heroHeight
                )
            }

            GlassEffectContainer(spacing: 2) {
                if horizontalSizeClass == .regular && !stacksSections {
                    regularContent
                } else {
                    compactContent
                }
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? Theme.Spacing.lg : Theme.Spacing.md)
            .padding(.top, hasHeroImage ? 0 : Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: 1_080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            RecipeIngredientsSection(ingredients: recipe.ingredients)
            RecipeStepsSection(steps: recipe.steps, highlightedStepIndex: nil)
            optionalNotes
            optionalNutrition
        }
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header

            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    RecipeIngredientsSection(ingredients: recipe.ingredients)
                    optionalNotes
                }
                .frame(maxWidth: 430, alignment: .leading)

                RecipeStepsSection(steps: recipe.steps, highlightedStepIndex: nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            optionalNutrition
        }
    }

    @ViewBuilder
    private var header: some View {
        if usesCompactHeader {
            RecipeReviewCompactHeader(recipe: recipe, dependencies: dependencies)
        } else {
        RecipeReviewHeaderSection(
            recipe: recipe,
            sourceDescription: sourceDescription,
            attributionName: attributionName
        )
        }
    }

    @ViewBuilder
    private var optionalNotes: some View {
        if let notes = recipe.notes, !notes.isEmpty {
            RecipeNotesSection(notes: notes)
        }
    }

    @ViewBuilder
    private var optionalNutrition: some View {
        if let nutrition = recipe.nutrition, nutrition.hasData {
            RecipeNutritionSection(nutrition: nutrition)
        }
    }
}

private struct RecipeReviewHeaderSection: View {
    @Environment(\.openURL) private var openURL

    let recipe: Recipe
    let sourceDescription: String?
    let attributionName: String?

    var body: some View {
        AppCard(style: .glass) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(recipe.title.recipeDetailLineBreakFriendly())
                    .font(Theme.Typography.screenTitle)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.xs) {
                        if let time = recipe.displayTime {
                            metadataPill(systemImage: "clock", text: time)
                        }

                        metadataPill(systemImage: "person.2", text: recipe.yields)

                        if let attributionName {
                            metadataPill(systemImage: "person.circle", text: attributionName)
                        }
                    }
                    .padding(.trailing, 1)
                }
                .scrollIndicators(.hidden)

                if !recipe.tags.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(recipe.tags) { tag in
                                TagView(tag)
                            }
                        }
                        .padding(.trailing, 1)
                    }
                    .scrollIndicators(.hidden)
                    .frame(minHeight: 34)
                }

                if let sourceDescription, !sourceDescription.isEmpty {
                    Label(sourceDescription, systemImage: "info.circle")
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let sourceURL = recipe.sourceURL {
                    Button {
                        openURL(sourceURL)
                    } label: {
                        Label("View Original Recipe", systemImage: "arrow.up.right")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Theme.HitTarget.minimum)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cauldronOrange)
                    .accessibilityHint("Opens the original recipe in your browser")
                }
            }
        }
    }

    private func metadataPill(systemImage: String, text: String) -> some View {
        Label(text.recipeDetailLineBreakFriendly(), systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
    }
}

#Preview("Imported Recipe Review") {
    NavigationStack {
        ScrollView {
            RecipeReviewPresentation(
                recipe: Recipe(
                    title: "Brown Butter Chocolate Chip Cookies",
                    ingredients: [
                        Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
                        Ingredient(name: "brown sugar", quantity: Quantity(value: 1, unit: .cup)),
                    ],
                    steps: [
                        CookStep(index: 0, text: "Brown the butter and let it cool."),
                        CookStep(index: 1, text: "Mix and bake for 12 minutes.", timers: [.minutes(12)]),
                    ],
                    yields: "12 cookies",
                    totalMinutes: 35,
                    tags: [Tag(name: "Dessert")]
                ),
                dependencies: .preview(),
                sourceDescription: "Imported from example.com"
            )
        }
        .appPageChrome()
        .navigationTitle("Preview Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecipeReviewCompactHeader: View {
    let recipe: Recipe
    let dependencies: DependencyContainer

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecipeImageView(thumbnailForRecipe: recipe, recipeImageService: dependencies.recipeImageService)
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text([recipe.displayTime, recipe.yields].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !recipe.tags.isEmpty {
                    Text(recipe.tags.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
