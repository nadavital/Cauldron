//
//  QuantityValueParserTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class QuantityValueParserTests: XCTestCase {

    // MARK: - Decimal Parsing

    func testParse_SimpleDecimal() {
        XCTAssertEqual(QuantityValueParser.parse("2.5"), 2.5)
        XCTAssertEqual(QuantityValueParser.parse("1.0"), 1.0)
        XCTAssertEqual(QuantityValueParser.parse("0.5"), 0.5)
    }

    func testParse_WholeNumber() {
        XCTAssertEqual(QuantityValueParser.parse("1"), 1.0)
        XCTAssertEqual(QuantityValueParser.parse("2"), 2.0)
        XCTAssertEqual(QuantityValueParser.parse("10"), 10.0)
    }

    // MARK: - Fraction Parsing

    func testParse_SimpleFraction() {
        XCTAssertEqual(QuantityValueParser.parse("1/2"), 0.5)
        XCTAssertEqual(QuantityValueParser.parse("1/4"), 0.25)
        XCTAssertEqual(QuantityValueParser.parse("3/4"), 0.75)
        XCTAssertEqual(QuantityValueParser.parse("1/3")!, 0.333, accuracy: 0.001)
        XCTAssertEqual(QuantityValueParser.parse("2/3")!, 0.667, accuracy: 0.001)
    }

    func testParse_FractionWithSpaces() {
        XCTAssertEqual(QuantityValueParser.parse(" 1/2 "), 0.5)
        XCTAssertEqual(QuantityValueParser.parse("  3/4  "), 0.75)
    }

    // MARK: - Mixed Number Parsing

    func testParse_MixedNumber() {
        XCTAssertEqual(QuantityValueParser.parse("1 1/2"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("2 1/4"), 2.25)
        XCTAssertEqual(QuantityValueParser.parse("3 3/4"), 3.75)
    }

    func testParse_MixedNumberWithMultipleSpaces() {
        XCTAssertEqual(QuantityValueParser.parse("1  1/2"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("2   1/4"), 2.25)
    }

    // MARK: - Unicode Fraction Parsing

    func testParse_UnicodeFractionHalf() {
        XCTAssertEqual(QuantityValueParser.parse("½"), 0.5)
    }

    func testParse_UnicodeFractionQuarter() {
        XCTAssertEqual(QuantityValueParser.parse("¼"), 0.25)
        XCTAssertEqual(QuantityValueParser.parse("¾"), 0.75)
    }

    func testParse_UnicodeFractionThird() {
        XCTAssertEqual(QuantityValueParser.parse("⅓")!, 0.333, accuracy: 0.001)
        XCTAssertEqual(QuantityValueParser.parse("⅔")!, 0.667, accuracy: 0.001)
    }

    func testParse_UnicodeFractionEighth() {
        XCTAssertEqual(QuantityValueParser.parse("⅛"), 0.125)
        XCTAssertEqual(QuantityValueParser.parse("⅜"), 0.375)
        XCTAssertEqual(QuantityValueParser.parse("⅝"), 0.625)
        XCTAssertEqual(QuantityValueParser.parse("⅞"), 0.875)
    }

    func testParse_MixedNumberWithUnicodeFraction() {
        // "1 ½" (with space) gets converted to "1 0.5" which should parse as mixed number
        XCTAssertEqual(QuantityValueParser.parse("1 ½"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("2 ¼"), 2.25)
        XCTAssertEqual(QuantityValueParser.parse("3 ¾"), 3.75)
    }

    // MARK: - Range Parsing

    func testParse_Range() {
        // Ranges should return the average
        XCTAssertEqual(QuantityValueParser.parse("1-2"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("2-4"), 3.0)
        XCTAssertEqual(QuantityValueParser.parse("10-20"), 15.0)
    }

    func testParse_RangeWithSpaces() {
        XCTAssertEqual(QuantityValueParser.parse("1 - 2"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("2  -  4"), 3.0)
    }

    func testParse_RangeWithDecimals() {
        XCTAssertEqual(QuantityValueParser.parse("1.5-2.5"), 2.0)
        XCTAssertEqual(QuantityValueParser.parse("0.5-1.5"), 1.0)
    }

    // MARK: - Edge Cases

    func testParse_EmptyString() {
        XCTAssertNil(QuantityValueParser.parse(""))
    }

    func testParse_Whitespace() {
        XCTAssertNil(QuantityValueParser.parse("   "))
    }

    func testParse_InvalidText() {
        XCTAssertNil(QuantityValueParser.parse("abc"))
        XCTAssertNil(QuantityValueParser.parse("not a number"))
    }

    func testParse_DivisionByZero() {
        XCTAssertNil(QuantityValueParser.parse("1/0"))
    }

    func testParse_InvalidFraction() {
        XCTAssertNil(QuantityValueParser.parse("1/"))
        XCTAssertNil(QuantityValueParser.parse("/2"))
        XCTAssertNil(QuantityValueParser.parse("a/b"))
    }

    func testParse_InvalidRange() {
        XCTAssertNil(QuantityValueParser.parse("1-"))
        // Note: "-2" is a valid negative number, so it returns -2.0
        XCTAssertEqual(QuantityValueParser.parse("-2"), -2.0)
        XCTAssertNil(QuantityValueParser.parse("a-b"))
    }

    // MARK: - Real-World Examples

    func testParse_RealWorldIngredients() {
        // Common ingredient quantities from recipes
        XCTAssertEqual(QuantityValueParser.parse("2"), 2.0)
        XCTAssertEqual(QuantityValueParser.parse("1/2"), 0.5)
        XCTAssertEqual(QuantityValueParser.parse("1 1/2"), 1.5)
        XCTAssertEqual(QuantityValueParser.parse("¼"), 0.25)
        XCTAssertEqual(QuantityValueParser.parse("2-3"), 2.5)
        XCTAssertEqual(QuantityValueParser.parse("0.5"), 0.5)
    }

    func testParse_LargeNumbers() {
        XCTAssertEqual(QuantityValueParser.parse("100"), 100.0)
        XCTAssertEqual(QuantityValueParser.parse("500.5"), 500.5)
        XCTAssertEqual(QuantityValueParser.parse("1000"), 1000.0)
    }

    func testParse_SmallDecimals() {
        XCTAssertEqual(QuantityValueParser.parse("0.125"), 0.125)
        XCTAssertEqual(QuantityValueParser.parse("0.333"), 0.333)
        XCTAssertEqual(QuantityValueParser.parse("0.01"), 0.01)
    }
}
