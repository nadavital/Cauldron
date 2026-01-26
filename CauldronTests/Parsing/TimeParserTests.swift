//
//  TimeParserTests.swift
//  CauldronTests
//
//  Tests for TimeParser utility
//

import XCTest
@testable import Cauldron

final class TimeParserTests: XCTestCase {

    // MARK: - Total Time Extraction

    func testExtractTotalMinutes_TotalTimePattern() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Total time: 30 min"]), 30)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Total Time: 45 minutes"]), 45)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Total: 1 hour"]), 60)
    }

    func testExtractTotalMinutes_ReadyInPattern() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Ready in 45 minutes"]), 45)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Ready in: 1 hour"]), 60)
    }

    func testExtractTotalMinutes_CookTimePattern() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Cook time: 30 min"]), 30)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Cooking time: 45 minutes"]), 45)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Bake time: 25 min"]), 25)
    }

    func testExtractTotalMinutes_PrepTimePattern() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Prep time: 15 min"]), 15)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Preparation: 20 minutes"]), 20)
    }

    // MARK: - Combined Times

    func testExtractTotalMinutes_CombinesPrepAndCook() {
        let lines = [
            "Prep time: 15 min",
            "Cook time: 30 min"
        ]
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: lines), 45)
    }

    func testExtractTotalMinutes_PrefersTotalOverCombined() {
        let lines = [
            "Prep time: 15 min",
            "Cook time: 30 min",
            "Total time: 50 min"  // Uses this instead of 45
        ]
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: lines), 50)
    }

    // MARK: - Time String Parsing

    func testParseTimeString_Minutes() {
        XCTAssertEqual(TimeParser.parseTimeString("30 min"), 30)
        XCTAssertEqual(TimeParser.parseTimeString("45 minutes"), 45)
        XCTAssertEqual(TimeParser.parseTimeString("15 mins"), 15)
        XCTAssertEqual(TimeParser.parseTimeString("20m"), 20)
    }

    func testParseTimeString_Hours() {
        XCTAssertEqual(TimeParser.parseTimeString("1 hour"), 60)
        XCTAssertEqual(TimeParser.parseTimeString("2 hours"), 120)
        XCTAssertEqual(TimeParser.parseTimeString("1 hr"), 60)
        XCTAssertEqual(TimeParser.parseTimeString("3h"), 180)
    }

    func testParseTimeString_HoursAndMinutes() {
        XCTAssertEqual(TimeParser.parseTimeString("1 hour 30 minutes"), 90)
        XCTAssertEqual(TimeParser.parseTimeString("1h 30m"), 90)
        XCTAssertEqual(TimeParser.parseTimeString("2 hours and 15 minutes"), 135)
        XCTAssertEqual(TimeParser.parseTimeString("1 hr 45 min"), 105)
    }

    func testParseTimeString_ColonFormat() {
        XCTAssertEqual(TimeParser.parseTimeString("1:30"), 90)
        XCTAssertEqual(TimeParser.parseTimeString("2:00"), 120)
        XCTAssertEqual(TimeParser.parseTimeString("0:45"), 45)
    }

    func testParseTimeString_StandaloneNumber() {
        XCTAssertEqual(TimeParser.parseTimeString("30"), 30)
        XCTAssertEqual(TimeParser.parseTimeString("45"), 45)
    }

    // MARK: - Special Cases

    func testExtractTotalMinutes_OvernightPattern() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Let rise overnight (8 hours)"]), 8 * 60)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Chill overnight"]), 8 * 60) // Default
    }

    // MARK: - Edge Cases

    func testExtractTotalMinutes_ReturnsNilForNoTime() {
        XCTAssertNil(TimeParser.extractTotalMinutes(from: ["No time info here"]))
        XCTAssertNil(TimeParser.extractTotalMinutes(from: []))
    }

    func testParseTimeString_ReturnsNilForInvalidInput() {
        XCTAssertNil(TimeParser.parseTimeString("no time"))
        XCTAssertNil(TimeParser.parseTimeString(""))
        XCTAssertNil(TimeParser.parseTimeString("abc"))
    }

    func testExtractTotalMinutes_CaseInsensitive() {
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["COOK TIME: 30 MIN"]), 30)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Cook Time: 30 Minutes"]), 30)
    }

    // MARK: - Real-World Examples

    func testExtractTotalMinutes_RealWorldExamples() {
        // From recipe websites
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Prep: 15 | Cook: 45 | Total: 1 hr"]), 60)
        XCTAssertEqual(TimeParser.extractTotalMinutes(from: ["Time: 1 hr 30 min"]), 90)
    }

    // MARK: - All Times Extraction

    func testExtractAllTimes_SeparatesPrepAndCook() {
        let lines = [
            "Prep time: 15 min",
            "Cook time: 30 min"
        ]
        let result = TimeParser.extractAllTimes(from: lines)

        XCTAssertEqual(result.prepMinutes, 15)
        XCTAssertEqual(result.cookMinutes, 30)
        XCTAssertEqual(result.bestTotalMinutes, 45)
    }

    func testExtractAllTimes_IncludesTotalTime() {
        let lines = [
            "Prep time: 15 min",
            "Cook time: 30 min",
            "Total time: 50 min"
        ]
        let result = TimeParser.extractAllTimes(from: lines)

        XCTAssertEqual(result.prepMinutes, 15)
        XCTAssertEqual(result.cookMinutes, 30)
        XCTAssertEqual(result.totalMinutes, 50)
        XCTAssertEqual(result.bestTotalMinutes, 50) // Prefers explicit total
    }
}
