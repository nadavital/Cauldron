import XCTest
@testable import Cauldron

final class RecipeIngredientRefinementTests: XCTestCase {
    func testRequiredAndExcludedIngredientsAreDeterministic() {
        let refinement = RecipeIngredientRefinement(
            requiredText: "Tomato, basil, tomato",
            excludedText: "peanut"
        )

        XCTAssertEqual(refinement.required, ["tomato", "basil"])
        XCTAssertTrue(refinement.matches(ingredientNames: ["Cherry Tomatoes", "Fresh basil leaves"]))
        XCTAssertFalse(refinement.matches(ingredientNames: ["Tomatoes", "Basil", "Peanut oil"]))
    }

    func testIngredientTokensDoNotMatchInsideUnrelatedWords() {
        let refinement = RecipeIngredientRefinement(requiredText: "ham", excludedText: "")

        XCTAssertTrue(refinement.matches(ingredientNames: ["smoked ham"] ))
        XCTAssertFalse(refinement.matches(ingredientNames: ["champignon mushrooms"]))
    }

    func testNormalizationHandlesPunctuationAndDiacritics() {
        let refinement = RecipeIngredientRefinement(requiredText: "creme fraiche", excludedText: "")
        XCTAssertTrue(refinement.matches(ingredientNames: ["Crème-fraîche"]))
    }
}
