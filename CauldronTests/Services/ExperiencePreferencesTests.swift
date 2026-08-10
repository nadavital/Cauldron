import XCTest
@testable import Cauldron

@MainActor
final class ExperiencePreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ExperiencePreferencesTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsPreserveExistingExperience() {
        let preferences = ExperiencePreferences(defaults: defaults)

        XCTAssertEqual(preferences.groceryGrouping, .recipe)
        XCTAssertEqual(preferences.recipeScaleFactor, 1)
        XCTAssertEqual(preferences.recipeUnitSystem, .original)
        XCTAssertTrue(preferences.keepScreenAwake)
        XCTAssertFalse(preferences.largerStepText)
        XCTAssertFalse(preferences.reduceMotion)
        XCTAssertTrue(preferences.timerHaptics)
        XCTAssertTrue(preferences.timerSounds)
    }

    func testInvalidStoredEnumsAndScaleUseSafeFallbacks() {
        defaults.set("not-a-group", forKey: ExperiencePreferences.Key.groceryGrouping)
        defaults.set(Double.nan, forKey: ExperiencePreferences.Key.recipeScaleFactor)
        defaults.set("martian", forKey: ExperiencePreferences.Key.recipeUnitSystem)

        let preferences = ExperiencePreferences(defaults: defaults)

        XCTAssertEqual(preferences.groceryGrouping, .recipe)
        XCTAssertEqual(preferences.recipeScaleFactor, 1)
        XCTAssertEqual(preferences.recipeUnitSystem, .original)
        XCTAssertEqual(defaults.string(forKey: ExperiencePreferences.Key.groceryGrouping), "Recipe")
        XCTAssertEqual(defaults.double(forKey: ExperiencePreferences.Key.recipeScaleFactor), 1)
        XCTAssertEqual(defaults.string(forKey: ExperiencePreferences.Key.recipeUnitSystem), "original")
    }

    func testUnsupportedScaleAssignmentIsNormalizedAndPersisted() {
        let preferences = ExperiencePreferences(defaults: defaults)

        preferences.recipeScaleFactor = 7.25

        XCTAssertEqual(preferences.recipeScaleFactor, 1)
        XCTAssertEqual(defaults.double(forKey: ExperiencePreferences.Key.recipeScaleFactor), 1)
    }

    func testTypedMutationsRoundTripThroughInjectedDefaults() {
        let preferences = ExperiencePreferences(defaults: defaults)
        preferences.groceryGrouping = .none
        preferences.recipeScaleFactor = 2
        preferences.recipeUnitSystem = .metric
        preferences.keepScreenAwake = false
        preferences.largerStepText = true
        preferences.reduceMotion = true
        preferences.timerHaptics = false
        preferences.timerSounds = false

        let reopened = ExperiencePreferences(defaults: defaults)

        XCTAssertEqual(reopened.groceryGrouping, .none)
        XCTAssertEqual(reopened.recipeScaleFactor, 2)
        XCTAssertEqual(reopened.recipeUnitSystem, .metric)
        XCTAssertFalse(reopened.keepScreenAwake)
        XCTAssertTrue(reopened.largerStepText)
        XCTAssertTrue(reopened.reduceMotion)
        XCTAssertFalse(reopened.timerHaptics)
        XCTAssertFalse(reopened.timerSounds)
    }

    func testCookAwakePolicyRequiresAllThreeConditions() {
        XCTAssertTrue(CookAwakePolicy.shouldDisableIdleTimer(
            sessionIsActive: true,
            applicationIsActive: true,
            keepScreenAwake: true
        ))
        XCTAssertFalse(CookAwakePolicy.shouldDisableIdleTimer(
            sessionIsActive: false,
            applicationIsActive: true,
            keepScreenAwake: true
        ))
        XCTAssertFalse(CookAwakePolicy.shouldDisableIdleTimer(
            sessionIsActive: true,
            applicationIsActive: false,
            keepScreenAwake: true
        ))
        XCTAssertFalse(CookAwakePolicy.shouldDisableIdleTimer(
            sessionIsActive: true,
            applicationIsActive: true,
            keepScreenAwake: false
        ))
    }
}
