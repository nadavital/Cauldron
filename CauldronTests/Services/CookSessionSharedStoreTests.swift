import XCTest
@testable import Cauldron

final class CookSessionSharedStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "CookSessionSharedStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testReferenceUpdatesPreserveConcurrentWidgetStepAndSurviveReload() throws {
        let initial = CookSessionSharedSnapshot(recipeID: UUID(), ownerID: UUID(), stepIndex: 0,
                                               totalSteps: 3, sessionStartTime: .now)
        CookSessionSharedStore.saveForTesting(initial, defaults: defaults)
        _ = CookSessionSharedStore.moveForTesting(by: 1, expected: initial, defaults: defaults)
        let ingredient = UUID()
        let updated = try XCTUnwrap(CookSessionSharedStore.updateReference(
            .toggleIngredient(ingredient), expected: initial, defaults: defaults, usesFileAuthority: false
        ))
        XCTAssertEqual(updated.stepIndex, 1)
        XCTAssertEqual(updated.revision, 2)
        _ = CookSessionSharedStore.updateReference(.selectPage(1), expected: initial,
                                                   defaults: defaults, usesFileAuthority: false)
        let reloaded = try XCTUnwrap(CookSessionSharedStore.readForTesting(defaults: UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(reloaded.referenceState?.checkedIngredientIDs, [ingredient])
        XCTAssertEqual(reloaded.referenceState?.page, 1)
        let next = CookSessionSharedStore.moveForTesting(by: 1, expected: reloaded, defaults: defaults)
        XCTAssertEqual(next?.referenceState, reloaded.referenceState)
        XCTAssertEqual(next?.stepIndex, 2)
    }

    func testReferenceMutationRejectsReplacedSessionAndAnotherOwner() {
        let initial = CookSessionSharedSnapshot(recipeID: UUID(), ownerID: UUID(), stepIndex: 0,
                                               totalSteps: 3, sessionStartTime: .now)
        var replacement = initial
        replacement.sessionStartTime = initial.sessionStartTime.addingTimeInterval(1)
        CookSessionSharedStore.saveForTesting(replacement, defaults: defaults)
        XCTAssertNil(CookSessionSharedStore.updateReference(.selectPage(1), expected: initial,
                                                             defaults: defaults, usesFileAuthority: false))
        replacement = initial
        replacement.ownerID = UUID()
        CookSessionSharedStore.saveForTesting(replacement, defaults: defaults)
        XCTAssertNil(CookSessionSharedStore.updateReference(.toggleIngredient(UUID()), expected: initial,
                                                             defaults: defaults, usesFileAuthority: false))
    }

    func testLegacySnapshotWithoutReferenceStateStillDecodes() throws {
        let initial = CookSessionSharedSnapshot(recipeID: UUID(), ownerID: UUID(), stepIndex: 1,
                                               totalSteps: 3, sessionStartTime: .now)
        let data = try JSONEncoder().encode(initial)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "referenceState")
        let decoded = try JSONDecoder().decode(CookSessionSharedSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.stepIndex, 1)
        XCTAssertNil(decoded.referenceState)
    }

    func testRoundTripAndBoundsNormalization() {
        let recipeID = UUID()
        let ownerID = UUID()
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: recipeID,
                ownerID: ownerID,
                stepIndex: 99,
                totalSteps: 3,
                sessionStartTime: Date(timeIntervalSince1970: 10)
            ),
            defaults: defaults
        )

        let restored = CookSessionSharedStore.readForTesting(defaults: defaults)
        XCTAssertEqual(restored?.recipeID, recipeID)
        XCTAssertEqual(restored?.ownerID, ownerID)
        XCTAssertEqual(restored?.stepIndex, 2)
        XCTAssertEqual(restored?.totalSteps, 3)
    }

    func testOwnerlessLegacySnapshotDoesNotBelongToAnyAccount() {
        let userID = UUID()
        let ownerless = CookSessionSharedSnapshot(
            recipeID: UUID(),
            stepIndex: 0,
            totalSteps: 1,
            sessionStartTime: .now
        )
        let owned = CookSessionSharedSnapshot(
            recipeID: UUID(),
            ownerID: userID,
            stepIndex: 0,
            totalSteps: 1,
            sessionStartTime: .now
        )

        XCTAssertFalse(ownerless.belongs(to: userID))
        XCTAssertTrue(owned.belongs(to: userID))
        CookSessionSharedStore.saveForTesting(ownerless, defaults: defaults)
        XCTAssertNil(CookSessionSharedStore.readForTesting(defaults: defaults))
    }

    func testSharedRecipePayloadRoundTripsIndependentlyOfRecipeOwner() throws {
        let recipe = Recipe(
            title: "Friend's Soup",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Simmer")],
            ownerId: UUID(),
            isPreview: true
        )
        let data = try XCTUnwrap(CookSessionRecipePayloadCodec.encode(recipe))

        let restored = CookSessionRecipePayloadCodec.decode(data, recipeID: recipe.id)

        XCTAssertEqual(restored, recipe)
        XCTAssertNil(CookSessionRecipePayloadCodec.decode(data, recipeID: UUID()))
    }

    func testMoveRespectsBoundsAndIncrementsRevisionOnlyOnChange() {
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: UUID(),
                ownerID: UUID(),
                stepIndex: 0,
                totalSteps: 2,
                sessionStartTime: .now
            ),
            defaults: defaults
        )

        XCTAssertEqual(CookSessionSharedStore.moveForTesting(by: -1, defaults: defaults)?.revision, 0)
        XCTAssertEqual(CookSessionSharedStore.moveForTesting(by: 1, defaults: defaults)?.revision, 1)
        XCTAssertEqual(CookSessionSharedStore.moveForTesting(by: 1, defaults: defaults)?.revision, 1)
        XCTAssertEqual(CookSessionSharedStore.readForTesting(defaults: defaults)?.stepIndex, 1)
    }

    func testMoveRejectsReplacedSessionEvenForSameRecipeAndRevision() {
        let recipeID = UUID()
        let ownerID = UUID()
        let oldSession = CookSessionSharedSnapshot(
            recipeID: recipeID,
            ownerID: ownerID,
            stepIndex: 0,
            totalSteps: 3,
            sessionStartTime: Date(timeIntervalSince1970: 10)
        )
        let replacement = CookSessionSharedSnapshot(
            recipeID: recipeID,
            ownerID: ownerID,
            stepIndex: 0,
            totalSteps: 3,
            sessionStartTime: Date(timeIntervalSince1970: 20)
        )
        CookSessionSharedStore.saveForTesting(replacement, defaults: defaults)

        XCTAssertNil(CookSessionSharedStore.moveForTesting(
            by: 1,
            expected: oldSession,
            defaults: defaults
        ))
        XCTAssertEqual(CookSessionSharedStore.readForTesting(defaults: defaults), replacement)
    }

    func testMoveRejectsDifferentOwnerEvenWhenOtherSessionIdentityMatches() {
        let recipeID = UUID()
        let sessionStart = Date(timeIntervalSince1970: 10)
        let oldSession = CookSessionSharedSnapshot(
            recipeID: recipeID,
            ownerID: UUID(),
            stepIndex: 0,
            totalSteps: 3,
            sessionStartTime: sessionStart
        )
        let replacement = CookSessionSharedSnapshot(
            recipeID: recipeID,
            ownerID: UUID(),
            stepIndex: 0,
            totalSteps: 3,
            sessionStartTime: sessionStart
        )
        CookSessionSharedStore.saveForTesting(replacement, defaults: defaults)

        XCTAssertNil(CookSessionSharedStore.moveForTesting(
            by: 1,
            expected: oldSession,
            defaults: defaults
        ))
        XCTAssertEqual(CookSessionSharedStore.readForTesting(defaults: defaults), replacement)
    }

    func testClearRemovesSession() {
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: UUID(),
                ownerID: UUID(),
                stepIndex: 0,
                totalSteps: 1,
                sessionStartTime: .now
            ),
            defaults: defaults
        )
        CookSessionSharedStore.clearForTesting(defaults: defaults)
        XCTAssertNil(CookSessionSharedStore.readForTesting(defaults: defaults))
    }

    func testInvalidEmptySessionIsRejected() {
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: UUID(),
                ownerID: UUID(),
                stepIndex: 0,
                totalSteps: 0,
                sessionStartTime: .now
            ),
            defaults: defaults
        )
        XCTAssertNil(CookSessionSharedStore.readForTesting(defaults: defaults))
    }
}
