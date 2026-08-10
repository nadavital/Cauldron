import SwiftUI

struct VisualRecipeSearchRoute: Hashable {
    let recipeIDs: [UUID]
}

struct VisualRecipeSearchResultsView: View {
    typealias LibraryLoader = () async throws -> [Recipe]

    let route: VisualRecipeSearchRoute
    let dependencies: DependencyContainer
    private let loadLibrary: LibraryLoader

    @State private var recipes: [Recipe] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var retryID = UUID()

    init(
        route: VisualRecipeSearchRoute,
        dependencies: DependencyContainer,
        loadLibrary: @escaping LibraryLoader = {
            try await RecipeIntentProvider.shared.libraryRecipes()
        }
    ) {
        self.route = route
        self.dependencies = dependencies
        self.loadLibrary = loadLibrary
    }

    var body: some View {
        Group {
            if RuntimeEnvironment.forceSkeletonLoading || isLoading {
                ScrollView {
                    VisualRecipeResultRowSkeletonList()
                        .padding()
                }
            } else if loadFailed {
                ContentUnavailableView {
                    Label("Couldn't Load Matches", systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try Again") {
                        retryID = UUID()
                    }
                }
            } else if recipes.isEmpty {
                ContentUnavailableView(
                    "No Matching Recipes",
                    systemImage: "camera.metering.unknown",
                    description: Text("Try another image or add more recipes to your library.")
                )
            } else {
                List(recipes) { recipe in
                    NavigationLink(value: recipe) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.title)
                                .font(.headline)
                            if let totalMinutes = recipe.totalMinutes {
                                Text("\(totalMinutes) minutes")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .modifier(RecipeEntityContextModifier(recipeID: recipe.id, isResolvable: true))
                    }
                }
            }
        }
        .navigationTitle("Visual Matches")
        .task(id: retryID) {
            isLoading = true
            loadFailed = false
            defer { isLoading = false }
            do {
                let library = try await loadLibrary()
                let byID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
                recipes = route.recipeIDs.compactMap { byID[$0] }
            } catch {
                AppLogger.general.error("Unable to load visual recipe results: \(error.localizedDescription)")
                recipes = []
                loadFailed = true
            }
        }
    }
}
