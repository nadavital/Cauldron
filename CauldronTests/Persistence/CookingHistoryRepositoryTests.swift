import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class CookingHistoryRepositoryTests: XCTestCase {
    func testRecentlyCookedFetchAppliesLimitInStore() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for index in 0..<50 {
            context.insert(CookingHistoryModel(
                recipeId: UUID(),
                recipeTitle: "Recipe \(index)",
                cookedAt: Date(timeIntervalSinceReferenceDate: Double(index))
            ))
        }
        try context.save()

        let repository = CookingHistoryRepository(modelContainer: container)
        let results = try await repository.fetchRecentlyCookedRecipes(limit: 7)

        XCTAssertEqual(results.count, 7)
        XCTAssertEqual(results.map(\.recipeTitle), (43..<50).reversed().map { "Recipe \($0)" })
    }

    func testUniqueRecentlyCookedPagesPastDuplicateHistory() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repeatedRecipeID = UUID()
        let olderRecipeIDs = (0..<4).map { _ in UUID() }

        for index in 0..<30 {
            context.insert(CookingHistoryModel(
                recipeId: repeatedRecipeID,
                recipeTitle: "Repeated",
                cookedAt: Date(timeIntervalSinceReferenceDate: 1_000 + Double(index))
            ))
        }
        for (index, recipeID) in olderRecipeIDs.enumerated() {
            context.insert(CookingHistoryModel(
                recipeId: recipeID,
                recipeTitle: "Older \(index)",
                cookedAt: Date(timeIntervalSinceReferenceDate: 900 - Double(index))
            ))
        }
        try context.save()

        let repository = CookingHistoryRepository(modelContainer: container)
        let results = try await repository.fetchUniqueRecentlyCookedRecipeIds(limit: 5)

        XCTAssertEqual(results, [repeatedRecipeID] + olderRecipeIDs)
    }

    func testCookingStatsCanBeScopedToVisibleRecipes() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let includedRecipeID = UUID()
        let excludedRecipeID = UUID()
        context.insert(CookingHistoryModel(
            recipeId: includedRecipeID,
            recipeTitle: "Included",
            cookedAt: Date(timeIntervalSinceReferenceDate: 100)
        ))
        context.insert(CookingHistoryModel(
            recipeId: excludedRecipeID,
            recipeTitle: "Excluded",
            cookedAt: Date(timeIntervalSinceReferenceDate: 200)
        ))
        try context.save()

        let repository = CookingHistoryRepository(modelContainer: container)
        let stats = try await repository.fetchCookingStats(for: [includedRecipeID])

        XCTAssertEqual(Set(stats.keys), [includedRecipeID])
        XCTAssertEqual(stats[includedRecipeID]?.count, 1)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CookingHistoryModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
