//
//  CookSessionManager.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Manages an active cooking session
actor CookSessionManager {
    
    enum SessionState {
        case idle
        case cooking(recipeId: UUID, currentStep: Int)
        case paused(recipeId: UUID, currentStep: Int)
    }
    
    private(set) var state: SessionState = .idle
    private var activeTimers: [UUID: TimerState] = [:]
    
    struct TimerState {
        let spec: TimerSpec
        var startedAt: Date?
        var remainingSeconds: Int
        var isRunning: Bool
    }
    
    // MARK: - Session Control
    
    func startSession(recipe: Recipe) {
        state = .cooking(recipeId: recipe.id, currentStep: 0)
    }
    
    func pauseSession() {
        guard case .cooking(let recipeId, let step) = state else { return }
        state = .paused(recipeId: recipeId, currentStep: step)
        
        // Pause all timers
        for (id, _) in activeTimers {
            pauseTimer(id: id)
        }
    }
    
    func resumeSession() {
        guard case .paused(let recipeId, let step) = state else { return }
        state = .cooking(recipeId: recipeId, currentStep: step)
    }
    
    func endSession() {
        state = .idle
        activeTimers.removeAll()
    }
    
    // MARK: - Step Navigation
    
    func nextStep() -> Int? {
        guard case .cooking(let recipeId, let step) = state else { return nil }
        let newStep = step + 1
        state = .cooking(recipeId: recipeId, currentStep: newStep)
        return newStep
    }
    
    func previousStep() -> Int? {
        guard case .cooking(let recipeId, let step) = state, step > 0 else { return nil }
        let newStep = step - 1
        state = .cooking(recipeId: recipeId, currentStep: newStep)
        return newStep
    }
    
    func getCurrentStep() -> Int? {
        switch state {
        case .cooking(_, let step), .paused(_, let step):
            return step
        case .idle:
            return nil
        }
    }
    
    // MARK: - Timer Management
    
    func startTimer(spec: TimerSpec) {
        activeTimers[spec.id] = TimerState(
            spec: spec,
            startedAt: Date(),
            remainingSeconds: spec.seconds,
            isRunning: true
        )
    }
    
    func pauseTimer(id: UUID) {
        guard var timer = activeTimers[id], timer.isRunning else { return }
        
        if let startedAt = timer.startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            timer.remainingSeconds = max(0, timer.remainingSeconds - elapsed)
        }
        timer.isRunning = false
        timer.startedAt = nil
        activeTimers[id] = timer
    }
    
    func resumeTimer(id: UUID) {
        guard var timer = activeTimers[id], !timer.isRunning else { return }
        timer.isRunning = true
        timer.startedAt = Date()
        activeTimers[id] = timer
    }
    
    func stopTimer(id: UUID) {
        activeTimers.removeValue(forKey: id)
    }
    
    func getRemainingTime(id: UUID) -> Int? {
        guard let timer = activeTimers[id] else { return nil }
        
        if timer.isRunning, let startedAt = timer.startedAt {
            let elapsed = Int(Date().timeIntervalSince(startedAt))
            return max(0, timer.remainingSeconds - elapsed)
        }
        
        return timer.remainingSeconds
    }
    
    func getActiveTimers() -> [UUID] {
        Array(activeTimers.keys)
    }
}
