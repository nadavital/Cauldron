//
//  PreparedSharedRecipeBridgeTests.swift
//  CauldronTests
//
//  Created on February 12, 2026.
//

import XCTest
@testable import Cauldron

@MainActor
final class PreparedSharedRecipeBridgeTests: XCTestCase {

    func testRecipeParserInputText_ContainsMetadataSectionsAndNotes() {
        let recipe = Recipe(
            title: "Sheet Pan Chicken",
            ingredients: [
                Ingredient(name: "chicken thighs", quantity: Quantity(value: 1.5, unit: .pound)),
                Ingredient(name: "soy sauce", quantity: Quantity(value: 0.25, unit: .cup), section: "Sauce")
            ],
            steps: [
                CookStep(index: 0, text: "Preheat oven to 425F."),
                CookStep(index: 1, text: "Whisk the sauce.", section: "Sauce")
            ],
            yields: "4 servings",
            totalMinutes: 35,
            notes: "Optional: add sesame seeds."
        )
        let prepared = PreparedSharedRecipe(recipe: recipe, sourceInfo: "Imported from shared webpage")

        let parserInput = prepared.recipeParserInputText()

        XCTAssertTrue(parserInput.contains("Sheet Pan Chicken"))
        XCTAssertTrue(parserInput.contains("Servings: 4 servings"))
        XCTAssertTrue(parserInput.contains("Total Time: 35 minutes"))
        XCTAssertTrue(parserInput.contains("Ingredients:"))
        XCTAssertTrue(parserInput.contains("Sauce:"))
        XCTAssertTrue(parserInput.contains("Instructions:"))
        XCTAssertTrue(parserInput.contains("1. Preheat oven to 425F."))
        XCTAssertTrue(parserInput.contains("2. Whisk the sauce."))
        XCTAssertTrue(parserInput.contains("Notes:"))
        XCTAssertTrue(parserInput.contains("Optional: add sesame seeds."))
    }

    func testRecipeMergedWithParsedContent_PreservesShareMetadata() {
        let sourceURL = URL(string: "https://example.com/recipe")!
        let imageURL = URL(string: "https://example.com/image.jpg")!

        let baseRecipe = Recipe(
            title: "Original Title",
            ingredients: [Ingredient(name: "original ingredient")],
            steps: [CookStep(index: 0, text: "Original step.")],
            yields: "4 servings",
            totalMinutes: 30,
            sourceURL: sourceURL,
            sourceTitle: "Example Source",
            notes: "Original note.",
            imageURL: imageURL
        )
        let prepared = PreparedSharedRecipe(recipe: baseRecipe, sourceInfo: "Imported from shared webpage")

        let parsedRecipe = Recipe(
            title: "Parsed Title",
            ingredients: [Ingredient(name: "parsed ingredient")],
            steps: [CookStep(index: 0, text: "Parsed step.")],
            yields: "2 servings",
            totalMinutes: nil,
            notes: "Parsed note."
        )

        let merged = prepared.recipeMergedWithParsedContent(parsedRecipe)

        XCTAssertEqual(merged.id, baseRecipe.id)
        XCTAssertEqual(merged.title, "Parsed Title")
        XCTAssertEqual(merged.ingredients.map(\.name), ["parsed ingredient"])
        XCTAssertEqual(merged.steps.map(\.text), ["Parsed step."])
        XCTAssertEqual(merged.yields, "2 servings")
        XCTAssertEqual(merged.totalMinutes, 30)
        XCTAssertEqual(merged.sourceURL, sourceURL)
        XCTAssertEqual(merged.sourceTitle, "Example Source")
        XCTAssertEqual(merged.imageURL, imageURL)
        XCTAssertEqual(merged.notes, "Parsed note.")
    }

    func testPreparedShareRecipeParserInput_ReparseProducesIngredientsAndSteps() async throws {
        let recipe = Recipe(
            title: "Shared Noodles",
            ingredients: [
                Ingredient(name: "8 oz noodles"),
                Ingredient(name: "2 tbsp soy sauce")
            ],
            steps: [
                CookStep(index: 0, text: "Boil noodles for 6 minutes."),
                CookStep(index: 1, text: "Toss with soy sauce.")
            ],
            yields: "2 servings",
            totalMinutes: 15,
            notes: "Serve warm."
        )
        let prepared = PreparedSharedRecipe(recipe: recipe, sourceInfo: "Imported from shared webpage")

        let parser = TextRecipeParser()
        let reparsed = try await parser.parse(from: prepared.recipeParserInputText())

        XCTAssertFalse(reparsed.ingredients.isEmpty)
        XCTAssertFalse(reparsed.steps.isEmpty)
    }
}
