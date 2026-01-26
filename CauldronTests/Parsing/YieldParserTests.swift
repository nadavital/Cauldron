//
//  YieldParserTests.swift
//  CauldronTests
//
//  Tests for YieldParser utility
//

import XCTest
@testable import Cauldron

final class YieldParserTests: XCTestCase {

    // MARK: - Basic Pattern Tests

    func testExtractYield_ServesPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Serves 4"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "Serves: 4"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "serves 6"), "6 servings")
    }

    func testExtractYield_ServingsPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Servings: 4"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "4 servings"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "8 Servings"), "8 servings")
    }

    func testExtractYield_MakesPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Makes 12 cookies"), "12 cookies")
        XCTAssertEqual(YieldParser.extractYield(from: "Makes about 24 muffins"), "24 muffins")
        XCTAssertEqual(YieldParser.extractYield(from: "makes 2 loaves"), "2 loaves")
    }

    func testExtractYield_YieldPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Yields 6"), "6 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "Yield: 1 loaf"), "1 loaf")
        XCTAssertEqual(YieldParser.extractYield(from: "yield: 8 servings"), "8 servings")
    }

    func testExtractYield_ForPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Recipe for 8"), "8 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "For 4 people"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "for 6 persons"), "6 servings")
    }

    func testExtractYield_PortionsPattern() {
        XCTAssertEqual(YieldParser.extractYield(from: "Portions: 6"), "6 portions")
        XCTAssertEqual(YieldParser.extractYield(from: "4 portions"), "4 portions")
    }

    // MARK: - Range Tests

    func testExtractYield_RangeWithDash() {
        XCTAssertEqual(YieldParser.extractYield(from: "Serves 4-6"), "4-6 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "Serves: 8-10"), "8-10 servings")
    }

    func testExtractYield_RangeWithTo() {
        XCTAssertEqual(YieldParser.extractYield(from: "Serves 4 to 6"), "4-6 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "Makes 10 to 12 cookies"), "10-12 cookies")
    }

    // MARK: - Unit Normalization Tests

    func testExtractYield_NormalizesUnits() {
        XCTAssertEqual(YieldParser.extractYield(from: "Makes 1 dozen"), "1 dozen")
        XCTAssertEqual(YieldParser.extractYield(from: "Makes 2 batches"), "2 batches")
        XCTAssertEqual(YieldParser.extractYield(from: "Yields 3 cups"), "3 cups")
    }

    // MARK: - From Lines Tests

    func testExtractYieldFromLines_FindsYieldLine() {
        let lines = [
            "Chocolate Chip Cookies",
            "Serves 24",
            "Ingredients:",
            "2 cups flour"
        ]
        XCTAssertEqual(YieldParser.extractYieldFromLines(lines), "24 servings")
    }

    func testExtractYieldFromLines_PrioritizesYieldKeywords() {
        let lines = [
            "Recipe Title",
            "Some description with 4 people mentioned",
            "Serves 8",  // This should be found first due to keyword
            "More content"
        ]
        XCTAssertEqual(YieldParser.extractYieldFromLines(lines), "8 servings")
    }

    func testExtractYieldFromLines_ReturnsNilWhenNoYield() {
        let lines = [
            "Simple Recipe",
            "Ingredients:",
            "Flour",
            "Sugar"
        ]
        XCTAssertNil(YieldParser.extractYieldFromLines(lines))
    }

    // MARK: - Edge Cases

    func testExtractYield_ReturnsNilForInvalidInput() {
        XCTAssertNil(YieldParser.extractYield(from: "No yield here"))
        XCTAssertNil(YieldParser.extractYield(from: ""))
        XCTAssertNil(YieldParser.extractYield(from: "Just some random text"))
    }

    func testExtractYield_HandlesExtraWhitespace() {
        XCTAssertEqual(YieldParser.extractYield(from: "Serves   4"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "  Serves 4  "), "4 servings")
    }

    func testExtractYield_CaseInsensitive() {
        XCTAssertEqual(YieldParser.extractYield(from: "SERVES 4"), "4 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "MAKES 12 COOKIES"), "12 cookies")
    }

    // MARK: - Real-World Examples

    func testExtractYield_RealWorldExamples() {
        // From recipe websites
        XCTAssertEqual(YieldParser.extractYield(from: "Yield: 1 (9-inch) pie"), "1 servings")
        XCTAssertEqual(YieldParser.extractYield(from: "Makes 24 standard cupcakes"), "24 cupcakes")
        XCTAssertEqual(YieldParser.extractYield(from: "Serves 4-6 as a main course"), "4-6 servings")
    }
}
