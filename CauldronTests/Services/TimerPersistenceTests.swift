import XCTest
import UserNotifications
@testable import Cauldron

@MainActor
final class TimerPersistenceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "TimerPersistenceTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRunningTimerRestoresAndExpiredTimerIsDropped() async {
        let manager = makeManager()
        manager.startTimer(
            spec: TimerSpec(seconds: 60, label: "Sauce"),
            stepIndex: 1,
            recipeName: "Pasta"
        )
        let restored = makeManager()
        XCTAssertEqual(restored.activeTimers.count, 1)
        XCTAssertEqual(restored.activeTimers.first?.spec.label, "Sauce")
        restored.stopAllTimers()
        manager.stopAllTimers()
    }

    func testPausedTimerRestoresItsRemainingDuration() async {
        let manager = makeManager()
        manager.startTimer(
            spec: TimerSpec(seconds: 90, label: "Rest"),
            stepIndex: 2,
            recipeName: "Bread"
        )
        guard let id = manager.activeTimers.first?.id else { return XCTFail("Missing timer") }
        manager.pauseTimer(id: id)

        let restored = makeManager()
        XCTAssertEqual(restored.activeTimers.first?.isPaused, true)
        XCTAssertGreaterThan(restored.activeTimers.first?.pausedRemainingSeconds ?? 0, 0)
        restored.stopAllTimers()
        manager.stopAllTimers()
    }

    func testPausedTimerRestoreCancelsAnyStaleNotification() async throws {
        let id = UUID()
        let paused = ActiveTimer(
            id: id,
            spec: TimerSpec(seconds: 90, label: "Rest"),
            recipeName: "Bread",
            stepIndex: 2,
            originalEndDate: .now.addingTimeInterval(90),
            isPaused: true,
            pausedAt: .now,
            pausedRemainingSeconds: 45,
            pausedEndDate: .now.addingTimeInterval(45)
        )
        defaults.set(try JSONEncoder().encode([paused]), forKey: TimerManager.storageKey)
        let scheduler = RecordingTimerNotificationScheduler()

        _ = TimerManager(
            sharedDefaults: defaults,
            requestNotificationPermission: false,
            schedulesNotifications: true,
            notificationScheduler: scheduler
        )

        XCTAssertEqual(scheduler.canceledIDs, [id])
        XCTAssertTrue(scheduler.scheduledIDs.isEmpty)
    }

    func testStopAllClearsPersistedTimers() async {
        let manager = makeManager()
        manager.startTimer(
            spec: TimerSpec(seconds: 60, label: "Bake"),
            stepIndex: 0,
            recipeName: "Cake"
        )
        manager.stopAllTimers()

        let restored = makeManager()
        XCTAssertTrue(restored.activeTimers.isEmpty)
    }

    func testExpiredRunningTimerIsDroppedFromMemoryAndPersistence() throws {
        let expired = ActiveTimer(
            id: UUID(),
            spec: TimerSpec(seconds: 60, label: "Expired"),
            recipeName: "Soup",
            stepIndex: 0,
            originalEndDate: Date(timeIntervalSince1970: 10),
            isPaused: false,
            pausedAt: nil,
            pausedRemainingSeconds: nil
        )
        defaults.set(try JSONEncoder().encode([expired]), forKey: TimerManager.storageKey)

        let restored = makeManager()
        XCTAssertTrue(restored.activeTimers.isEmpty)
        let data = try XCTUnwrap(defaults.data(forKey: TimerManager.storageKey))
        XCTAssertTrue(try JSONDecoder().decode([ActiveTimer].self, from: data).isEmpty)
    }

    func testInvalidPausedTimerIsDropped() throws {
        let invalid = ActiveTimer(
            id: UUID(),
            spec: TimerSpec(seconds: 60, label: "Invalid"),
            recipeName: "Soup",
            stepIndex: 0,
            originalEndDate: .now,
            isPaused: true,
            pausedAt: .now,
            pausedRemainingSeconds: nil
        )
        defaults.set(try JSONEncoder().encode([invalid]), forKey: TimerManager.storageKey)
        XCTAssertTrue(makeManager().activeTimers.isEmpty)
    }

    private func makeManager() -> TimerManager {
        TimerManager(
            sharedDefaults: defaults,
            requestNotificationPermission: false,
            schedulesNotifications: false,
            notificationScheduler: NoopTimerNotificationScheduler()
        )
    }
}

@MainActor
private final class RecordingTimerNotificationScheduler: TimerNotificationScheduling {
    var scheduledIDs: [UUID] = []
    var canceledIDs: [UUID] = []

    func schedule(_ request: UNNotificationRequest) {
        if let id = UUID(uuidString: request.identifier) { scheduledIDs.append(id) }
    }

    func cancel(ids: [UUID]) {
        canceledIDs.append(contentsOf: ids)
    }
}
