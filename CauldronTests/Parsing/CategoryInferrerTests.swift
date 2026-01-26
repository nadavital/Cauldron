//
//  CategoryInferrerTests.swift
//  CauldronTests
//
//  Tests for CategoryInferrer utility
//

import XCTest
@testable import Cauldron

final class CategoryInferrerTests: XCTestCase {

    // MARK: - Title-Based Inference

    func testInferCategories_VeganInTitle() {
        let tags = CategoryInferrer.inferCategories(
            title: "Vegan Pad Thai",
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Vegan" })
        XCTAssertTrue(tags.contains { $0.name == "Thai" })
    }

    func testInferCategories_ItalianInTitle() {
        let tags = CategoryInferrer.inferCategories(
            title: "Classic Italian Pasta",
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Italian" })
    }

    func testInferCategories_DessertKeywordInTitle() {
        let tags = CategoryInferrer.inferCategories(
            title: "Chocolate Cake",
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Dessert" })
    }

    func testInferCategories_BreakfastInTitle() {
        let tags = CategoryInferrer.inferCategories(
            title: "Fluffy Pancakes",
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Breakfast" })
    }

    // MARK: - Time-Based Inference

    func testInferCategories_QuickAndEasy() {
        let tags = CategoryInferrer.inferCategories(
            title: "Simple Salad",
            ingredients: [],
            steps: [],
            totalMinutes: 15
        )

        XCTAssertTrue(tags.contains { $0.name == "Quick & Easy" })
    }

    func testInferCategories_NotQuickWhenLongTime() {
        let tags = CategoryInferrer.inferCategories(
            title: "Slow Cooked Roast",
            ingredients: [],
            steps: [],
            totalMinutes: 180
        )

        XCTAssertFalse(tags.contains { $0.name == "Quick & Easy" })
    }

    // MARK: - Ingredient-Based Inference

    func testInferCategories_VegetarianFromIngredients() {
        let ingredients = [
            Ingredient(name: "Tofu", quantity: Quantity(value: 1, unit: .pound)),
            Ingredient(name: "Broccoli", quantity: Quantity(value: 2, unit: .cup)),
            Ingredient(name: "Soy sauce", quantity: Quantity(value: 2, unit: .tablespoon))
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Tofu Stir Fry",
            ingredients: ingredients,
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Vegetarian" })
    }

    func testInferCategories_NotVegetarianWithMeat() {
        let ingredients = [
            Ingredient(name: "Chicken breast", quantity: Quantity(value: 1, unit: .pound)),
            Ingredient(name: "Rice", quantity: Quantity(value: 2, unit: .cup))
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Chicken and Rice",
            ingredients: ingredients,
            steps: [],
            totalMinutes: nil
        )

        XCTAssertFalse(tags.contains { $0.name == "Vegetarian" })
        XCTAssertFalse(tags.contains { $0.name == "Vegan" })
    }

    func testInferCategories_VeganFromIngredients() {
        let ingredients = [
            Ingredient(name: "Tofu", quantity: Quantity(value: 1, unit: .pound)),
            Ingredient(name: "Almond milk", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(name: "Vegetables", quantity: Quantity(value: 2, unit: .cup))
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Vegan Bowl",
            ingredients: ingredients,
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Vegan" })
        XCTAssertTrue(tags.contains { $0.name == "Vegetarian" })
    }

    func testInferCategories_HighProtein() {
        let ingredients = [
            Ingredient(name: "Chicken breast", quantity: Quantity(value: 2, unit: .pound)),
            Ingredient(name: "Greek yogurt", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(name: "Eggs", quantity: Quantity(value: 4, unit: .whole))
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Protein Power Bowl",
            ingredients: ingredients,
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "High Protein" })
    }

    // MARK: - Cooking Method Inference

    func testInferCategories_BakingFromSteps() {
        let steps = [
            CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
            CookStep(index: 1, text: "Mix ingredients", timers: []),
            CookStep(index: 2, text: "Bake for 30 minutes", timers: [])
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Banana Bread",
            ingredients: [],
            steps: steps,
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Baking" })
    }

    func testInferCategories_AirFryerFromSteps() {
        let steps = [
            CookStep(index: 0, text: "Season the chicken", timers: []),
            CookStep(index: 1, text: "Place in air fryer at 400°F", timers: []),
            CookStep(index: 2, text: "Air fry for 15 minutes", timers: [])
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Air Fryer Chicken",
            ingredients: [],
            steps: steps,
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "Air Fryer" })
    }

    func testInferCategories_OnePotFromSteps() {
        let steps = [
            CookStep(index: 0, text: "Add everything to the instant pot", timers: []),
            CookStep(index: 1, text: "Pressure cook for 20 minutes", timers: [])
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Instant Pot Soup",
            ingredients: [],
            steps: steps,
            totalMinutes: nil
        )

        XCTAssertTrue(tags.contains { $0.name == "One Pot" })
    }

    // MARK: - Combined Inference

    func testInferCategories_MultipleCategories() {
        let ingredients = [
            Ingredient(name: "Tofu", quantity: Quantity(value: 1, unit: .pound)),
            Ingredient(name: "Rice noodles", quantity: Quantity(value: 8, unit: .ounce)),
            Ingredient(name: "Bean sprouts", quantity: Quantity(value: 1, unit: .cup))
        ]

        let steps = [
            CookStep(index: 0, text: "Prepare the tofu", timers: []),
            CookStep(index: 1, text: "Stir fry everything", timers: [])
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Vegan Pad Thai",
            ingredients: ingredients,
            steps: steps,
            totalMinutes: 25
        )

        XCTAssertTrue(tags.contains { $0.name == "Vegan" })
        XCTAssertTrue(tags.contains { $0.name == "Thai" })
        XCTAssertTrue(tags.contains { $0.name == "Quick & Easy" })
        XCTAssertTrue(tags.contains { $0.name == "Vegetarian" })
    }

    // MARK: - Edge Cases

    func testInferCategories_EmptyInput() {
        let tags = CategoryInferrer.inferCategories(
            title: "",
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        XCTAssertTrue(tags.isEmpty)
    }

    func testInferCategories_NoDuplicates() {
        let tags = CategoryInferrer.inferCategories(
            title: "Vegan Vegan Recipe",  // Double mention
            ingredients: [],
            steps: [],
            totalMinutes: nil
        )

        let veganCount = tags.filter { $0.name == "Vegan" }.count
        XCTAssertEqual(veganCount, 1)
    }

    // MARK: - Real-World Examples

    func testInferCategories_RealWorldChocolateChipCookies() {
        let ingredients = [
            Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
            Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(name: "butter", quantity: Quantity(value: 0.5, unit: .cup)),
            Ingredient(name: "eggs", quantity: Quantity(value: 2, unit: .whole)),
            Ingredient(name: "chocolate chips", quantity: Quantity(value: 1, unit: .cup))
        ]

        let steps = [
            CookStep(index: 0, text: "Preheat oven to 350°F", timers: []),
            CookStep(index: 1, text: "Mix ingredients", timers: []),
            CookStep(index: 2, text: "Bake for 12 minutes", timers: [])
        ]

        let tags = CategoryInferrer.inferCategories(
            title: "Classic Chocolate Chip Cookies",
            ingredients: ingredients,
            steps: steps,
            totalMinutes: 30
        )

        XCTAssertTrue(tags.contains { $0.name == "Dessert" })
        XCTAssertTrue(tags.contains { $0.name == "Baking" })
        XCTAssertTrue(tags.contains { $0.name == "Quick & Easy" })
    }
}
