import AppIntents
import CoreSpotlight
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct RecipeIntentEntity: IndexedEntity, Identifiable, Sendable, Transferable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Recipe")
    static var defaultQuery = RecipeIntentEntityQuery()

    let id: UUID

    @Property(title: "Title", indexingKey: \.title)
    var title: String

    @Property(title: "Ingredients", indexingKey: \.keywords)
    var ingredientNames: [String]

    @Property(title: "Instructions", indexingKey: \.textContent)
    var instructions: String

    @Property(title: "Total Time")
    var totalMinutes: Int?

    @Property(title: "Tags")
    var tagNames: [String]

    @Property(title: "Favorite")
    var isFavorite: Bool

    @Property(title: "Yield")
    var recipeYield: String

    @Property(title: "Updated")
    var updatedAt: Date

    @Property(title: "Created")
    var createdAt: Date

    @Property(title: "Creator")
    var creatorName: String?

    @Property(title: "Notes")
    var notes: String?

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

    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription = searchableDescription
        attributes.keywords = Array(Set(ingredientNames + tagNames)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
        attributes.metadataModificationDate = updatedAt
        attributes.contentCreationDate = createdAt
        attributes.userCreated = true
        attributes.userOwned = true
        if let totalMinutes {
            attributes.duration = NSNumber(value: totalMinutes * 60)
        }
        return attributes
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(entity.siriContext.utf8)
        }
    }

    nonisolated init(
        id: UUID,
        title: String,
        ingredientNames: [String] = [],
        instructions: String = "",
        totalMinutes: Int?,
        tagNames: [String] = [],
        isFavorite: Bool = false,
        recipeYield: String = "",
        updatedAt: Date = .distantPast,
        createdAt: Date = .distantPast,
        creatorName: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.title = title
        self.ingredientNames = ingredientNames
        self.instructions = instructions
        self.totalMinutes = totalMinutes
        self.tagNames = tagNames
        self.isFavorite = isFavorite
        self.recipeYield = recipeYield
        self.updatedAt = updatedAt
        self.createdAt = createdAt
        self.creatorName = creatorName
        self.notes = notes
    }

    nonisolated init(recipe: Recipe) {
        self.init(
            id: recipe.id,
            title: recipe.title,
            ingredientNames: recipe.ingredients.map(\.name),
            instructions: recipe.steps
                .sorted { $0.index < $1.index }
                .map(\.text)
                .joined(separator: "\n"),
            totalMinutes: recipe.totalMinutes,
            tagNames: recipe.tags.map(\.name),
            isFavorite: recipe.isFavorite,
            recipeYield: recipe.yields,
            updatedAt: recipe.updatedAt,
            createdAt: recipe.createdAt,
            creatorName: recipe.originalCreatorName,
            notes: recipe.notes
        )
    }

    nonisolated var searchableDescription: String {
        var parts = [recipeYield]
        if !ingredientNames.isEmpty {
            parts.append("Ingredients: \(ingredientNames.joined(separator: ", "))")
        }
        if !tagNames.isEmpty {
            parts.append("Tags: \(tagNames.joined(separator: ", "))")
        }
        if let creatorName, !creatorName.isEmpty {
            parts.append("From \(creatorName)")
        }
        if let notes, !notes.isEmpty {
            parts.append(notes)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    nonisolated var siriContext: String {
        var sections = ["Recipe: \(title)"]
        if let totalMinutes {
            sections.append("Total time: \(totalMinutes) minutes")
        }
        if !recipeYield.isEmpty {
            sections.append("Yield: \(recipeYield)")
        }
        if !ingredientNames.isEmpty {
            sections.append("Ingredients:\n- \(ingredientNames.joined(separator: "\n- "))")
        }
        if !instructions.isEmpty {
            sections.append("Instructions:\n\(instructions)")
        }
        if let notes, !notes.isEmpty {
            sections.append("Notes:\n\(notes)")
        }
        return sections.joined(separator: "\n\n").prefix(12_000).description
    }
}

enum RecipeIntentComparator: Sendable, Equatable {
    case titleContains(String)
    case ingredientContains(String)
    case tagContains(String)
    case maximumMinutes(Int)
    case favorite(Bool)
    case updatedAfter(Date)
    case createdAfter(Date)
}

struct RecipeIntentEntityQuery: EntityStringQuery, EntityPropertyQuery, EnumerableEntityQuery {
    static var findIntentDescription: IntentDescription? {
        IntentDescription("Find recipes in your Cauldron library by title, ingredient, tag, time, or favorite status.")
    }

    static var properties = QueryProperties {
        Property(\RecipeIntentEntity.$title) {
            ContainsComparator { .titleContains($0) }
        }
        Property(\RecipeIntentEntity.$ingredientNames) {
            ContainsComparator { .ingredientContains($0) }
        }
        Property(\RecipeIntentEntity.$tagNames) {
            ContainsComparator { .tagContains($0) }
        }
        Property(\RecipeIntentEntity.$totalMinutes) {
            LessThanOrEqualToComparator { .maximumMinutes($0) }
        }
        Property(\RecipeIntentEntity.$isFavorite) {
            EqualToComparator { .favorite($0) }
        }
        Property(\RecipeIntentEntity.$updatedAt) {
            GreaterThanOrEqualToComparator { .updatedAfter($0) }
        }
        Property(\RecipeIntentEntity.$createdAt) {
            GreaterThanOrEqualToComparator { .createdAfter($0) }
        }
    }

    static var sortingOptions = SortingOptions {
        SortableBy(\RecipeIntentEntity.$title)
        SortableBy(\RecipeIntentEntity.$totalMinutes)
        SortableBy(\RecipeIntentEntity.$updatedAt)
        SortableBy(\RecipeIntentEntity.$createdAt)
    }

    func entities(for identifiers: [UUID]) async throws -> [RecipeIntentEntity] {
        let recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        let byID = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(RecipeIntentEntity.init(recipe:)) }
    }

    func entities(matching string: String) async throws -> [RecipeIntentEntity] {
        let recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        return RecipeIntentSearch.stringMatches(string, in: recipes, limit: 20)
            .map(RecipeIntentEntity.init(recipe:))
    }

    func entities(
        matching comparators: [RecipeIntentComparator],
        mode: ComparatorMode,
        sortedBy: [Sort<RecipeIntentEntity>],
        limit: Int?
    ) async throws -> [RecipeIntentEntity] {
        let recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        let entities = recipes.map(RecipeIntentEntity.init(recipe:))
        return RecipeIntentSearch.filter(
            entities,
            comparators: comparators,
            requireAll: mode == .and,
            sorts: sortedBy,
            limit: limit
        )
    }

    func allEntities() async throws -> [RecipeIntentEntity] {
        try await RecipeIntentProvider.shared.libraryRecipes()
            .map(RecipeIntentEntity.init(recipe:))
    }

    func suggestedEntities() async throws -> [RecipeIntentEntity] {
        try await RecipeIntentProvider.shared.libraryRecipes()
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(10)
            .map(RecipeIntentEntity.init(recipe:))
    }
}

enum RecipeIntentSearch {
    nonisolated static func stringMatches(
        _ string: String,
        in recipes: [Recipe],
        limit: Int
    ) -> [Recipe] {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return recipes
            .filter { recipe in
                normalized.isEmpty
                    || recipe.title.localizedStandardContains(normalized)
                    || recipe.ingredients.contains { $0.name.localizedStandardContains(normalized) }
                    || recipe.tags.contains { $0.name.localizedStandardContains(normalized) }
            }
            .sorted { lhs, rhs in
                let lhsRank = matchRank(for: lhs, query: normalized)
                let rhsRank = matchRank(for: rhs, query: normalized)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    nonisolated static func filter(
        _ entities: [RecipeIntentEntity],
        comparators: [RecipeIntentComparator],
        requireAll: Bool,
        sorts: [EntityQuerySort<RecipeIntentEntity>],
        limit: Int?
    ) -> [RecipeIntentEntity] {
        let filtered = entities.filter { entity in
            guard !comparators.isEmpty else { return true }
            let matches = comparators.map { matches(entity, comparator: $0) }
            return requireAll ? matches.allSatisfy { $0 } : matches.contains(true)
        }

        let sorted = filtered.sorted { lhs, rhs in
            for sort in sorts {
                if sort.by == \RecipeIntentEntity.$totalMinutes,
                   lhs.totalMinutes == nil || rhs.totalMinutes == nil {
                    if lhs.totalMinutes == nil, rhs.totalMinutes != nil { return false }
                    if lhs.totalMinutes != nil, rhs.totalMinutes == nil { return true }
                }
                let comparison = compare(lhs, rhs, by: sort.by)
                guard comparison != .orderedSame else { continue }
                return sort.order == .ascending
                    ? comparison == .orderedAscending
                    : comparison == .orderedDescending
            }
            let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(sorted.prefix(max(limit ?? sorted.count, 0)))
    }

    nonisolated static func sortedByTotalMinutes(
        _ entities: [RecipeIntentEntity],
        ascending: Bool
    ) -> [RecipeIntentEntity] {
        entities.sorted { lhs, rhs in
            switch (lhs.totalMinutes, rhs.totalMinutes) {
            case (.none, .none):
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case (.none, .some):
                return false
            case (.some, .none):
                return true
            case (.some(let lhsMinutes), .some(let rhsMinutes)):
                if lhsMinutes == rhsMinutes {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return ascending ? lhsMinutes < rhsMinutes : lhsMinutes > rhsMinutes
            }
        }
    }

    nonisolated private static func matchRank(for recipe: Recipe, query: String) -> Int {
        guard !query.isEmpty else { return 3 }
        if recipe.title.localizedCaseInsensitiveCompare(query) == .orderedSame { return 0 }
        if recipe.title.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive, .anchored]
        ) != nil { return 1 }
        if recipe.title.localizedStandardContains(query) { return 2 }
        return 3
    }

    nonisolated private static func matches(
        _ entity: RecipeIntentEntity,
        comparator: RecipeIntentComparator
    ) -> Bool {
        switch comparator {
        case .titleContains(let value):
            entity.title.localizedStandardContains(value)
        case .ingredientContains(let value):
            entity.ingredientNames.contains { $0.localizedStandardContains(value) }
        case .tagContains(let value):
            entity.tagNames.contains { $0.localizedStandardContains(value) }
        case .maximumMinutes(let value):
            entity.totalMinutes.map { $0 <= value } ?? false
        case .favorite(let value):
            entity.isFavorite == value
        case .updatedAfter(let value):
            entity.updatedAt >= value
        case .createdAfter(let value):
            entity.createdAt >= value
        }
    }

    nonisolated private static func compare(
        _ lhs: RecipeIntentEntity,
        _ rhs: RecipeIntentEntity,
        by keyPath: PartialKeyPath<RecipeIntentEntity>
    ) -> ComparisonResult {
        switch keyPath {
        case \RecipeIntentEntity.$title:
            lhs.title.localizedStandardCompare(rhs.title)
        case \RecipeIntentEntity.$totalMinutes:
            compareOptionals(lhs.totalMinutes, rhs.totalMinutes)
        case \RecipeIntentEntity.$updatedAt:
            lhs.updatedAt.compare(rhs.updatedAt)
        case \RecipeIntentEntity.$createdAt:
            lhs.createdAt.compare(rhs.createdAt)
        default:
            .orderedSame
        }
    }

    nonisolated private static func compareOptionals<T: Comparable>(
        _ lhs: T?,
        _ rhs: T?
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.none, .none): .orderedSame
        case (.none, .some): .orderedDescending
        case (.some, .none): .orderedAscending
        case (.some(let lhs), .some(let rhs)):
            lhs == rhs ? .orderedSame : (lhs < rhs ? .orderedAscending : .orderedDescending)
        }
    }
}

@MainActor
final class RecipeIntentProvider {
    static let shared = RecipeIntentProvider()

    private init() {}

    func libraryRecipes() async throws -> [Recipe] {
        await CurrentUserSession.shared.ensureInitialized(dependencies: DependencyContainer.shared)
        guard CurrentUserSession.shared.isAccountIdentityVerified,
              let userID = CurrentUserSession.shared.userId else {
            return []
        }
        let recipes = try await DependencyContainer.shared.recipeRepository.fetchLibraryRecipes(ownerId: userID)
        guard CurrentUserSession.shared.isAccountIdentityVerified,
              CurrentUserSession.shared.userId == userID else {
            return []
        }
        return recipes.filter { !$0.isPreview && $0.ownerId == userID }
    }

    func recipe(id: UUID) async throws -> Recipe? {
        try await libraryRecipes().first { $0.id == id }
    }

    func activeCookingSnapshot() async -> CookSessionSharedSnapshot? {
        await CurrentUserSession.shared.ensureInitialized(dependencies: DependencyContainer.shared)
        guard CurrentUserSession.shared.isAccountIdentityVerified,
              let userID = CurrentUserSession.shared.userId else {
            return nil
        }

        let snapshot = CookSessionSharedStore.read()
        guard let snapshot,
              CurrentUserSession.shared.userId == userID,
              snapshot.belongs(to: userID) else {
            if snapshot != nil {
                DependencyContainer.shared.cookModeCoordinator.endSession()
            }
            return nil
        }
        return snapshot
    }

    func startCooking(recipeID: UUID) async throws -> CookModeStartOutcome {
        guard let recipe = try await recipe(id: recipeID) else { return .invalidRecipe }
        guard let expectedUserID = CurrentUserSession.shared.userId,
              recipe.ownerId == expectedUserID else {
            return .invalidRecipe
        }
        let coordinator = DependencyContainer.shared.cookModeCoordinator
        let reconciled = await coordinator.reconcileExternalState()
        guard CurrentUserSession.shared.userId == expectedUserID,
              recipe.ownerId == expectedUserID else {
            return .invalidRecipe
        }
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
              current.ownerID == expected.ownerID,
              current.revision == expected.revision,
              current.sessionStartTime == expected.sessionStartTime,
              CurrentUserSession.shared.userId == expected.ownerID,
              coordinator.currentRecipe?.id == expected.recipeID,
              coordinator.isActive else { return false }
        coordinator.endSession()
        return true
    }
}
