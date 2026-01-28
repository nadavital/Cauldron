//
//  TextSectionParserTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class TextSectionParserTests: XCTestCase {

    // MARK: - Numbered Step Detection

    func testLooksLikeNumberedStep_WithPeriod() {
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("1. Mix the ingredients together"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("2. Heat the oven to 350°F"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("10. Serve and enjoy"))
    }

    func testLooksLikeNumberedStep_WithParenthesis() {
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("1) Mix the ingredients"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("2) Heat the oven"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("10) Serve hot"))
    }

    func testLooksLikeNumberedStep_WithHyphen() {
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("1 - Mix the ingredients"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("2 - Heat the oven"))
    }

    func testLooksLikeNumberedStep_WithColon() {
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("1: Mix the ingredients"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("2: Heat the oven"))
    }

    func testLooksLikeNumberedStep_WithStepPrefix() {
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("Step 1. Mix the ingredients"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("Step 2) Heat the oven"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("Step 3: Bake for 30 minutes"))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep("step 1. Mix ingredients"))  // Case insensitive
    }

    func testLooksLikeNumberedStep_TooShort() {
        // Lines that are just "1." or "2)" without content should not be detected
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("1."))
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("2)"))
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("1:"))
    }

    func testLooksLikeNumberedStep_NotNumberedStep() {
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("Mix the ingredients"))
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("Heat oven to 350°F"))
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("2 cups flour"))
    }

    // MARK: - Ingredient Detection

    func testLooksLikeIngredient_WithWholeNumber() {
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("2 cups flour"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("1 tsp salt"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("10 oz butter"))
    }

    func testLooksLikeIngredient_WithFraction() {
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("1/2 cup sugar"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("3/4 tsp vanilla"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("1/4 cup milk"))
    }

    func testLooksLikeIngredient_WithUnicodeFraction() {
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("½ cup butter"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("¼ tsp salt"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("¾ cup water"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("⅓ cup oil"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("⅔ cup milk"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("⅛ tsp pepper"))
    }

    func testLooksLikeIngredient_WithMixedNumber() {
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("1 1/2 cups flour"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("2 1/4 tsp baking powder"))
    }

    func testLooksLikeIngredient_WithDecimal() {
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("2.5 cups sugar"))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient("0.5 tsp salt"))
    }

    func testLooksLikeIngredient_NotIngredient() {
        XCTAssertFalse(TextSectionParser.looksLikeIngredient("Salt to taste"))
        XCTAssertFalse(TextSectionParser.looksLikeIngredient("Fresh basil"))
        XCTAssertFalse(TextSectionParser.looksLikeIngredient("Mix well"))
        XCTAssertFalse(TextSectionParser.looksLikeIngredient("Instructions"))
    }

    // MARK: - Ingredient Section Header Detection

    func testIsIngredientSectionHeader_BasicHeader() {
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("Ingredients"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("Ingredients:"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("INGREDIENTS"))
    }

    func testIsIngredientSectionHeader_WithSubsection() {
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("For the dough ingredients:"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("Cake ingredients"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("Frosting ingredients:"))
    }

    func testIsIngredientSectionHeader_CaseInsensitive() {
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("ingredients"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("INGREDIENTS"))
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader("Ingredients"))
    }

    func testIsIngredientSectionHeader_TooLong() {
        // Should reject very long lines (not headers)
        let longLine = "Here are all the ingredients you'll need for this delicious recipe"
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader(longLine))
    }

    func testIsIngredientSectionHeader_NotHeader() {
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader("2 cups flour"))
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader("Instructions"))
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader("Mix well"))
    }

    // MARK: - Steps Section Header Detection

    func testIsStepsSectionHeader_Instructions() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Instructions"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Instructions:"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("INSTRUCTIONS"))
    }

    func testIsStepsSectionHeader_Directions() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Directions"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Directions:"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("DIRECTIONS"))
    }

    func testIsStepsSectionHeader_Method() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Method"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Method:"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Cooking method"))
    }

    func testIsStepsSectionHeader_HowTo() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("How to make"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("How to prepare"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("How to:"))
    }

    func testIsStepsSectionHeader_Preparation() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Preparation"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Preparation:"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Preparation steps"))
    }

    func testIsStepsSectionHeader_Steps() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Steps"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Steps:"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Cooking steps"))
    }

    func testIsStepsSectionHeader_NotStepNumbered() {
        // "Step 1. Mix ingredients" should NOT be detected as a header (it's a numbered step)
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader("Step 1. Mix the ingredients together thoroughly"))
    }

    func testIsStepsSectionHeader_NotHeader() {
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader("Ingredients"))
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader("2 cups flour"))
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader("Mix the ingredients"))
    }

    func testIsStepsSectionHeader_CaseInsensitive() {
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("instructions"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("DIRECTIONS"))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader("Method"))
    }

    // MARK: - Edge Cases

    func testEmptyString() {
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep(""))
        XCTAssertFalse(TextSectionParser.looksLikeIngredient(""))
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader(""))
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(TextSectionParser.looksLikeNumberedStep("   "))
        XCTAssertFalse(TextSectionParser.looksLikeIngredient("   "))
        XCTAssertFalse(TextSectionParser.isIngredientSectionHeader("   "))
        XCTAssertFalse(TextSectionParser.isStepsSectionHeader("   "))
    }

    // MARK: - Real-World Examples

    func testRealWorld_RecipeParsing() {
        // Simulate parsing a real recipe text
        let recipeLines = [
            "Chocolate Chip Cookies",
            "",
            "Ingredients:",
            "2 cups all-purpose flour",
            "1 tsp baking soda",
            "½ cup butter, softened",
            "¾ cup sugar",
            "",
            "Instructions:",
            "1. Preheat oven to 375°F",
            "2. Mix butter and sugar until creamy",
            "3. Add flour and baking soda",
            "4. Bake for 10 minutes"
        ]

        // Test section headers
        XCTAssertTrue(TextSectionParser.isIngredientSectionHeader(recipeLines[2]))
        XCTAssertTrue(TextSectionParser.isStepsSectionHeader(recipeLines[8]))

        // Test ingredients
        XCTAssertTrue(TextSectionParser.looksLikeIngredient(recipeLines[3]))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient(recipeLines[4]))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient(recipeLines[5]))
        XCTAssertTrue(TextSectionParser.looksLikeIngredient(recipeLines[6]))

        // Test numbered steps
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep(recipeLines[9]))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep(recipeLines[10]))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep(recipeLines[11]))
        XCTAssertTrue(TextSectionParser.looksLikeNumberedStep(recipeLines[12]))
    }
}
