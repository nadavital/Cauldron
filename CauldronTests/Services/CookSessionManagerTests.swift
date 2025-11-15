//
//  CookSessionManagerTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
@testable import Cauldron

final class CookSessionManagerTests: XCTestCase {

    var manager: CookSessionManager!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        manager = CookSessionManager()
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Session Control Tests

    func testStartSession_SetsStateToActive() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [
                CookStep(index: 0, text: "Step 1"),
                CookStep(index: 1, text: "Step 2")
            ],
            yields: "2 servings"
        )

        // When
        await manager.startSession(recipe: recipe)

        // Then
        let state = await manager.state
        if case .cooking(let recipeId, let currentStep) = state {
            XCTAssertEqual(recipeId, recipe.id)
            XCTAssertEqual(currentStep, 0)
        } else {
            XCTFail("Expected cooking state")
        }
    }

    func testPauseSession_TransitionsToPaused() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        // When
        await manager.pauseSession()

        // Then
        let state = await manager.state
        if case .paused(let recipeId, let currentStep) = state {
            XCTAssertEqual(recipeId, recipe.id)
            XCTAssertEqual(currentStep, 0)
        } else {
            XCTFail("Expected paused state")
        }
    }

    func testResumeSession_TransitionsBackToCooking() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)
        await manager.pauseSession()

        // When
        await manager.resumeSession()

        // Then
        let state = await manager.state
        if case .cooking(let recipeId, let currentStep) = state {
            XCTAssertEqual(recipeId, recipe.id)
            XCTAssertEqual(currentStep, 0)
        } else {
            XCTFail("Expected cooking state")
        }
    }

    func testEndSession_ResetsToIdle() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        // When
        await manager.endSession()

        // Then
        let state = await manager.state
        if case .idle = state {
            // Success
        } else {
            XCTFail("Expected idle state")
        }
    }

    // MARK: - Step Navigation Tests

    func testNextStep_IncrementsCurrentStep() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [
                CookStep(index: 0, text: "Step 1"),
                CookStep(index: 1, text: "Step 2")
            ],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        // When
        let newStep = await manager.nextStep()

        // Then
        XCTAssertEqual(newStep, 1)
        let currentStep = await manager.getCurrentStep()
        XCTAssertEqual(currentStep, 1)
    }

    func testPreviousStep_DecrementsCurrentStep() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [
                CookStep(index: 0, text: "Step 1"),
                CookStep(index: 1, text: "Step 2")
            ],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)
        _ = await manager.nextStep() // Move to step 1

        // When
        let newStep = await manager.previousStep()

        // Then
        XCTAssertEqual(newStep, 0)
        let currentStep = await manager.getCurrentStep()
        XCTAssertEqual(currentStep, 0)
    }

    func testPreviousStep_AtFirstStep_ReturnsNil() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        // When
        let newStep = await manager.previousStep()

        // Then
        XCTAssertNil(newStep)
        let currentStep = await manager.getCurrentStep()
        XCTAssertEqual(currentStep, 0) // Should stay at 0
    }

    func testGetCurrentStep_WhenIdle_ReturnsNil() async {
        // When
        let currentStep = await manager.getCurrentStep()

        // Then
        XCTAssertNil(currentStep)
    }

    func testGetCurrentStep_WhenPaused_ReturnsStep() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)
        await manager.pauseSession()

        // When
        let currentStep = await manager.getCurrentStep()

        // Then
        XCTAssertEqual(currentStep, 0)
    }

    // MARK: - Timer Management Tests

    func testStartTimer_CreatesActiveTimer() async {
        // Given
        let timerSpec = TimerSpec(seconds: 300, label: "Cook pasta")

        // When
        await manager.startTimer(spec: timerSpec)

        // Then
        let activeTimers = await manager.getActiveTimers()
        XCTAssertEqual(activeTimers.count, 1)
        XCTAssertTrue(activeTimers.contains(timerSpec.id))
    }

    func testStopTimer_RemovesTimer() async {
        // Given
        let timerSpec = TimerSpec(seconds: 300, label: "Cook pasta")
        await manager.startTimer(spec: timerSpec)

        // When
        await manager.stopTimer(id: timerSpec.id)

        // Then
        let activeTimers = await manager.getActiveTimers()
        XCTAssertEqual(activeTimers.count, 0)
    }

    func testPauseTimer_StopsTimeElapsing() async {
        // Given
        let timerSpec = TimerSpec(seconds: 10, label: "Quick timer")
        await manager.startTimer(spec: timerSpec)

        // Wait 1 second
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // When
        await manager.pauseTimer(id: timerSpec.id)

        // Get remaining time immediately after pause
        let remainingAfterPause = await manager.getRemainingTime(id: timerSpec.id)

        // Wait another second
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Then - time should not have decreased further
        let remainingAfterWait = await manager.getRemainingTime(id: timerSpec.id)
        XCTAssertEqual(remainingAfterPause, remainingAfterWait)
    }

    func testResumeTimer_ResumesTimeElapsing() async {
        // Given
        let timerSpec = TimerSpec(seconds: 10, label: "Quick timer")
        await manager.startTimer(spec: timerSpec)
        await manager.pauseTimer(id: timerSpec.id)

        // When
        await manager.resumeTimer(id: timerSpec.id)

        // Wait 1 second
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Then - time should have decreased
        let remainingTime = await manager.getRemainingTime(id: timerSpec.id)
        XCTAssertNotNil(remainingTime)
        if let remainingTime = remainingTime {
            XCTAssertLessThan(remainingTime, 10)
        }
    }

    func testGetRemainingTime_NonExistentTimer_ReturnsNil() async {
        // When
        let remainingTime = await manager.getRemainingTime(id: UUID())

        // Then
        XCTAssertNil(remainingTime)
    }

    func testEndSession_ClearsAllTimers() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        let timer1 = TimerSpec(seconds: 300, label: "Timer 1")
        let timer2 = TimerSpec(seconds: 600, label: "Timer 2")
        await manager.startTimer(spec: timer1)
        await manager.startTimer(spec: timer2)

        // When
        await manager.endSession()

        // Then
        let activeTimers = await manager.getActiveTimers()
        XCTAssertEqual(activeTimers.count, 0)
    }

    func testMultipleTimers_CanRunConcurrently() async {
        // Given
        let timer1 = TimerSpec(seconds: 300, label: "Timer 1")
        let timer2 = TimerSpec(seconds: 600, label: "Timer 2")
        let timer3 = TimerSpec(seconds: 900, label: "Timer 3")

        // When
        await manager.startTimer(spec: timer1)
        await manager.startTimer(spec: timer2)
        await manager.startTimer(spec: timer3)

        // Then
        let activeTimers = await manager.getActiveTimers()
        XCTAssertEqual(activeTimers.count, 3)
        XCTAssertTrue(activeTimers.contains(timer1.id))
        XCTAssertTrue(activeTimers.contains(timer2.id))
        XCTAssertTrue(activeTimers.contains(timer3.id))
    }

    func testPauseSession_PausesAllActiveTimers() async {
        // Given
        let recipe = await Recipe(
            title: "Test Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Step 1")],
            yields: "2 servings"
        )
        await manager.startSession(recipe: recipe)

        let timer1 = TimerSpec(seconds: 10, label: "Timer 1")
        let timer2 = TimerSpec(seconds: 20, label: "Timer 2")
        await manager.startTimer(spec: timer1)
        await manager.startTimer(spec: timer2)

        // Wait 1 second
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // When
        await manager.pauseSession()

        // Get remaining times immediately after pause
        let remaining1 = await manager.getRemainingTime(id: timer1.id)
        let remaining2 = await manager.getRemainingTime(id: timer2.id)

        // Wait another second
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // Then - both timers should have stopped counting
        let remaining1After = await manager.getRemainingTime(id: timer1.id)
        let remaining2After = await manager.getRemainingTime(id: timer2.id)

        XCTAssertEqual(remaining1, remaining1After)
        XCTAssertEqual(remaining2, remaining2After)
    }
}
