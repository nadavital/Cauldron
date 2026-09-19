import SwiftUI

struct ImportReviewWorkspace: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showsSource = false
    let recipe: Recipe
    let dependencies: DependencyContainer
    let sourceInfo: String
    let sourceText: String?
    let sourceImage: UIImage?

    private var hasSource: Bool {
        sourceImage != nil || sourceText?.trimmed.isEmpty == false ||
            ["http", "https"].contains(recipe.sourceURL?.scheme?.lowercased() ?? "")
    }

    var body: some View {
        GeometryReader { geometry in
            #if canImport(SwiftUI, _version: 8.0.85)
            if #available(iOS 27.1, macCatalyst 27.1, *),
               hasSource, sizeClass == .regular, !textSize.isAccessibilitySize {
                ArrangementView {
                    ImportReviewRecipePane(recipe: recipe, dependencies: dependencies, sourceInfo: sourceInfo)
                } secondary: {
                    ImportSourceReferenceView(text: sourceText, image: sourceImage, url: recipe.sourceURL)
                }
                .arrangementViewStyle(.split)
            } else {
                fallback(width: geometry.size.width)
            }
            #else
            fallback(width: geometry.size.width)
            #endif
        }
    }

    @ViewBuilder
    private func fallback(width: CGFloat) -> some View {
        if hasSource, RecipeReadingLayout.usesColumns(availableWidth: width, accessibilityText: textSize.isAccessibilitySize) {
            HStack(spacing: 0) {
                ImportReviewRecipePane(recipe: recipe, dependencies: dependencies, sourceInfo: sourceInfo)
                Divider()
                ImportSourceReferenceView(text: sourceText, image: sourceImage, url: recipe.sourceURL)
                    .frame(width: width * 0.42)
            }
        } else {
            VStack(spacing: 0) {
                if hasSource {
                    Picker("Review", selection: $showsSource) {
                        Text("Recipe").tag(false)
                        Text("Original").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }
                if showsSource && hasSource {
                    ImportSourceReferenceView(text: sourceText, image: sourceImage, url: recipe.sourceURL)
                } else {
                    ImportReviewRecipePane(recipe: recipe, dependencies: dependencies, sourceInfo: sourceInfo)
                }
            }
        }
    }
}

private struct ImportReviewRecipePane: View {
    let recipe: Recipe
    let dependencies: DependencyContainer
    let sourceInfo: String

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                RecipeReviewPresentation(
                    recipe: recipe, dependencies: dependencies,
                    sourceDescription: sourceInfo,
                    showsHeroImage: false,
                    stacksSections: geometry.size.width < 760,
                    usesCompactHeader: true
                )
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
