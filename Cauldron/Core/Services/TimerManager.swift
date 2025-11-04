//
//  TimerManager.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/4/25.
//

import Foundation
import UserNotifications
import AudioToolbox
import os
import Combine

/// Represents an active timer (running or paused)
struct ActiveTimer: Identifiable {
    let id: UUID
    let spec: TimerSpec
    let recipeName: String
    let stepIndex: Int

    // The absolute time when the timer will/would complete
    // Set once when timer starts, never recalculated for running timers
    let originalEndDate: Date

    // Pause state
    var isPaused: Bool
    var pausedAt: Date?  // When the timer was paused (for UI display)
    var pausedRemainingSeconds: Int?  // Remaining seconds when paused
    var pausedEndDate: Date?  // Stable end date snapshot when paused (for Live Activity)

    // MARK: - Initialization

    init(spec: TimerSpec, recipeName: String, stepIndex: Int) {
        self.id = UUID()
        self.spec = spec
        self.recipeName = recipeName
        self.stepIndex = stepIndex
        self.originalEndDate = Date().addingTimeInterval(TimeInterval(spec.seconds))
        self.isPaused = false
        self.pausedAt = nil
        self.pausedRemainingSeconds = nil
        self.pausedEndDate = nil
    }

    // Internal initializer for resume functionality
    init(id: UUID, spec: TimerSpec, recipeName: String, stepIndex: Int,
         originalEndDate: Date, isPaused: Bool, pausedAt: Date?, pausedRemainingSeconds: Int?, pausedEndDate: Date? = nil) {
        self.id = id
        self.spec = spec
        self.recipeName = recipeName
        self.stepIndex = stepIndex
        self.originalEndDate = originalEndDate
        self.isPaused = isPaused
        self.pausedAt = pausedAt
        self.pausedRemainingSeconds = pausedRemainingSeconds
        self.pausedEndDate = pausedEndDate
    }

    // MARK: - Computed Properties

    /// Whether the timer is currently running (not paused)
    var isRunning: Bool {
        !isPaused
    }

    /// The effective end date (handles paused state)
    var endDate: Date {
        if isPaused, let pausedEnd = pausedEndDate {
            // Paused: return stable snapshot date
            return pausedEnd
        } else {
            // Running: use the original end date
            return originalEndDate
        }
    }

    /// Calculate remaining seconds (for UI and pause logic)
    func remainingSeconds(at date: Date = Date()) -> Int {
        if isPaused, let remaining = pausedRemainingSeconds {
            return remaining
        } else {
            let remaining = originalEndDate.timeIntervalSince(date)
            return max(0, Int(remaining))
        }
    }
}

/// Manages all cooking timers
@MainActor
class TimerManager: ObservableObject {
    @Published var activeTimers: [ActiveTimer] = []

    private var timerTasks: [UUID: Task<Void, Never>] = [:]

    /// Callback for when timers change (used by CookModeCoordinator)
    var onTimersChanged: (() -> Void)?

    nonisolated init() {
        requestNotificationPermissions()
    }
    
    // MARK: - Timer Control
    
    /// Start a new timer
    func startTimer(spec: TimerSpec, stepIndex: Int, recipeName: String) {
        let timer = ActiveTimer(spec: spec, recipeName: recipeName, stepIndex: stepIndex)
        activeTimers.append(timer)

        // Start countdown task
        let task = Task {
            await runTimer(id: timer.id)
        }
        timerTasks[timer.id] = task

        // Schedule notification
        scheduleNotification(for: timer)

        // Notify listeners
        onTimersChanged?()

        AppLogger.general.info("Started timer: \(spec.label) for \(spec.seconds)s")
    }
    
    /// Pause a running timer
    func pauseTimer(id: UUID) {
        guard let index = activeTimers.firstIndex(where: { $0.id == id }),
              !activeTimers[index].isPaused else { return }

        // Calculate and save remaining time before pausing
        let remaining = activeTimers[index].remainingSeconds()
        let pausedEndDate = Date().addingTimeInterval(TimeInterval(remaining))
        activeTimers[index].isPaused = true
        activeTimers[index].pausedAt = Date()
        activeTimers[index].pausedRemainingSeconds = remaining
        activeTimers[index].pausedEndDate = pausedEndDate

        // Cancel the timer task
        timerTasks[id]?.cancel()
        timerTasks.removeValue(forKey: id)

        // Cancel scheduled notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])

        // Notify listeners
        onTimersChanged?()

        AppLogger.general.info("Paused timer: \(id) with \(remaining)s remaining")
    }
    
    /// Resume a paused timer
    func resumeTimer(id: UUID) {
        guard let index = activeTimers.firstIndex(where: { $0.id == id }),
              activeTimers[index].isPaused,
              let remaining = activeTimers[index].pausedRemainingSeconds else { return }

        // Create new timer with remaining time
        let newEndDate = Date().addingTimeInterval(TimeInterval(remaining))

        // Update to running state with new end date
        activeTimers[index] = ActiveTimer(
            id: activeTimers[index].id,
            spec: activeTimers[index].spec,
            recipeName: activeTimers[index].recipeName,
            stepIndex: activeTimers[index].stepIndex,
            originalEndDate: newEndDate,
            isPaused: false,
            pausedAt: nil,
            pausedRemainingSeconds: nil,
            pausedEndDate: nil
        )

        // Restart countdown task
        let task = Task {
            await runTimer(id: id)
        }
        timerTasks[id] = task

        // Reschedule notification with remaining time
        if let timer = activeTimers.first(where: { $0.id == id }) {
            scheduleNotification(for: timer)
        }

        // Notify listeners
        onTimersChanged?()

        AppLogger.general.info("Resumed timer: \(id) with \(remaining)s remaining")
    }
    
    /// Stop and remove a timer
    func stopTimer(id: UUID) {
        guard let index = activeTimers.firstIndex(where: { $0.id == id }) else { return }

        activeTimers.remove(at: index)
        timerTasks[id]?.cancel()
        timerTasks.removeValue(forKey: id)

        // Cancel notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])

        // Notify listeners
        onTimersChanged?()

        AppLogger.general.info("Stopped timer: \(id)")
    }
    
    /// Stop all active timers
    func stopAllTimers() {
        let ids = activeTimers.map { $0.id }
        for id in ids {
            stopTimer(id: id)
        }
    }
    
    /// Get remaining time for a timer
    func getRemainingTime(id: UUID) -> Int {
        guard let timer = activeTimers.first(where: { $0.id == id }) else { return 0 }
        return timer.remainingSeconds()
    }
    
    // MARK: - Private Helpers
    
    private func runTimer(id: UUID) async {
        while !Task.isCancelled {
            guard let timer = activeTimers.first(where: { $0.id == id }),
                  !timer.isPaused else {
                return
            }

            let remaining = timer.remainingSeconds()

            if remaining <= 0 {
                await timerCompleted(id: id)
                return
            }

            // Sleep for 1 second
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }
    
    private func timerCompleted(id: UUID) async {
        guard let timer = activeTimers.first(where: { $0.id == id }) else { return }
        
        AppLogger.general.info("Timer completed: \(timer.spec.label)")
        
        // Play haptic feedback and sound
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(1315) // Timer completion sound
        
        // Remove timer
        stopTimer(id: id)
    }
    
    private func scheduleNotification(for timer: ActiveTimer) {
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete!"
        content.body = "\(timer.spec.label) - \(timer.recipeName)"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let remaining = timer.remainingSeconds()
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(remaining),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: timer.id.uuidString,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.general.error("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    nonisolated private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                AppLogger.general.info("Notification permissions granted")
            } else if let error = error {
                AppLogger.general.error("Failed to request notification permissions: \(error.localizedDescription)")
            }
        }
    }
}
