import AppIntents
import Foundation

struct RecipeIntentEntity: AppEntity, Identifiable, Sendable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe")
    static var defaultQuery = RecipeIntentEntityQuery()

    let id: UUID
    let title: String
    let totalMinutes: Int?

    var displayRepresentation: DisplayRepresentation {
        var subtitle: LocalizedStringResource?
        if let totalMinutes {
            subtitle = "\(totalMinutes) minutes"
        }
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: title),
            subtitle: subtitle,
            image: .init(systemName: "fork.knife")
        )
    }

    nonisolated init(id: UUID, title: String, totalMinutes: Int?) {
        self.id = id
        self.title = title
        self.totalMinutes = totalMinutes
    }

    nonisolated init(recipe: Recipe) {
        self.init(id: recipe.id, title: recipe.title, totalMinutes: recipe.totalMinutes)
    }
}

struct RecipeIntentEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RecipeIntentEntity] {
        let recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(RecipeIntentEntity.init(recipe:)) }
    }

    func entities(matching string: String) async throws -> [RecipeIntentEntity] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        return recipes
            .filter { normalized.isEmpty || $0.title.localizedCaseInsensitiveContains(normalized) }
            .sorted { lhs, rhs in
                let lhsExact = lhs.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame
                let rhsExact = rhs.title.localizedCaseInsensitiveCompare(normalized) == .orderedSame
                if lhsExact != rhsExact { return lhsExact }
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(20)
            .map(RecipeIntentEntity.init(recipe:))
    }

    func suggestedEntities() async throws -> [RecipeIntentEntity] {
        try await RecipeIntentProvider.shared.libraryRecipes()
            .prefix(10)
            .map(RecipeIntentEntity.init(recipe:))
    }
}

@MainActor
final class RecipeIntentProvider {
    static let shared = RecipeIntentProvider()

    private init() {}

    func libraryRecipes() async throws -> [Recipe] {
        try await DependencyContainer.shared.recipeRepository.fetchLibraryRecipes(
            ownerId: CurrentUserSession.shared.userId
        )
    }

    func recipe(id: UUID) async throws -> Recipe? {
        guard let userID = CurrentUserSession.shared.userId else { return nil }
        return try await DependencyContainer.shared.recipeRepository
            .fetchLibraryRecipes(ownerId: userID)
            .first { $0.id == id }
    }

    func startCooking(recipeID: UUID) async throws -> CookModeStartOutcome {
        guard let recipe = try await recipe(id: recipeID) else { return .invalidRecipe }
        let coordinator = DependencyContainer.shared.cookModeCoordinator
        let reconciled = await coordinator.reconcileExternalState()
        if !reconciled, let persisted = CookSessionSharedStore.read() {
            return persisted.recipeID == recipeID ? .alreadyActive : .conflict
        }
        return await coordinator.startCooking(recipe)
    }

    func resumeCooking(expectedRecipeID: UUID) async -> Bool {
        let coordinator = DependencyContainer.shared.cookModeCoordinator
        await coordinator.reconcileExternalState()
        guard coordinator.currentRecipe?.id == expectedRecipeID else { return false }
        coordinator.expandToFullScreen()
        return true
    }

    func endCooking(expected: CookSessionSharedSnapshot) async -> Bool {
        let coordinator = DependencyContainer.shared.cookModeCoordinator
        await coordinator.reconcileExternalState()
        guard let current = CookSessionSharedStore.read(),
              current.recipeID == expected.recipeID,
              current.revision == expected.revision,
              coordinator.currentRecipe?.id == expected.recipeID,
              coordinator.isActive else { return false }
        coordinator.endSession()
        return true
    }
}
