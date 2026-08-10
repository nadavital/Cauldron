import Foundation
import Testing
import UserNotifications
@testable import Cauldron

@MainActor
struct TimerFeedbackPolicyTests {
    @Test func injectedPreferencesEnableAllTimerFeedback() {
        let preferences = makePreferences(haptics: true, sounds: true)
        let manager = makeManager(preferences: preferences)

        #expect(manager.feedbackDecision == TimerFeedbackDecision(
            playsHaptic: true,
            playsSound: true,
            notificationIncludesSound: true
        ))
    }

    @Test func injectedPreferencesDisableAllTimerFeedback() {
        let preferences = makePreferences(haptics: false, sounds: false)
        let manager = makeManager(preferences: preferences)

        #expect(manager.feedbackDecision == TimerFeedbackDecision(
            playsHaptic: false,
            playsSound: false,
            notificationIncludesSound: false
        ))
    }

    @Test func hapticAndSoundPreferencesRemainIndependentAndUpdateLive() {
        let preferences = makePreferences(haptics: false, sounds: true)
        let manager = makeManager(preferences: preferences)

        #expect(manager.feedbackDecision == TimerFeedbackDecision(
            playsHaptic: false,
            playsSound: true,
            notificationIncludesSound: true
        ))

        preferences.timerHaptics = true
        preferences.timerSounds = false

        #expect(manager.feedbackDecision == TimerFeedbackDecision(
            playsHaptic: true,
            playsSound: false,
            notificationIncludesSound: false
        ))
    }

    @Test func changingSoundPreferenceReplacesActiveNotificationWithSilentRequest() async {
        let preferences = makePreferences(haptics: true, sounds: true)
        let scheduler = RecordingFeedbackNotificationScheduler()
        let manager = TimerManager(
            sharedDefaults: nil,
            requestNotificationPermission: false,
            schedulesNotifications: true,
            notificationScheduler: scheduler,
            experiencePreferences: preferences
        )
        manager.startTimer(
            spec: TimerSpec(seconds: 60, label: "Sauce"),
            stepIndex: 0,
            recipeName: "Pasta"
        )
        let timerID = manager.activeTimers[0].id

        #expect(scheduler.requests.count == 1)
        #expect(scheduler.requests[0].content.sound != nil)

        preferences.timerSounds = false
        await Task.yield()

        #expect(scheduler.canceledIDs == [timerID])
        #expect(scheduler.requests.count == 2)
        #expect(scheduler.requests[1].identifier == timerID.uuidString)
        #expect(scheduler.requests[1].content.sound == nil)

        manager.stopAllTimers()
    }

    private func makePreferences(haptics: Bool, sounds: Bool) -> ExperiencePreferences {
        let suiteName = "TimerFeedbackPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(haptics, forKey: ExperiencePreferences.Key.timerHaptics)
        defaults.set(sounds, forKey: ExperiencePreferences.Key.timerSounds)
        return ExperiencePreferences(defaults: defaults)
    }

    private func makeManager(preferences: ExperiencePreferences) -> TimerManager {
        TimerManager(
            sharedDefaults: nil,
            requestNotificationPermission: false,
            schedulesNotifications: false,
            notificationScheduler: NoopTimerNotificationScheduler(),
            experiencePreferences: preferences
        )
    }
}

@MainActor
private final class RecordingFeedbackNotificationScheduler: TimerNotificationScheduling {
    var requests: [UNNotificationRequest] = []
    var canceledIDs: [UUID] = []

    func schedule(_ request: UNNotificationRequest) {
        requests.append(request)
    }

    func cancel(ids: [UUID]) {
        canceledIDs.append(contentsOf: ids)
    }
}
