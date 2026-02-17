//
//  RecipeSchemaRegressionTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class RecipeSchemaRegressionTests: XCTestCase {
    private var parser: TextRecipeParser!

    override func setUp() async throws {
        try await super.setUp()
        parser = TextRecipeParser()
    }

    override func tearDown() async throws {
        parser = nil
        try await super.tearDown()
    }

    func testNotesDoNotLeakIntoIngredientsOrSteps() async throws {
        let text = """
        Quick Chili
        1 lb ground beef
        1 can tomatoes
        Brown beef in a pot
        Add tomatoes and simmer 20 minutes
        Notes:
        Tastes better the next day
        """

        let recipe = try await parser.parse(from: text)
        let notes = recipe.notes?.lowercased() ?? ""

        XCTAssertTrue(notes.contains("tastes better the next day"))
        XCTAssertFalse(recipe.ingredients.contains { $0.name.lowercased().contains("tastes better") })
        XCTAssertFalse(recipe.steps.contains { $0.text.lowercased().contains("tastes better") })
    }

    func testIngredientAndStepSectionsRemainStable() async throws {
        let text = """
        Weeknight Stir Fry
        Ingredients:
        2 tbsp soy sauce
        1 tbsp sesame oil
        Instructions:
        Heat pan over high heat
        Cook vegetables for 5 minutes
        Add sauce and toss
        """

        let recipe = try await parser.parse(from: text)

        XCTAssertTrue(recipe.ingredients.contains { $0.name.lowercased().contains("soy sauce") })
        XCTAssertTrue(recipe.ingredients.contains { $0.name.lowercased().contains("sesame oil") })
        XCTAssertTrue(recipe.steps.contains { $0.text.lowercased().contains("heat pan") })
        XCTAssertTrue(recipe.steps.contains { $0.text.lowercased().contains("add sauce") })
    }

    func testNoisyMarkupLinesAreIgnored() async throws {
        let text = """
        Baked Oats
        <div>ads</div>
        INGREDIENTS
        1 cup oats
        1 banana
        METHOD
        Mash banana with oats
        Bake for 20 minutes
        Tip:
        Top with yogurt
        """

        let recipe = try await parser.parse(from: text)

        XCTAssertEqual(
            recipe.ingredients.count,
            2,
            "ingredients=\(recipe.ingredients.map { $0.name }) steps=\(recipe.steps.map { $0.text }) notes=\(recipe.notes ?? "nil")"
        )
        XCTAssertEqual(
            recipe.steps.count,
            2,
            "ingredients=\(recipe.ingredients.map { $0.name }) steps=\(recipe.steps.map { $0.text }) notes=\(recipe.notes ?? "nil")"
        )
        XCTAssertTrue(recipe.notes?.lowercased().contains("top with yogurt") ?? false)
    }
}
