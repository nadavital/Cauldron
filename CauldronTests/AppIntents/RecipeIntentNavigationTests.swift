import XCTest
@testable import Cauldron

final class RecipeIntentNavigationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RecipeIntentNavigationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPendingRecipeSurvivesAndConsumesOnce() {
        let id = UUID()

        RecipeIntentNavigationStore.save(recipeID: id, defaults: defaults)

        XCTAssertEqual(RecipeIntentNavigationStore.pendingRecipeID(defaults: defaults), id)
        XCTAssertEqual(RecipeIntentNavigationStore.consume(defaults: defaults), id)
        XCTAssertNil(RecipeIntentNavigationStore.consume(defaults: defaults))
    }

    func testMalformedPendingIdentifierIsIgnored() {
        defaults.set("not-a-uuid", forKey: RecipeIntentNavigationStore.pendingRecipeIDKey)
        XCTAssertNil(RecipeIntentNavigationStore.pendingRecipeID(defaults: defaults))
        XCTAssertNil(RecipeIntentNavigationStore.consume(defaults: defaults))
        XCTAssertNil(defaults.string(forKey: RecipeIntentNavigationStore.pendingRecipeIDKey))
    }

    func testOlderRouteCannotConsumeNewerPendingRecipe() {
        let olderID = UUID()
        let newerID = UUID()
        RecipeIntentNavigationStore.save(recipeID: newerID, defaults: defaults)

        XCTAssertNil(
            RecipeIntentNavigationStore.consume(expectedRecipeID: olderID, defaults: defaults)
        )
        XCTAssertEqual(RecipeIntentNavigationStore.pendingRecipeID(defaults: defaults), newerID)
        XCTAssertEqual(
            RecipeIntentNavigationStore.consume(expectedRecipeID: newerID, defaults: defaults),
            newerID
        )
    }

    func testVisualSearchRouteOnlyConsumesMatchingPayload() {
        let first = [UUID(), UUID()]
        let newer = [UUID()]
        RecipeIntentNavigationStore.saveVisualSearch(recipeIDs: first, defaults: defaults)
        RecipeIntentNavigationStore.saveVisualSearch(recipeIDs: newer, defaults: defaults)

        XCTAssertFalse(RecipeIntentNavigationStore.consumeVisualSearch(
            expectedRecipeIDs: first,
            defaults: defaults
        ))
        XCTAssertEqual(RecipeIntentNavigationStore.pendingVisualSearch(defaults: defaults), newer)
        XCTAssertTrue(RecipeIntentNavigationStore.consumeVisualSearch(
            expectedRecipeIDs: newer,
            defaults: defaults
        ))
        XCTAssertTrue(RecipeIntentNavigationStore.pendingVisualSearch(defaults: defaults).isEmpty)
    }

    func testNewRecipeRouteSupersedesOlderVisualSearch() {
        RecipeIntentNavigationStore.saveVisualSearch(recipeIDs: [UUID()], defaults: defaults)
        let recipeID = UUID()
        RecipeIntentNavigationStore.save(recipeID: recipeID, defaults: defaults)

        XCTAssertFalse(RecipeIntentNavigationStore.hasPendingVisualSearch(defaults: defaults))
        XCTAssertEqual(RecipeIntentNavigationStore.pendingRecipeID(defaults: defaults), recipeID)
    }
}
