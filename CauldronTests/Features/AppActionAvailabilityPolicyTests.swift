import XCTest
@testable import Cauldron

final class AppActionAvailabilityPolicyTests: XCTestCase {
    func testEnabledActionRemainsEnabled() {
        XCTAssertFalse(
            AppActionAvailabilityPolicy.isDisabled(
                isBusy: false,
                isExplicitlyDisabled: false
            )
        )
    }

    func testBusyActionIsDisabledToPreventDuplicateSubmission() {
        XCTAssertTrue(
            AppActionAvailabilityPolicy.isDisabled(
                isBusy: true,
                isExplicitlyDisabled: false
            )
        )
    }

    func testExplicitlyDisabledActionRemainsDisabledWhenIdle() {
        XCTAssertTrue(
            AppActionAvailabilityPolicy.isDisabled(
                isBusy: false,
                isExplicitlyDisabled: true
            )
        )
    }
}
