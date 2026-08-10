import XCTest
@testable import Cauldron

@MainActor
final class CookModeCoordinatorAwakePolicyTests: XCTestCase {
    private final class IdleTimerSpy: IdleTimerControlling {
        var isIdleTimerDisabled = false
    }

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CookModeCoordinatorAwakePolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testActiveForegroundSessionPreservesKeepAwakeDefault() {
        let spy = IdleTimerSpy()
        let coordinator = makeCoordinator(spy: spy, applicationIsActive: true)

        coordinator.isActive = true

        XCTAssertTrue(spy.isIdleTimerDisabled)
    }

    func testBackgroundImmediatelyRestoresIdleTimerAndForegroundReappliesPolicy() {
        let spy = IdleTimerSpy()
        let coordinator = makeCoordinator(spy: spy, applicationIsActive: true)
        coordinator.isActive = true

        coordinator.setApplicationActive(false)
        XCTAssertFalse(spy.isIdleTimerDisabled)

        coordinator.setApplicationActive(true)
        XCTAssertTrue(spy.isIdleTimerDisabled)
    }

    func testEndingSessionAlwaysRestoresIdleTimer() {
        let spy = IdleTimerSpy()
        let coordinator = makeCoordinator(spy: spy, applicationIsActive: true)
        coordinator.isActive = true

        coordinator.endSession()

        XCTAssertFalse(spy.isIdleTimerDisabled)
    }

    func testOptedOutPreferenceNeverDisablesIdleTimer() {
        let spy = IdleTimerSpy()
        let preferences = ExperiencePreferences(defaults: defaults)
        preferences.keepScreenAwake = false
        let coordinator = CookModeCoordinator(
            dependencies: .preview(),
            experiencePreferences: preferences,
            idleTimerController: spy,
            applicationIsActive: true,
            observesApplicationLifecycle: false
        )

        coordinator.isActive = true

        XCTAssertFalse(spy.isIdleTimerDisabled)
    }

    private func makeCoordinator(
        spy: IdleTimerSpy,
        applicationIsActive: Bool
    ) -> CookModeCoordinator {
        CookModeCoordinator(
            dependencies: .preview(),
            experiencePreferences: ExperiencePreferences(defaults: defaults),
            idleTimerController: spy,
            applicationIsActive: applicationIsActive,
            observesApplicationLifecycle: false
        )
    }
}
