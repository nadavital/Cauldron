//
//  GroceryServiceTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class GroceryServiceTests: XCTestCase {

    var service: GroceryService!
    var unitsService: UnitsService!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        unitsService = UnitsService()
        service = GroceryService(unitsService: unitsService)
    }

    override func tearDown() async throws {
        service = nil
        unitsService = nil
        try await super.tearDown()
    }

    // MARK: - Generate Grocery List Tests

    func testGenerateGroceryList_FromRecipeWithIngredients() async throws {
        // Given
        let recipe = Recipe(
            title: "Test Recipe",
            ingredients: [
                Ingredient(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
                Ingredient(name: "sugar", quantity: Quantity(value: 1, unit: .cup)),
                Ingredient(name: "salt", quantity: nil)
            ],
            steps: [CookStep(index: 0, text: "Mix")],
            yields: "4 servings"
        )

        // When
        let groceryList = try await service.generateGroceryList(from: recipe)

        // Then
        XCTAssertEqual(groceryList.count, 3)
        XCTAssertEqual(groceryList[0].name, "flour")
        XCTAssertEqual(groceryList[0].quantity?.value, 2)
        XCTAssertEqual(groceryList[0].quantity?.unit, .cup)
        XCTAssertEqual(groceryList[1].name, "sugar")
        XCTAssertEqual(groceryList[2].name, "salt")
        XCTAssertNil(groceryList[2].quantity)
    }

    func testGenerateGroceryList_FromRecipeWithNoIngredients() async throws {
        // Given
        let recipe = Recipe(
            title: "Empty Recipe",
            ingredients: [],
            steps: [CookStep(index: 0, text: "Do nothing")],
            yields: "0 servings"
        )

        // When
        let groceryList = try await service.generateGroceryList(from: recipe)

        // Then
        XCTAssertEqual(groceryList.count, 0)
    }

    // MARK: - Merge Grocery Lists Tests

    func testMergeGroceryLists_EmptyLists() async {
        // Given
        let lists: [[GroceryItem]] = []

        // When
        let merged = await service.mergeGroceryLists(lists)

        // Then
        XCTAssertEqual(merged.count, 0)
    }

    func testMergeGroceryLists_SingleList() async {
        // Given
        let list = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
            GroceryItem(name: "sugar", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let merged = await service.mergeGroceryLists([list])

        // Then
        XCTAssertEqual(merged.count, 2)
        // Should be sorted by name
        XCTAssertEqual(merged[0].name, "flour")
        XCTAssertEqual(merged[1].name, "sugar")
    }

    func testMergeGroceryLists_CombinesSameIngredientSameUnit() async {
        // Given
        let list1 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup))
        ]
        let list2 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "flour")
        XCTAssertEqual(merged[0].quantity?.value, 3) // 2 + 1
        XCTAssertEqual(merged[0].quantity?.unit, .cup)
    }

    func testMergeGroceryLists_CaseInsensitiveMerging() async {
        // Given
        let list1 = [
            GroceryItem(name: "Flour", quantity: Quantity(value: 2, unit: .cup))
        ]
        let list2 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then - Should merge despite different casing
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].quantity?.value, 3)
    }

    func testMergeGroceryLists_TrimsWhitespace() async {
        // Given
        let list1 = [
            GroceryItem(name: "  flour  ", quantity: Quantity(value: 2, unit: .cup))
        ]
        let list2 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then - Should merge despite whitespace differences
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].quantity?.value, 3)
    }

    func testMergeGroceryLists_DifferentUnits_DoesNotCombine() async {
        // Given - Same ingredient but different units
        let list1 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup))
        ]
        let list2 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 100, unit: .gram))
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then - Should keep only the first one (doesn't convert units yet)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].quantity?.value, 2)
        XCTAssertEqual(merged[0].quantity?.unit, .cup)
    }

    func testMergeGroceryLists_MultipleIngredients() async {
        // Given
        let list1 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
            GroceryItem(name: "sugar", quantity: Quantity(value: 1, unit: .cup))
        ]
        let list2 = [
            GroceryItem(name: "flour", quantity: Quantity(value: 1, unit: .cup)),
            GroceryItem(name: "eggs", quantity: Quantity(value: 3, unit: .whole))
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then
        XCTAssertEqual(merged.count, 3)
        // Should have: eggs (3), flour (3), sugar (1) - sorted alphabetically
        let flours = merged.filter { $0.name == "flour" }
        XCTAssertEqual(flours.count, 1)
        XCTAssertEqual(flours[0].quantity?.value, 3) // 2 + 1
    }

    func testMergeGroceryLists_WithNullQuantities() async {
        // Given
        let list1 = [
            GroceryItem(name: "salt", quantity: nil)
        ]
        let list2 = [
            GroceryItem(name: "salt", quantity: nil)
        ]

        // When
        let merged = await service.mergeGroceryLists([list1, list2])

        // Then - Should keep one (doesn't combine null quantities)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].name, "salt")
        XCTAssertNil(merged[0].quantity)
    }

    func testMergeGroceryLists_SortedAlphabetically() async {
        // Given
        let list = [
            GroceryItem(name: "zucchini", quantity: nil),
            GroceryItem(name: "apples", quantity: nil),
            GroceryItem(name: "milk", quantity: nil)
        ]

        // When
        let merged = await service.mergeGroceryLists([list])

        // Then - Should be sorted
        XCTAssertEqual(merged[0].name, "apples")
        XCTAssertEqual(merged[1].name, "milk")
        XCTAssertEqual(merged[2].name, "zucchini")
    }

    // MARK: - Export to Text Tests

    func testExportToText_WithQuantities() async {
        // Given
        let items = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
            GroceryItem(name: "sugar", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let text = await service.exportToText(items)

        // Then
        XCTAssertTrue(text.contains("☐"))
        XCTAssertTrue(text.contains("flour"))
        XCTAssertTrue(text.contains("sugar"))
        XCTAssertTrue(text.contains("2"))
        XCTAssertTrue(text.contains("1"))
        XCTAssertTrue(text.contains("cup"))
    }

    func testExportToText_WithoutQuantities() async {
        // Given
        let items = [
            GroceryItem(name: "salt", quantity: nil),
            GroceryItem(name: "pepper", quantity: nil)
        ]

        // When
        let text = await service.exportToText(items)

        // Then
        XCTAssertTrue(text.contains("☐ salt"))
        XCTAssertTrue(text.contains("☐ pepper"))
        XCTAssertFalse(text.contains("cup"))
    }

    func testExportToText_EmptyList() async {
        // Given
        let items: [GroceryItem] = []

        // When
        let text = await service.exportToText(items)

        // Then
        XCTAssertEqual(text, "")
    }

    func testExportToText_NewlineSeparated() async {
        // Given
        let items = [
            GroceryItem(name: "flour", quantity: Quantity(value: 2, unit: .cup)),
            GroceryItem(name: "sugar", quantity: Quantity(value: 1, unit: .cup))
        ]

        // When
        let text = await service.exportToText(items)

        // Then
        let lines = text.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
    }
}
