import XCTest
@testable import Cauldron

@MainActor
final class RecipeVisualLabelMatcherTests: XCTestCase {
    func testRanksTitleThenIngredientMatches() {
        let titleMatch = entity(title: "Tomato Soup", ingredients: ["stock"])
        let ingredientMatch = entity(title: "Weeknight Pasta", ingredients: ["tomato"])

        let matches = RecipeVisualLabelMatcher.matches(
            labels: ["Tomato", "Food"],
            recipes: [ingredientMatch, titleMatch],
            limit: 8
        )

        XCTAssertEqual(matches.map(\.id), [titleMatch.id, ingredientMatch.id])
    }

    func testExpandsCommonFoodSynonyms() {
        let recipe = entity(title: "Roasted Eggplant", ingredients: ["eggplant"])

        let matches = RecipeVisualLabelMatcher.matches(
            labels: ["aubergine"],
            recipes: [recipe],
            limit: 8
        )

        XCTAssertEqual(matches.map(\.id), [recipe.id])
    }

    func testReturnsEmptyForGenericOrUnrelatedLabels() {
        let recipe = entity(title: "Apple Pie", ingredients: ["apple"])

        XCTAssertTrue(RecipeVisualLabelMatcher.matches(
            labels: ["food", "plate"],
            recipes: [recipe],
            limit: 8
        ).isEmpty)
        XCTAssertTrue(RecipeVisualLabelMatcher.matches(
            labels: ["automobile"],
            recipes: [recipe],
            limit: 8
        ).isEmpty)
    }

    func testScallionDoesNotMatchGenericGreenRecipe() {
        let unrelated = entity(title: "Green Salad", ingredients: ["lettuce"])
        let scallionRecipe = entity(title: "Noodle Bowl", ingredients: ["green onion"])

        let matches = RecipeVisualLabelMatcher.matches(
            labels: ["scallion"],
            recipes: [unrelated, scallionRecipe],
            limit: 8
        )

        XCTAssertEqual(matches.map(\.id), [scallionRecipe.id])
    }

    func testMatchesCommonSingularAndPluralFoodLabels() {
        let recipe = entity(title: "Tomato Noodles", ingredients: ["apples"])

        XCTAssertEqual(
            RecipeVisualLabelMatcher.matches(labels: ["tomatoes"], recipes: [recipe], limit: 8).map(\.id),
            [recipe.id]
        )
        XCTAssertEqual(
            RecipeVisualLabelMatcher.matches(labels: ["apple"], recipes: [recipe], limit: 8).map(\.id),
            [recipe.id]
        )
    }

    private func entity(title: String, ingredients: [String]) -> RecipeIntentEntity {
        RecipeIntentEntity(
            id: UUID(),
            title: title,
            ingredientNames: ingredients,
            instructions: "Cook until done.",
            totalMinutes: 30
        )
    }
}
