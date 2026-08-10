import Foundation
import Observation
import UIKit

extension Notification.Name {
    nonisolated static let experiencePreferencesChanged = Notification.Name(
        "ExperiencePreferencesChanged"
    )
}

/// Typed, device-local presentation preferences.
///
/// These values intentionally do not sync with recipe data. A user may want a
/// larger Cook Mode or different units on one device without changing another.
@MainActor
@Observable
final class ExperiencePreferences {
    static let shared = ExperiencePreferences()

    nonisolated enum Key {
        static let groceryGrouping = "experience.groceries.grouping.v1"
        static let recipeScaleFactor = "experience.recipes.scale-factor.v1"
        static let recipeUnitSystem = "experience.recipes.unit-system.v1"
        static let keepScreenAwake = "experience.cook.keep-screen-awake.v1"
        static let largerStepText = "experience.cook.larger-step-text.v1"
        static let reduceMotion = "experience.cook.reduce-motion.v1"
        static let timerHaptics = "experience.cook.timer-haptics.v1"
        static let timerSounds = "experience.cook.timer-sounds.v1"
    }

    nonisolated static let supportedScaleFactors: [Double] = [0.5, 1, 2, 3]

    @ObservationIgnored private let defaults: UserDefaults

    var groceryGrouping: GroceryGroupingType {
        didSet {
            persist(
                groceryGrouping.rawValue,
                key: Key.groceryGrouping,
                oldValue: oldValue.rawValue
            )
        }
    }

    private var storedRecipeScaleFactor: Double

    var recipeScaleFactor: Double {
        get { storedRecipeScaleFactor }
        set {
            let normalized = Self.validScaleFactor(newValue)
            let oldValue = storedRecipeScaleFactor
            guard normalized != oldValue else { return }
            storedRecipeScaleFactor = normalized
            persist(normalized, key: Key.recipeScaleFactor, oldValue: oldValue)
        }
    }

    var recipeUnitSystem: UnitSystem {
        didSet {
            persist(
                recipeUnitSystem.rawValue,
                key: Key.recipeUnitSystem,
                oldValue: oldValue.rawValue
            )
        }
    }

    var keepScreenAwake: Bool {
        didSet { persist(keepScreenAwake, key: Key.keepScreenAwake, oldValue: oldValue) }
    }

    var largerStepText: Bool {
        didSet { persist(largerStepText, key: Key.largerStepText, oldValue: oldValue) }
    }

    var reduceMotion: Bool {
        didSet { persist(reduceMotion, key: Key.reduceMotion, oldValue: oldValue) }
    }

    var timerHaptics: Bool {
        didSet { persist(timerHaptics, key: Key.timerHaptics, oldValue: oldValue) }
    }

    var timerSounds: Bool {
        didSet { persist(timerSounds, key: Key.timerSounds, oldValue: oldValue) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let groupingRaw = defaults.string(forKey: Key.groceryGrouping)
        groceryGrouping = groupingRaw.flatMap(GroceryGroupingType.init(rawValue:)) ?? .recipe

        let storedScale = defaults.object(forKey: Key.recipeScaleFactor) as? NSNumber
        storedRecipeScaleFactor = Self.validScaleFactor(storedScale?.doubleValue)

        let unitsRaw = defaults.string(forKey: Key.recipeUnitSystem)
        recipeUnitSystem = unitsRaw.flatMap(UnitSystem.init(rawValue:)) ?? .original

        keepScreenAwake = Self.bool(defaults, key: Key.keepScreenAwake, defaultValue: true)
        largerStepText = Self.bool(defaults, key: Key.largerStepText, defaultValue: false)
        reduceMotion = Self.bool(defaults, key: Key.reduceMotion, defaultValue: false)
        timerHaptics = Self.bool(defaults, key: Key.timerHaptics, defaultValue: true)
        timerSounds = Self.bool(defaults, key: Key.timerSounds, defaultValue: true)

        // Repair invalid persisted values once so every consumer sees the same
        // fallback, including extensions that read UserDefaults directly.
        defaults.set(groceryGrouping.rawValue, forKey: Key.groceryGrouping)
        defaults.set(recipeScaleFactor, forKey: Key.recipeScaleFactor)
        defaults.set(recipeUnitSystem.rawValue, forKey: Key.recipeUnitSystem)
    }

    nonisolated static func validScaleFactor(_ candidate: Double?) -> Double {
        guard let candidate,
              candidate.isFinite,
              supportedScaleFactors.contains(where: { abs($0 - candidate) < 0.000_001 }) else {
            return 1
        }
        return supportedScaleFactors.first(where: { abs($0 - candidate) < 0.000_001 }) ?? 1
    }

    private nonisolated static func bool(
        _ defaults: UserDefaults,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private func persist<T: Equatable>(_ value: T, key: String, oldValue: T) {
        guard value != oldValue else { return }
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .experiencePreferencesChanged, object: self)
    }
}

/// Pure policy used by Cook Mode and unit tests. The idle timer is disabled
/// only while a session is active, the app is foreground-active, and the user
/// has opted into the existing keep-awake behavior.
nonisolated enum CookAwakePolicy {
    static func shouldDisableIdleTimer(
        sessionIsActive: Bool,
        applicationIsActive: Bool,
        keepScreenAwake: Bool
    ) -> Bool {
        sessionIsActive && applicationIsActive && keepScreenAwake
    }
}

@MainActor
protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

@MainActor
final class ApplicationIdleTimerController: IdleTimerControlling {
    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}
