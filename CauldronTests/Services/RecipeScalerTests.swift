//
//  RecipeScalerTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class RecipeScalerTests: XCTestCase {

    var testRecipe: Recipe!

    // MARK: - Setup

    override func setUp() {
        super.setUp()

        // Create a test recipe with various ingredients
        testRecipe = Recipe(
            title: "Test Recipe",
            ingredients: [
                Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
                Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup)),
                Ingredient(name: "eggs", quantity: Quantity(value: 3, unit: .whole)),
                Ingredient(name: "vanilla extract", quantity: Quantity(value: 1, unit: .teaspoon)),
                Ingredient(name: "salt", quantity: nil) // Ingredient without quantity
            ],
            steps: [CookStep(index: 0, text: "Mix ingredients")],
            yields: "4 servings"
        )
    }

    override func tearDown() {
        testRecipe = nil
        super.tearDown()
    }

    // MARK: - Basic Scaling Tests

    func testScale_ByTwo_DoublesIngredients() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.factor, 2.0)
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value, 4.0) // flour: 2 → 4
        XCTAssertEqual(scaled.recipe.ingredients[1].quantity?.value, 2.0) // sugar: 1 → 2
        XCTAssertEqual(scaled.recipe.ingredients[2].quantity?.value, 6.0) // eggs: 3 → 6
    }

    func testScale_ByHalf_HalvesIngredients() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 0.5)

        // Then
        XCTAssertEqual(scaled.factor, 0.5)
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value, 1.0) // flour: 2 → 1
        XCTAssertEqual(scaled.recipe.ingredients[1].quantity?.value, 0.5) // sugar: 1 → 0.5
        XCTAssertEqual(scaled.recipe.ingredients[2].quantity?.value, 1.5) // eggs: 3 → 1.5
    }

    func testScale_ByOne_NoChange() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 1.0)

        // Then
        XCTAssertEqual(scaled.factor, 1.0)
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value, 2.0) // flour unchanged
        XCTAssertEqual(scaled.recipe.ingredients[1].quantity?.value, 1.0) // sugar unchanged
    }

    func testScale_IngredientWithoutQuantity_Unchanged() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then - Salt has no quantity, should remain nil
        XCTAssertNil(scaled.recipe.ingredients[4].quantity)
        XCTAssertEqual(scaled.recipe.ingredients[4].name, "salt")
    }

    func testScale_IngredientWithAdditionalQuantities_ScalesAllQuantities() {
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(
                    name: "sugar",
                    quantity: Quantity(value: 1, unit: .tablespoon),
                    additionalQuantities: [Quantity(value: 0.5, unit: .cup)]
                )
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "2 servings"
        )

        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        guard let primaryQuantity = scaled.recipe.ingredients[0].quantity else {
            XCTFail("Expected primary quantity after scaling")
            return
        }
        XCTAssertEqual(primaryQuantity.value, 2.0, accuracy: 0.001)
        XCTAssertEqual(primaryQuantity.unit, .tablespoon)
        XCTAssertEqual(scaled.recipe.ingredients[0].additionalQuantities.count, 1)
        XCTAssertEqual(scaled.recipe.ingredients[0].additionalQuantities[0].value, 1.0, accuracy: 0.001)
        XCTAssertEqual(scaled.recipe.ingredients[0].additionalQuantities[0].unit, .cup)
    }

    // MARK: - Smart Rounding Tests

    func testScale_SmallQuantity_RoundsToSixteenth() {
        // Given - 0.125 tsp (1/8 tsp) scaled by 0.5 = 0.0625
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(name: "spice", quantity: Quantity(value: 0.125, unit: .teaspoon))
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "1 serving"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 0.5)

        // Then - Should round to nearest 1/16
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value ?? 0, 0.0625, accuracy: 0.001)
    }

    func testScale_MediumQuantity_RoundsToQuarter() {
        // Given - 1.3 cups scaled by 1.5 = 1.95
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(name: "milk", quantity: Quantity(value: 1.3, unit: .cup))
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "1 serving"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 1.5)

        // Then - Should round to nearest 1/4 (2.0)
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value ?? 0, 2.0, accuracy: 0.001)
    }

    func testScale_LargeQuantity_RoundsToNearest10() {
        // Given - 120 cups scaled by 1.1 = 132
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(name: "water", quantity: Quantity(value: 120, unit: .cup))
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "1 serving"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 1.1)

        // Then - Should round to nearest 10 (130)
        XCTAssertEqual(scaled.recipe.ingredients[0].quantity?.value ?? 0, 130.0, accuracy: 0.001)
    }

    // MARK: - Yields Scaling Tests

    func testScale_YieldsWithServings_UpdatesNumber() {
        // Given - "4 servings"
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then - Should update the number from 4 to 8
        XCTAssertEqual(scaled.recipe.yields, "8 servings")
    }

    func testScale_YieldsWithServes_UpdatesNumber() {
        // Given
        var recipe = testRecipe!
        recipe = Recipe(
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: "serves 4"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 3.0)

        // Then
        XCTAssertEqual(scaled.recipe.yields, "serves 12")
    }

    func testScale_YieldsWithMakes_UpdatesNumber() {
        // Given
        var recipe = testRecipe!
        recipe = Recipe(
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: "makes 12 cookies"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 0.5)

        // Then
        XCTAssertEqual(scaled.recipe.yields, "makes 6 cookies")
    }

    func testScale_YieldsNoNumber_AppendsScalingInfo() {
        // Given
        var recipe = testRecipe!
        recipe = Recipe(
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: "one large batch"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        // Then - Should append scaling factor
        XCTAssertTrue(scaled.recipe.yields.contains("×2"))
    }

    // MARK: - Warning Tests

    func testScale_FractionalEggs_GeneratesWarning() {
        // Given - 3 eggs scaled by 0.5 = 1.5 eggs
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 0.5)

        // Then
        XCTAssertTrue(scaled.hasWarnings)
        XCTAssertTrue(scaled.warnings.contains { $0.type == .fractionalEggs })
    }

    func testScale_WholeEggs_NoWarning() {
        // Given - 3 eggs scaled by 2.0 = 6.0 eggs (whole number)
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then - Should not have fractional egg warning
        XCTAssertFalse(scaled.warnings.contains { $0.type == .fractionalEggs })
    }

    func testScale_VeryLargeQuantity_GeneratesWarning() {
        // Given - 30 cups scaled by 2 = 60 cups (very large)
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(name: "water", quantity: Quantity(value: 30, unit: .cup))
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "1 serving"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        // Then
        XCTAssertTrue(scaled.hasWarnings)
        XCTAssertTrue(scaled.warnings.contains { $0.type == .veryLargeQuantity })
    }

    func testScale_ExtremeScalingUp_GeneratesWarning() {
        // When - Scale by 5× (extreme)
        let scaled = RecipeScaler.scale(testRecipe, by: 5.0)

        // Then
        XCTAssertTrue(scaled.hasWarnings)
        XCTAssertTrue(scaled.warnings.contains { $0.type == .extremeScaling })
    }

    func testScale_ExtremeScalingDown_GeneratesWarning() {
        // When - Scale by 0.25× (extreme)
        let scaled = RecipeScaler.scale(testRecipe, by: 0.25)

        // Then
        XCTAssertTrue(scaled.hasWarnings)
        XCTAssertTrue(scaled.warnings.contains { $0.type == .extremeScaling })
    }

    func testScale_NormalScaling_NoExtremeWarning() {
        // When - Scale by 2× (normal)
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then - Should not have extreme scaling warning
        XCTAssertFalse(scaled.warnings.contains { $0.type == .extremeScaling })
    }

    // MARK: - Nutrition Scaling Tests

    func testScale_WithNutrition_ScalesNutrition() {
        // Given
        let nutrition = Nutrition(
            calories: 200,
            protein: 10,
            fat: 5,
            carbohydrates: 30,
            fiber: 2,
            sugar: 15,
            sodium: 100
        )
        var recipe = testRecipe!
        recipe = Recipe(
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: recipe.yields,
            nutrition: nutrition
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.recipe.nutrition?.calories, 400)
        XCTAssertEqual(scaled.recipe.nutrition?.protein, 20)
        XCTAssertEqual(scaled.recipe.nutrition?.carbohydrates, 60)
    }

    func testScale_WithoutNutrition_NutritionRemainsNil() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then
        XCTAssertNil(scaled.recipe.nutrition)
    }

    // MARK: - Recipe Properties Preservation Tests

    func testScale_PreservesTitle() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.recipe.title, testRecipe.title)
    }

    func testScale_PreservesSteps() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.recipe.steps.count, testRecipe.steps.count)
        XCTAssertEqual(scaled.recipe.steps[0].text, testRecipe.steps[0].text)
    }

    func testScale_PreservesTags() {
        // Given
        var recipe = testRecipe!
        recipe = Recipe(
            title: recipe.title,
            ingredients: recipe.ingredients,
            steps: recipe.steps,
            yields: recipe.yields,
            tags: [Tag(name: "dessert"), Tag(name: "quick")]
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.recipe.tags.count, 2)
        // Note: Tag initializer normalizes names - "dessert" becomes "Dessert"
        XCTAssertEqual(scaled.recipe.tags[0].name, "Dessert")
    }

    func testScale_UpdatesUpdatedAt() {
        // Given
        let originalUpdatedAt = testRecipe.updatedAt

        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then - updatedAt should be newer
        XCTAssertGreaterThanOrEqual(scaled.recipe.updatedAt, originalUpdatedAt)
    }

    func testScale_PreservesId() {
        // When
        let scaled = RecipeScaler.scale(testRecipe, by: 2.0)

        // Then
        XCTAssertEqual(scaled.recipe.id, testRecipe.id)
    }

    func testScale_PreservesSectionOnIngredients() {
        // Given - Recipe with sectioned ingredients
        let recipe = Recipe(
            title: "Test",
            ingredients: [
                Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup), section: "Dough"),
                Ingredient(name: "water", quantity: Quantity(value: 1, unit: .cup), section: "Dough"),
                Ingredient(name: "cream cheese", quantity: Quantity(value: 8, unit: .ounce), section: "Filling"),
                Ingredient(name: "salt", quantity: nil, section: "Filling") // No quantity
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "4 servings"
        )

        // When
        let scaled = RecipeScaler.scale(recipe, by: 2.0)

        // Then - All sections should be preserved
        XCTAssertEqual(scaled.recipe.ingredients[0].section, "Dough")
        XCTAssertEqual(scaled.recipe.ingredients[1].section, "Dough")
        XCTAssertEqual(scaled.recipe.ingredients[2].section, "Filling")
        XCTAssertEqual(scaled.recipe.ingredients[3].section, "Filling")
    }
}
