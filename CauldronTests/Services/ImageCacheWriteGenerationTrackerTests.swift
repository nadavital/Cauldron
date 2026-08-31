import XCTest
@testable import Cauldron

final class ImageCacheWriteGenerationTrackerTests: XCTestCase {
    func testForcedRefreshInvalidatesOlderWriteWithoutAffectingOtherCacheKeys() {
        var tracker = ImageCacheWriteGenerationTracker()
        let staleGeneration = tracker.generation(for: "recipe-a")
        let otherGeneration = tracker.generation(for: "recipe-b")

        let refreshedGeneration = tracker.generation(for: "recipe-a", advancing: true)

        XCTAssertFalse(tracker.isCurrent(staleGeneration, for: "recipe-a"))
        XCTAssertTrue(tracker.isCurrent(refreshedGeneration, for: "recipe-a"))
        XCTAssertTrue(tracker.isCurrent(otherGeneration, for: "recipe-b"))
    }

    func testRepeatedForcedRefreshOnlyAllowsLatestCompletionToWrite() {
        var tracker = ImageCacheWriteGenerationTracker()
        let firstRefresh = tracker.generation(for: "recipe-a", advancing: true)
        let secondRefresh = tracker.generation(for: "recipe-a", advancing: true)

        XCTAssertFalse(tracker.isCurrent(firstRefresh, for: "recipe-a"))
        XCTAssertTrue(tracker.isCurrent(secondRefresh, for: "recipe-a"))
    }

    func testExplicitSemanticVariantsRemainDistinctAcrossRequestedSizes() {
        let small = RecipeImageCacheKeyPolicy.variant(
            baseVariant: "card",
            hasExplicitVariant: true,
            targetPixelSize: 320,
            cacheIdentity: "revision"
        )
        let large = RecipeImageCacheKeyPolicy.variant(
            baseVariant: "card",
            hasExplicitVariant: true,
            targetPixelSize: 960,
            cacheIdentity: "revision"
        )

        XCTAssertEqual(small, "card_px_320_v_revision")
        XCTAssertEqual(large, "card_px_960_v_revision")
        XCTAssertNotEqual(small, large)
    }
}
