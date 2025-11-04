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

/// Represents an active running timer
struct ActiveTimer: Identifiable {
    let id: UUID
    let spec: TimerSpec
    let recipeName: String
    let stepIndex: Int
    var startedAt: Date  // Made mutable for pause/resume
    var pausedAt: Date?
    var remainingSeconds: Int
    var isRunning: Bool

    init(spec: TimerSpec, recipeName: String, stepIndex: Int) {
        self.id = UUID()
        self.spec = spec
        self.recipeName = recipeName
        self.stepIndex = stepIndex
        self.startedAt = Date()
        self.pausedAt = nil
        self.remainingSeconds = spec.seconds
        self.isRunning = true
    }

    /// Calculate when the timer will end
    var endDate: Date {
        if isRunning {
            // For running timers, calculate based on elapsed time
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = max(0, TimeInterval(remainingSeconds) - elapsed)
            return Date().addingTimeInterval(remaining)
        } else {
            // Paused - calculate from current time with remaining seconds
            return Date().addingTimeInterval(TimeInterval(remainingSeconds))
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
              activeTimers[index].isRunning else { return }

        // Calculate and save remaining time before pausing
        let remaining = getRemainingTime(id: id)
        activeTimers[index].remainingSeconds = remaining
        activeTimers[index].isRunning = false
        activeTimers[index].pausedAt = Date()

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
              !activeTimers[index].isRunning else { return }

        // Update startedAt to current time (reset the timer start point)
        activeTimers[index].startedAt = Date()
        activeTimers[index].isRunning = true
        activeTimers[index].pausedAt = nil

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

        AppLogger.general.info("Resumed timer: \(id)")
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
        
        if timer.isRunning {
            let elapsed = Int(Date().timeIntervalSince(timer.startedAt))
            return max(0, timer.remainingSeconds - elapsed)
        } else {
            return timer.remainingSeconds
        }
    }
    
    // MARK: - Private Helpers
    
    private func runTimer(id: UUID) async {
        while !Task.isCancelled {
            guard let index = activeTimers.firstIndex(where: { $0.id == id }),
                  activeTimers[index].isRunning else {
                return
            }
            
            let remaining = getRemainingTime(id: id)
            
            if remaining <= 0 {
                await timerCompleted(id: id)
                return
            }
            
            // Sleep for 1 second
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every 1.0s
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
        
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(timer.remainingSeconds),
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
