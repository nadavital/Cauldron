//
//  IngredientParserTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class IngredientParserTests: XCTestCase {

    // MARK: - Basic Ingredient Parsing

    func testParseIngredientText_SimpleIngredient() {
        let ingredient = IngredientParser.parseIngredientText("2 cups flour")

        XCTAssertEqual(ingredient.name, "flour")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_WithFraction() {
        let ingredient = IngredientParser.parseIngredientText("1/2 tsp salt")

        XCTAssertEqual(ingredient.name, "salt")
        XCTAssertEqual(ingredient.quantity?.value, 0.5)
        XCTAssertEqual(ingredient.quantity?.unit, .teaspoon)
    }

    func testParseIngredientText_WithMixedNumber() {
        let ingredient = IngredientParser.parseIngredientText("1 1/2 cups sugar")

        XCTAssertEqual(ingredient.name, "sugar")
        XCTAssertEqual(ingredient.quantity?.value, 1.5)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_WithUnicodeFraction() {
        let ingredient = IngredientParser.parseIngredientText("½ cup butter")

        XCTAssertEqual(ingredient.name, "butter")
        XCTAssertEqual(ingredient.quantity?.value, 0.5)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    // MARK: - Without Quantity

    func testParseIngredientText_NoQuantity() {
        let ingredient = IngredientParser.parseIngredientText("Salt to taste")

        XCTAssertEqual(ingredient.name, "Salt to taste")
        XCTAssertNil(ingredient.quantity)
    }

    func testParseIngredientText_JustName() {
        let ingredient = IngredientParser.parseIngredientText("Fresh basil")

        XCTAssertEqual(ingredient.name, "Fresh basil")
        XCTAssertNil(ingredient.quantity)
    }

    // MARK: - Different Units

    func testParseIngredientText_Tablespoon() {
        let ingredient = IngredientParser.parseIngredientText("3 tbsp olive oil")

        XCTAssertEqual(ingredient.name, "olive oil")
        XCTAssertEqual(ingredient.quantity?.value, 3.0)
        XCTAssertEqual(ingredient.quantity?.unit, .tablespoon)
    }

    func testParseIngredientText_Ounce() {
        let ingredient = IngredientParser.parseIngredientText("8 oz cream cheese")

        XCTAssertEqual(ingredient.name, "cream cheese")
        XCTAssertEqual(ingredient.quantity?.value, 8.0)
        XCTAssertEqual(ingredient.quantity?.unit, .ounce)
    }

    func testParseIngredientText_Gram() {
        let ingredient = IngredientParser.parseIngredientText("500 g flour")

        XCTAssertEqual(ingredient.name, "flour")
        XCTAssertEqual(ingredient.quantity?.value, 500.0)
        XCTAssertEqual(ingredient.quantity?.unit, .gram)
    }

    func testParseIngredientText_Pound() {
        let ingredient = IngredientParser.parseIngredientText("2 lbs chicken breast")

        XCTAssertEqual(ingredient.name, "chicken breast")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .pound)
    }

    // MARK: - Complex Ingredient Names

    func testParseIngredientText_ComplexName() {
        let ingredient = IngredientParser.parseIngredientText("2 cups all-purpose flour, sifted")

        XCTAssertEqual(ingredient.name, "all-purpose flour, sifted")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_WithCommas() {
        let ingredient = IngredientParser.parseIngredientText("1 cup onion, finely chopped")

        XCTAssertEqual(ingredient.name, "onion, finely chopped")
        XCTAssertEqual(ingredient.quantity?.value, 1.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_WithParentheses() {
        let ingredient = IngredientParser.parseIngredientText("2 cups rice (uncooked)")

        XCTAssertEqual(ingredient.name, "rice (uncooked)")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    // MARK: - Edge Cases

    func testParseIngredientText_EmptyString() {
        let ingredient = IngredientParser.parseIngredientText("")

        XCTAssertEqual(ingredient.name, "")
        XCTAssertNil(ingredient.quantity)
    }

    func testParseIngredientText_WhitespaceOnly() {
        let ingredient = IngredientParser.parseIngredientText("   ")

        XCTAssertEqual(ingredient.name, "")
        XCTAssertNil(ingredient.quantity)
    }

    func testParseIngredientText_NoSpaceAfterUnit() {
        // Some ingredients might be written as "200g flour"
        let ingredient = IngredientParser.parseIngredientText("200g flour")

        // This should still parse correctly
        XCTAssertEqual(ingredient.name, "flour")
        XCTAssertEqual(ingredient.quantity?.value, 200.0)
        XCTAssertEqual(ingredient.quantity?.unit, .gram)
    }

    func testParseIngredientText_WithLeadingWhitespace() {
        let ingredient = IngredientParser.parseIngredientText("  2 cups flour")

        XCTAssertEqual(ingredient.name, "flour")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_WithTrailingWhitespace() {
        let ingredient = IngredientParser.parseIngredientText("2 cups flour  ")

        XCTAssertEqual(ingredient.name, "flour")
        XCTAssertEqual(ingredient.quantity?.value, 2.0)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    // MARK: - Real-World Examples

    func testParseIngredientText_RealWorld1() {
        let ingredient = IngredientParser.parseIngredientText("2 ¼ cups all-purpose flour")

        XCTAssertEqual(ingredient.name, "all-purpose flour")
        XCTAssertEqual(ingredient.quantity?.value, 2.25)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_RealWorld2() {
        let ingredient = IngredientParser.parseIngredientText("1 tsp vanilla extract")

        XCTAssertEqual(ingredient.name, "vanilla extract")
        XCTAssertEqual(ingredient.quantity?.value, 1.0)
        XCTAssertEqual(ingredient.quantity?.unit, .teaspoon)
    }

    func testParseIngredientText_RealWorld3() {
        let ingredient = IngredientParser.parseIngredientText("3 large eggs, beaten")

        // When unit is not recognized, should default to .whole
        XCTAssertEqual(ingredient.name, "large eggs, beaten")
        XCTAssertEqual(ingredient.quantity?.value, 3.0)
        XCTAssertEqual(ingredient.quantity?.unit, .whole)
    }

    func testParseIngredientText_UnrecognizedTokenAfterQuantity_PreservesNameToken() {
        let ingredient = IngredientParser.parseIngredientText("3 garlic cloves, finely chopped")

        XCTAssertEqual(ingredient.name, "garlic finely chopped")
        XCTAssertEqual(ingredient.quantity?.value, 3.0)
        XCTAssertEqual(ingredient.quantity?.unit, .clove)
    }

    func testParseIngredientText_RealWorld4() {
        let ingredient = IngredientParser.parseIngredientText("¼ cup unsalted butter, melted")

        XCTAssertEqual(ingredient.name, "unsalted butter, melted")
        XCTAssertEqual(ingredient.quantity?.value, 0.25)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_DottedUnitAbbreviation_ParsesUnit() {
        let ingredient = IngredientParser.parseIngredientText("1 tbsp. honey")

        XCTAssertEqual(ingredient.name, "honey")
        XCTAssertEqual(ingredient.quantity?.value, 1.0)
        XCTAssertEqual(ingredient.quantity?.unit, .tablespoon)
    }

    func testParseIngredientText_UnitFollowedByComma_ParsesUnit() {
        let ingredient = IngredientParser.parseIngredientText("3 cloves, garlic finely chopped")

        XCTAssertEqual(ingredient.name, "garlic finely chopped")
        XCTAssertEqual(ingredient.quantity?.value, 3.0)
        XCTAssertEqual(ingredient.quantity?.unit, .clove)
    }

    func testParseIngredientText_OCRNoisyQuantityAndUnit_Parses() {
        let ingredient = IngredientParser.parseIngredientText("I/2 c. sugar")

        XCTAssertEqual(ingredient.name, "sugar")
        XCTAssertEqual(ingredient.quantity?.value, 0.5)
        XCTAssertEqual(ingredient.quantity?.unit, .cup)
    }

    func testParseIngredientText_BulletPrefix_ParsesQuantity() {
        let ingredient = IngredientParser.parseIngredientText("• 4 Tablespoons unsalted butter melted and cooled")

        XCTAssertEqual(ingredient.name, "unsalted butter melted and cooled")
        XCTAssertEqual(ingredient.quantity?.value, 4.0)
        XCTAssertEqual(ingredient.quantity?.unit, .tablespoon)
    }

    func testParseIngredientText_MisspelledTeaspoon_ParsesUnit() {
        let ingredient = IngredientParser.parseIngredientText("1 teapoon toasted sesame oil, plus more for drizzling")

        XCTAssertEqual(ingredient.name, "toasted sesame oil, plus more for drizzling")
        XCTAssertEqual(ingredient.quantity?.value, 1.0)
        XCTAssertEqual(ingredient.quantity?.unit, .teaspoon)
    }

    func testParseIngredientText_RangeQuantity_PreservesUpperValue() {
        let ingredient = IngredientParser.parseIngredientText("8 to 8 1/2 cups all-purpose flour")

        XCTAssertEqual(ingredient.name, "all-purpose flour")
        guard let quantity = ingredient.quantity else {
            XCTFail("Expected quantity for ranged ingredient")
            return
        }
        guard let upperValue = quantity.upperValue else {
            XCTFail("Expected upper value for ranged ingredient")
            return
        }
        XCTAssertEqual(quantity.value, 8.0, accuracy: 0.001)
        XCTAssertEqual(upperValue, 8.5, accuracy: 0.001)
        XCTAssertEqual(quantity.unit, .cup)
        XCTAssertTrue(ingredient.additionalQuantities.isEmpty)
    }

    func testParseIngredientText_RangeWithUnitInSecondToken_ParsesCorrectly() {
        let ingredient = IngredientParser.parseIngredientText("3 to 4 garlic cloves")

        XCTAssertEqual(ingredient.name, "garlic")
        guard let quantity = ingredient.quantity else {
            XCTFail("Expected quantity for ranged ingredient")
            return
        }
        guard let upperValue = quantity.upperValue else {
            XCTFail("Expected upper value for ranged ingredient")
            return
        }
        XCTAssertEqual(quantity.value, 3.0, accuracy: 0.001)
        XCTAssertEqual(upperValue, 4.0, accuracy: 0.001)
        XCTAssertEqual(quantity.unit, .clove)
        XCTAssertTrue(ingredient.additionalQuantities.isEmpty)
    }

    func testParseIngredientText_MixedUnits_ParsesMultipleQuantities() {
        let ingredient = IngredientParser.parseIngredientText("1 tablespoon plus 1/2 cup sugar")

        XCTAssertEqual(ingredient.name, "sugar")
        guard let quantity = ingredient.quantity else {
            XCTFail("Expected primary quantity for mixed-unit ingredient")
            return
        }
        XCTAssertEqual(quantity.value, 1.0, accuracy: 0.001)
        XCTAssertEqual(quantity.unit, .tablespoon)
        XCTAssertEqual(ingredient.additionalQuantities.count, 1)
        XCTAssertEqual(ingredient.additionalQuantities[0].value, 0.5, accuracy: 0.001)
        XCTAssertEqual(ingredient.additionalQuantities[0].unit, .cup)
    }

    // MARK: - Extract Quantity and Unit

    func testExtractQuantityAndUnit_BasicIngredient() {
        let result = IngredientParser.extractQuantityAndUnit(from: "2 cups flour")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0.value, 2.0)
        XCTAssertEqual(result?.0.unit, .cup)
        XCTAssertEqual(result?.1.trimmingCharacters(in: .whitespaces), "flour")
    }

    func testExtractQuantityAndUnit_NoQuantity() {
        let result = IngredientParser.extractQuantityAndUnit(from: "Salt to taste")

        XCTAssertNil(result)
    }

    func testExtractQuantityAndUnit_WithFraction() {
        let result = IngredientParser.extractQuantityAndUnit(from: "1/2 tsp salt")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0.value, 0.5)
        XCTAssertEqual(result?.0.unit, .teaspoon)
        XCTAssertEqual(result?.1.trimmingCharacters(in: .whitespaces), "salt")
    }

    func testExtractQuantityAndUnit_ReturnsRemainingText() {
        let result = IngredientParser.extractQuantityAndUnit(from: "2 cups all-purpose flour, sifted")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.1.trimmingCharacters(in: .whitespaces), "all-purpose flour, sifted")
    }
}
