//
//  QuantityTextParserTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class QuantityTextParserTests: XCTestCase {

    func testEmptyAndWhitespaceReturnNil() {
        XCTAssertNil(QuantityTextParser.parse(""))
        XCTAssertNil(QuantityTextParser.parse("   "))
    }

    func testWholeNumber() {
        let result = QuantityTextParser.parse("2")
        XCTAssertEqual(result?.value ?? .nan, 2, accuracy: 0.001)
        XCTAssertNil(result?.upperValue)
    }

    func testDecimal() {
        let result = QuantityTextParser.parse("1.5")
        XCTAssertEqual(result?.value ?? .nan, 1.5, accuracy: 0.001)
        XCTAssertNil(result?.upperValue)
    }

    func testSimpleFraction() {
        let result = QuantityTextParser.parse("1/2")
        XCTAssertEqual(result?.value ?? .nan, 0.5, accuracy: 0.001)
    }

    func testMixedNumber() {
        let result = QuantityTextParser.parse("1 1/2")
        XCTAssertEqual(result?.value ?? .nan, 1.5, accuracy: 0.001)
    }

    func testRange() {
        let result = QuantityTextParser.parse("1-2")
        XCTAssertEqual(result?.value ?? .nan, 1, accuracy: 0.001)
        XCTAssertEqual(result?.upperValue ?? 0, 2, accuracy: 0.001)
    }

    func testRangeWithSpaces() {
        let result = QuantityTextParser.parse("1 - 2")
        XCTAssertEqual(result?.value ?? .nan, 1, accuracy: 0.001)
        XCTAssertEqual(result?.upperValue ?? 0, 2, accuracy: 0.001)
    }

    func testRangeOfFractions() {
        let result = QuantityTextParser.parse("1/2-3/4")
        XCTAssertEqual(result?.value ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(result?.upperValue ?? 0, 0.75, accuracy: 0.001)
    }

    func testDivideByZeroFractionIsNotANumber() {
        // "1/0" is not a valid quantity → nil
        XCTAssertNil(QuantityTextParser.parse("1/0"))
    }

    func testGarbageReturnsNil() {
        XCTAssertNil(QuantityTextParser.parse("abc"))
    }
}
