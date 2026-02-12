//
//  UnitParserTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class UnitParserTests: XCTestCase {

    // MARK: - Teaspoon Parsing

    func testParse_Teaspoon_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("tsp"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("t"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("tsps"), .teaspoon)
    }

    func testParse_Teaspoon_FullName() {
        XCTAssertEqual(UnitParser.parse("teaspoon"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("teaspoons"), .teaspoon)
    }

    func testParse_Teaspoon_CommonMisspelling() {
        XCTAssertEqual(UnitParser.parse("teapoon"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("teapoons"), .teaspoon)
    }

    func testParse_Teaspoon_CaseInsensitive() {
        XCTAssertEqual(UnitParser.parse("TSP"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("Teaspoon"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("TEASPOONS"), .teaspoon)
    }

    // MARK: - Tablespoon Parsing

    func testParse_Tablespoon_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("tbsp"), .tablespoon)
        XCTAssertEqual(UnitParser.parse("T"), .tablespoon)
        XCTAssertEqual(UnitParser.parse("tbsps"), .tablespoon)
    }

    func testParse_Tablespoon_FullName() {
        XCTAssertEqual(UnitParser.parse("tablespoon"), .tablespoon)
        XCTAssertEqual(UnitParser.parse("tablespoons"), .tablespoon)
    }

    // MARK: - Cup Parsing

    func testParse_Cup_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("c"), .cup)
        XCTAssertEqual(UnitParser.parse("cup"), .cup)
        XCTAssertEqual(UnitParser.parse("cups"), .cup)
    }

    func testParse_Cup_CaseInsensitive() {
        XCTAssertEqual(UnitParser.parse("CUP"), .cup)
        XCTAssertEqual(UnitParser.parse("Cups"), .cup)
    }

    // MARK: - Ounce Parsing

    func testParse_Ounce_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("oz"), .ounce)
    }

    func testParse_Ounce_FullName() {
        XCTAssertEqual(UnitParser.parse("ounce"), .ounce)
        XCTAssertEqual(UnitParser.parse("ounces"), .ounce)
    }

    // MARK: - Fluid Ounce Parsing

    func testParse_FluidOunce_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("fl oz"), .fluidOunce)
        XCTAssertEqual(UnitParser.parse("floz"), .fluidOunce)
    }

    func testParse_FluidOunce_FullName() {
        XCTAssertEqual(UnitParser.parse("fluid ounce"), .fluidOunce)
        XCTAssertEqual(UnitParser.parse("fluid ounces"), .fluidOunce)
    }

    // MARK: - Pound Parsing

    func testParse_Pound_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("lb"), .pound)
        XCTAssertEqual(UnitParser.parse("lbs"), .pound)
    }

    func testParse_Pound_FullName() {
        XCTAssertEqual(UnitParser.parse("pound"), .pound)
        XCTAssertEqual(UnitParser.parse("pounds"), .pound)
    }

    // MARK: - Gram Parsing

    func testParse_Gram_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("g"), .gram)
    }

    func testParse_Gram_FullName() {
        XCTAssertEqual(UnitParser.parse("gram"), .gram)
        XCTAssertEqual(UnitParser.parse("grams"), .gram)
    }

    // MARK: - Kilogram Parsing

    func testParse_Kilogram_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("kg"), .kilogram)
        XCTAssertEqual(UnitParser.parse("kgs"), .kilogram)
    }

    func testParse_Kilogram_FullName() {
        XCTAssertEqual(UnitParser.parse("kilogram"), .kilogram)
        XCTAssertEqual(UnitParser.parse("kilograms"), .kilogram)
    }

    // MARK: - Milliliter Parsing

    func testParse_Milliliter_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("ml"), .milliliter)
        XCTAssertEqual(UnitParser.parse("mls"), .milliliter)
    }

    func testParse_Milliliter_FullName() {
        XCTAssertEqual(UnitParser.parse("milliliter"), .milliliter)
        XCTAssertEqual(UnitParser.parse("milliliters"), .milliliter)
    }

    // MARK: - Liter Parsing

    func testParse_Liter_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("l"), .liter)
    }

    func testParse_Liter_FullName() {
        XCTAssertEqual(UnitParser.parse("liter"), .liter)
        XCTAssertEqual(UnitParser.parse("liters"), .liter)
    }

    // MARK: - Pint Parsing

    func testParse_Pint_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("pt"), .pint)
        XCTAssertEqual(UnitParser.parse("pts"), .pint)
    }

    func testParse_Pint_FullName() {
        XCTAssertEqual(UnitParser.parse("pint"), .pint)
        XCTAssertEqual(UnitParser.parse("pints"), .pint)
    }

    // MARK: - Quart Parsing

    func testParse_Quart_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("qt"), .quart)
        XCTAssertEqual(UnitParser.parse("qts"), .quart)
    }

    func testParse_Quart_FullName() {
        XCTAssertEqual(UnitParser.parse("quart"), .quart)
        XCTAssertEqual(UnitParser.parse("quarts"), .quart)
    }

    // MARK: - Gallon Parsing

    func testParse_Gallon_Abbreviation() {
        XCTAssertEqual(UnitParser.parse("gal"), .gallon)
        XCTAssertEqual(UnitParser.parse("gals"), .gallon)
    }

    func testParse_Gallon_FullName() {
        XCTAssertEqual(UnitParser.parse("gallon"), .gallon)
        XCTAssertEqual(UnitParser.parse("gallons"), .gallon)
    }

    // MARK: - Whitespace Handling

    func testParse_WithLeadingWhitespace() {
        XCTAssertEqual(UnitParser.parse("  tsp"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("  cup"), .cup)
    }

    func testParse_WithTrailingWhitespace() {
        XCTAssertEqual(UnitParser.parse("tsp  "), .teaspoon)
        XCTAssertEqual(UnitParser.parse("cup  "), .cup)
    }

    func testParse_WithSurroundingWhitespace() {
        XCTAssertEqual(UnitParser.parse("  tsp  "), .teaspoon)
        XCTAssertEqual(UnitParser.parse("  tablespoon  "), .tablespoon)
    }

    // MARK: - Punctuation Handling

    func testParse_DottedAbbreviations() {
        XCTAssertEqual(UnitParser.parse("c."), .cup)
        XCTAssertEqual(UnitParser.parse("tsp."), .teaspoon)
        XCTAssertEqual(UnitParser.parse("tbsp."), .tablespoon)
        XCTAssertEqual(UnitParser.parse("lb."), .pound)
    }

    func testParse_OCRNoisyAbbreviations() {
        XCTAssertEqual(UnitParser.parse("tb5p"), .tablespoon)
        XCTAssertEqual(UnitParser.parse("t5p"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("1b"), .pound)
    }

    // MARK: - Invalid Input

    func testParse_UnknownUnit() {
        XCTAssertNil(UnitParser.parse("unknown"))
        XCTAssertNil(UnitParser.parse("xyz"))
        XCTAssertNil(UnitParser.parse("banana"))
    }

    func testParse_EmptyString() {
        XCTAssertNil(UnitParser.parse(""))
    }

    func testParse_WhitespaceOnly() {
        XCTAssertNil(UnitParser.parse("   "))
    }

    // MARK: - Real-World Examples

    func testParse_CommonRecipeUnits() {
        // Most common units in recipes
        XCTAssertEqual(UnitParser.parse("cup"), .cup)
        XCTAssertEqual(UnitParser.parse("tsp"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("tbsp"), .tablespoon)
        XCTAssertEqual(UnitParser.parse("oz"), .ounce)
        XCTAssertEqual(UnitParser.parse("lb"), .pound)
        XCTAssertEqual(UnitParser.parse("g"), .gram)
    }

    func testParse_MixedCaseInput() {
        XCTAssertEqual(UnitParser.parse("CuP"), .cup)
        XCTAssertEqual(UnitParser.parse("TsP"), .teaspoon)
        XCTAssertEqual(UnitParser.parse("TBsp"), .tablespoon)
    }
}
