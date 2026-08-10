import XCTest
@testable import Cauldron

final class RecipePlainTextFormatterTests: XCTestCase {
    func testIngredientsPreserveSectionsQuantitiesAndNotes() {
        let recipe = makeRecipe()

        XCTAssertEqual(
            RecipePlainTextFormatter.format(recipe, content: .ingredients),
            """
            Dough
            • 2 cups flour (sifted)
            • 1 teaspoon salt

            Filling
            • Apples
            """
        )
    }

    func testDirectionsPreserveSectionsNumberingAndTimers() {
        let recipe = makeRecipe()

        XCTAssertEqual(
            RecipePlainTextFormatter.format(recipe, content: .directions),
            """
            Prepare
            1. Mix the dough.

            Bake
            2. Bake until golden. [Bake: 45m]
            """
        )
    }

    func testFullRecipeIncludesMetadataNotesAndSource() {
        let result = RecipePlainTextFormatter.format(makeRecipe(), content: .fullRecipe)

        XCTAssertTrue(result.hasPrefix("Apple Pie\n\n8 servings\nTotal time: 1h 15m"))
        XCTAssertTrue(result.contains("\n\nIngredients\nDough\n• 2 cups flour (sifted)"))
        XCTAssertTrue(result.contains("\n\nDirections\nPrepare\n1. Mix the dough."))
        XCTAssertTrue(result.contains("\n\nNotes\nBest served warm."))
        XCTAssertTrue(result.hasSuffix("Source: Family Recipe — https://example.com/pie"))
    }

    func testPresentedScaledMetricIngredientsAreExportedInsteadOfOriginalUnits() {
        let scaledRecipe = makeRecipe().scaled(by: 0.5)
        let displayedIngredients = UnitConverter.convert(scaledRecipe.ingredients, to: .metric)

        let result = RecipePlainTextFormatter.format(
            scaledRecipe,
            displayedIngredients: displayedIngredients,
            content: .ingredients
        )

        XCTAssertTrue(result.contains("• 237 milliliters flour (sifted)"))
        XCTAssertFalse(result.contains("2 cups flour"))
    }

    private func makeRecipe() -> Recipe {
        Recipe(
            title: "Apple Pie",
            ingredients: [
                Ingredient(
                    name: "flour",
                    quantity: Quantity(value: 2, unit: .cup),
                    note: "sifted",
                    section: "Dough"
                ),
                Ingredient(
                    name: "salt",
                    quantity: Quantity(value: 1, unit: .teaspoon),
                    section: "Dough"
                ),
                Ingredient(name: "Apples", section: "Filling")
            ],
            steps: [
                CookStep(index: 0, text: "Mix the dough.", section: "Prepare"),
                CookStep(
                    index: 1,
                    text: "Bake until golden.",
                    timers: [.minutes(45, label: "Bake")],
                    section: "Bake"
                )
            ],
            yields: "8 servings",
            totalMinutes: 75,
            sourceURL: URL(string: "https://example.com/pie"),
            sourceTitle: "Family Recipe",
            notes: "Best served warm."
        )
    }
}
