import XCTest
@testable import Cauldron

final class WebSharePublicationReceiptStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "WebSharePublicationReceiptStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCanonicalRecipeURLDoesNotDependOnUsername() {
        let recipeID = UUID(uuidString: "7DBEAFFD-895F-43B1-9985-463F36EA5D8C")!
        XCTAssertEqual(
            WebShareCanonicalURL.recipe(id: recipeID).absoluteString,
            "https://cauldronrecipes.com/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C"
        )
    }

    func testReceiptOnlyMatchesThePublishedRevision() {
        let ownerID = UUID()
        let initialDate = Date(timeIntervalSince1970: 1_788_000_000)
        let initial = makeRecipe(ownerID: ownerID, updatedAt: initialDate)
        let store = WebSharePublicationReceiptStore(defaults: defaults)

        XCTAssertFalse(store.containsCurrentRevision(of: initial))
        store.record(initial)
        XCTAssertTrue(store.containsCurrentRevision(of: initial))

        let edited = makeRecipe(
            id: initial.id,
            ownerID: ownerID,
            updatedAt: initialDate.addingTimeInterval(1)
        )
        XCTAssertFalse(store.containsCurrentRevision(of: edited))
    }

    func testRemovingReceiptMakesTheLinkRequirePublicationAgain() {
        let recipe = makeRecipe(
            ownerID: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_788_000_000)
        )
        let store = WebSharePublicationReceiptStore(defaults: defaults)
        store.record(recipe)
        store.remove(recipeID: recipe.id, ownerID: recipe.ownerId!)
        XCTAssertFalse(store.containsCurrentRevision(of: recipe))
    }

    private func makeRecipe(
        id: UUID = UUID(),
        ownerID: UUID,
        updatedAt: Date
    ) -> Recipe {
        Recipe(
            id: id,
            title: "Soup",
            ingredients: [],
            steps: [],
            ownerId: ownerID,
            updatedAt: updatedAt
        )
    }
}
