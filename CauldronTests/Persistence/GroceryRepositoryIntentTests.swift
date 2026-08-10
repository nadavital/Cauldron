import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class GroceryRepositoryIntentTests: XCTestCase {
    func testAddItemsFromRecipeIfAbsentIsIdempotent() async throws {
        let repository = GroceryRepository(modelContainer: try TestModelContainer.create())
        let recipeID = UUID().uuidString
        let items: [(name: String, quantity: Quantity?)] = [
            ("Flour", Quantity(value: 2, unit: .cup)),
            ("Salt", nil)
        ]

        let firstCount = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Bread",
            items: items
        )
        let retryCount = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Bread",
            items: items
        )
        let stored = try await repository.fetchAllItemsForDisplay()

        XCTAssertEqual(firstCount, 2)
        XCTAssertEqual(retryCount, 0)
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.recipeID == recipeID })
    }

    func testAddItemsFromRecipeIfAbsentRestoresRemovedIngredient() async throws {
        let repository = GroceryRepository(modelContainer: try TestModelContainer.create())
        let recipeID = UUID().uuidString
        let items: [(name: String, quantity: Quantity?)] = [
            ("Flour", Quantity(value: 2, unit: .cup)),
            ("Salt", nil)
        ]
        _ = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Bread",
            items: items
        )
        let storedBeforeRemoval = try await repository.fetchAllItemsForDisplay()
        let salt = try XCTUnwrap(storedBeforeRemoval.first { $0.name == "Salt" })
        try await repository.deleteItem(id: salt.id)

        let addedCount = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Bread",
            items: items
        )

        XCTAssertEqual(addedCount, 1)
        let storedAfterRestore = try await repository.fetchAllItemsForDisplay()
        XCTAssertEqual(storedAfterRestore.count, 2)
    }

    func testAddItemsFromRecipeIfAbsentAddsNewAndRespectsIngredientMultiset() async throws {
        let repository = GroceryRepository(modelContainer: try TestModelContainer.create())
        let recipeID = UUID().uuidString
        let initial: [(name: String, quantity: Quantity?)] = [("Lime", nil)]
        _ = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Salsa",
            items: initial
        )

        let updated: [(name: String, quantity: Quantity?)] = [
            (" lime ", nil),
            ("LIME", nil),
            ("Salt", Quantity(value: 1, unit: .teaspoon))
        ]
        let addedCount = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: "Salsa",
            items: updated
        )
        let stored = try await repository.fetchAllItemsForDisplay()

        XCTAssertEqual(addedCount, 2)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(stored.filter { $0.name.trimmingCharacters(in: .whitespaces) == "LIME" }.count, 1)
    }

    func testAuthorizedRecipeMutationDoesNotPersistWhenIdentityExpiresBeforeCommit() async throws {
        let container = try TestModelContainer.create()
        let repository = GroceryRepository(modelContainer: container)
        let authorization = ExpiringCommitAuthorization()

        let result = try await repository.addItemsFromRecipeIfAbsent(
            recipeID: UUID().uuidString,
            recipeName: "Private Recipe",
            items: [("Secret ingredient", nil)],
            isAuthorizedToCommit: { authorization.check() }
        )

        XCTAssertNil(result)
        let context = ModelContext(container)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryListModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryItemModel>()).isEmpty)
    }
}

private final class ExpiringCommitAuthorization {
    private var checkCount = 0

    func check() -> Bool {
        checkCount += 1
        return checkCount == 1
    }
}
