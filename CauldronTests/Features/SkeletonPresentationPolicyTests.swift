import XCTest
@testable import Cauldron

final class SkeletonPresentationPolicyTests: XCTestCase {
    func testShowsSkeletonOnlyForUnresolvedEmptyFirstLoad() {
        XCTAssertTrue(
            SkeletonPresentationPolicy.shouldShow(
                isLoading: true,
                hasResolvedOnce: false,
                hasContent: false
            )
        )
    }

    func testKeepsCachedContentVisibleDuringRefresh() {
        XCTAssertFalse(
            SkeletonPresentationPolicy.shouldShow(
                isLoading: true,
                hasResolvedOnce: false,
                hasContent: true
            )
        )
    }

    func testDoesNotReplaceResolvedEmptyState() {
        XCTAssertFalse(
            SkeletonPresentationPolicy.shouldShow(
                isLoading: false,
                hasResolvedOnce: true,
                hasContent: false
            )
        )
    }

    func testDoesNotShowSkeletonForSubsequentEmptyRefresh() {
        XCTAssertFalse(
            SkeletonPresentationPolicy.shouldShow(
                isLoading: true,
                hasResolvedOnce: true,
                hasContent: false
            )
        )
    }
}
