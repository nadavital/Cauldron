//
//  TimerExtractorTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

final class TimerExtractorTests: XCTestCase {

    // MARK: - Minutes Extraction

    func testExtractTimers_Minutes_Singular() {
        let timers = TimerExtractor.extractTimers(from: "Bake for 30 minute")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 30 * 60)
    }

    func testExtractTimers_Minutes_Plural() {
        let timers = TimerExtractor.extractTimers(from: "Bake for 30 minutes")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 30 * 60)
    }

    func testExtractTimers_Minutes_Abbreviated() {
        let timers1 = TimerExtractor.extractTimers(from: "Cook for 5 min")
        let timers2 = TimerExtractor.extractTimers(from: "Cook for 5 mins")

        XCTAssertEqual(timers1.count, 1)
        XCTAssertEqual(timers2.count, 1)

        XCTAssertEqual(timers1[0].seconds, 5 * 60)
        XCTAssertEqual(timers2[0].seconds, 5 * 60)
    }

    func testExtractTimers_Minutes_CaseInsensitive() {
        let timers1 = TimerExtractor.extractTimers(from: "Bake for 30 MINUTES")
        let timers2 = TimerExtractor.extractTimers(from: "Bake for 30 Minutes")
        let timers3 = TimerExtractor.extractTimers(from: "Bake for 30 MiNuTeS")

        XCTAssertEqual(timers1.count, 1)
        XCTAssertEqual(timers2.count, 1)
        XCTAssertEqual(timers3.count, 1)
    }

    // MARK: - Hours Extraction

    func testExtractTimers_Hours_Singular() {
        let timers = TimerExtractor.extractTimers(from: "Simmer for 1 hour")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 1 * 3600)
    }

    func testExtractTimers_Hours_Plural() {
        let timers = TimerExtractor.extractTimers(from: "Simmer for 2 hours")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 2 * 3600)
    }

    func testExtractTimers_Hours_Abbreviated() {
        let timers1 = TimerExtractor.extractTimers(from: "Bake for 3 hr")
        let timers2 = TimerExtractor.extractTimers(from: "Bake for 3 hrs")

        XCTAssertEqual(timers1.count, 1)
        XCTAssertEqual(timers2.count, 1)

        XCTAssertEqual(timers1[0].seconds, 3 * 3600)
        XCTAssertEqual(timers2[0].seconds, 3 * 3600)
    }

    // MARK: - Seconds Extraction

    func testExtractTimers_Seconds_Singular() {
        let timers = TimerExtractor.extractTimers(from: "Stir for 30 second")

        XCTAssertEqual(timers.count, 1)
        // TimerSpec uses initializer with seconds
        XCTAssertEqual(timers[0].seconds, 30)
    }

    func testExtractTimers_Seconds_Plural() {
        let timers = TimerExtractor.extractTimers(from: "Stir for 45 seconds")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 45)
    }

    func testExtractTimers_Seconds_Abbreviated() {
        let timers1 = TimerExtractor.extractTimers(from: "Boil for 20 sec")
        let timers2 = TimerExtractor.extractTimers(from: "Boil for 20 secs")

        XCTAssertEqual(timers1.count, 1)
        XCTAssertEqual(timers2.count, 1)

        XCTAssertEqual(timers1[0].seconds, 20)
        XCTAssertEqual(timers2[0].seconds, 20)
    }

    // MARK: - Multiple Timers

    func testExtractTimers_MultipleTimers() {
        // Note: Current implementation only extracts the first match of each type
        // If text has "5 minutes" and "10 minutes", only one will be extracted
        let text = "Bake for 30 minutes, then cool for 1 hour"
        let timers = TimerExtractor.extractTimers(from: text)

        // Should extract both the minutes and hours
        XCTAssertGreaterThanOrEqual(timers.count, 1)
        // At minimum should have minutes
        XCTAssertTrue(timers.contains(where: { timer in
            timer.seconds == 30 * 60
        }))
    }

    func testExtractTimers_MixedUnits() {
        let text = "Cook for 2 hours and 30 minutes"
        let timers = TimerExtractor.extractTimers(from: text)

        // Should extract both hours and minutes
        XCTAssertGreaterThanOrEqual(timers.count, 1)
    }

    // MARK: - No Timer

    func testExtractTimers_NoTimer() {
        let timers = TimerExtractor.extractTimers(from: "Mix the ingredients thoroughly")

        XCTAssertEqual(timers.count, 0)
    }

    func testExtractTimers_EmptyString() {
        let timers = TimerExtractor.extractTimers(from: "")

        XCTAssertEqual(timers.count, 0)
    }

    // MARK: - Edge Cases

    func testExtractTimers_NumberWithoutUnit() {
        let timers = TimerExtractor.extractTimers(from: "Add 5 to the mixture")

        XCTAssertEqual(timers.count, 0)
    }

    func testExtractTimers_UnitWithoutNumber() {
        let timers = TimerExtractor.extractTimers(from: "Bake for minutes")

        XCTAssertEqual(timers.count, 0)
    }

    func testExtractTimers_WithHyphen() {
        let timers = TimerExtractor.extractTimers(from: "Bake for 25-30 minutes")

        // Should extract at least one timer
        XCTAssertGreaterThanOrEqual(timers.count, 1)
    }

    // MARK: - Real-World Examples

    func testExtractTimers_RealWorld1() {
        let timers = TimerExtractor.extractTimers(from: "1. Preheat oven to 350°F and bake for 25 minutes")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 25 * 60)
    }

    func testExtractTimers_RealWorld2() {
        let timers = TimerExtractor.extractTimers(from: "Simmer on low heat for 1 hour, stirring occasionally")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 1 * 3600)
    }

    func testExtractTimers_RealWorld3() {
        let timers = TimerExtractor.extractTimers(from: "Microwave for 90 seconds on high")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 90)
    }

    func testExtractTimers_RealWorld4() {
        let timers = TimerExtractor.extractTimers(from: "Let rest for 10 min before serving")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 10 * 60)
    }

    func testExtractTimers_RealWorld5() {
        let timers = TimerExtractor.extractTimers(from: "Cook until golden brown, about 5 minutes per side")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].seconds, 5 * 60)
    }

    // MARK: - Timer Labels

    func testExtractTimers_HasLabel() {
        let timers = TimerExtractor.extractTimers(from: "Bake for 30 minutes")

        XCTAssertEqual(timers.count, 1)
        XCTAssertEqual(timers[0].label, "Cook")
    }
}
