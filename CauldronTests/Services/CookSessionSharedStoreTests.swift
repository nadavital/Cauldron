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

    func testRoundTripAndBoundsNormalization() {
        let recipeID = UUID()
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: recipeID,
                stepIndex: 99,
                totalSteps: 3,
                sessionStartTime: Date(timeIntervalSince1970: 10)
            ),
            defaults: defaults
        )

        let restored = CookSessionSharedStore.readForTesting(defaults: defaults)
        XCTAssertEqual(restored?.recipeID, recipeID)
        XCTAssertEqual(restored?.stepIndex, 2)
        XCTAssertEqual(restored?.totalSteps, 3)
    }

    func testMoveRespectsBoundsAndIncrementsRevisionOnlyOnChange() {
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: UUID(),
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

    func testClearRemovesSession() {
        CookSessionSharedStore.saveForTesting(
            CookSessionSharedSnapshot(
                recipeID: UUID(),
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
                stepIndex: 0,
                totalSteps: 0,
                sessionStartTime: .now
            ),
            defaults: defaults
        )
        XCTAssertNil(CookSessionSharedStore.readForTesting(defaults: defaults))
    }
}
