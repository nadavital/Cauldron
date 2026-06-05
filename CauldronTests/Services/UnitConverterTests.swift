//
//  UnitConverterTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class UnitConverterTests: XCTestCase {

    // MARK: - Original

    func testOriginalLeavesQuantitiesUnchanged() {
        let q = Quantity(value: 2, unit: .cup)
        let result = UnitConverter.convert(q, to: .original)
        XCTAssertEqual(result.unit, .cup)
        XCTAssertEqual(result.value, 2, accuracy: 0.001)
    }

    // MARK: - Volume

    func testCupToMetricMilliliters() {
        let result = UnitConverter.convert(Quantity(value: 1, unit: .cup), to: .metric)
        XCTAssertEqual(result.unit, .milliliter)
        XCTAssertEqual(result.value, 237, accuracy: 1) // 236.588 → 237
    }

    func testLargeVolumeToMetricUsesLiters() {
        // 6 cups ≈ 1419 ml → liters
        let result = UnitConverter.convert(Quantity(value: 6, unit: .cup), to: .metric)
        XCTAssertEqual(result.unit, .liter)
        XCTAssertEqual(result.value, 1.4, accuracy: 0.1)
    }

    func testMillilitersToUSPicksCup() {
        let result = UnitConverter.convert(Quantity(value: 250, unit: .milliliter), to: .us)
        XCTAssertEqual(result.unit, .cup)
        XCTAssertEqual(result.value, 1.0, accuracy: 0.25)
    }

    func testSmallMetricVolumeToUSPicksTeaspoon() {
        let result = UnitConverter.convert(Quantity(value: 5, unit: .milliliter), to: .us)
        XCTAssertEqual(result.unit, .teaspoon)
    }

    // MARK: - Weight

    func testPoundToMetricGrams() {
        let result = UnitConverter.convert(Quantity(value: 1, unit: .pound), to: .metric)
        XCTAssertEqual(result.unit, .gram)
        XCTAssertEqual(result.value, 454, accuracy: 1)
    }

    func testKilogramRangeToMetricStaysKilograms() {
        let result = UnitConverter.convert(Quantity(value: 1500, unit: .gram), to: .metric)
        XCTAssertEqual(result.unit, .kilogram)
        XCTAssertEqual(result.value, 1.5, accuracy: 0.1)
    }

    func testGramsToUSPicksPoundWhenLarge() {
        let result = UnitConverter.convert(Quantity(value: 1000, unit: .gram), to: .us)
        XCTAssertEqual(result.unit, .pound)
        XCTAssertEqual(result.value, 2.25, accuracy: 0.25)
    }

    // MARK: - Non-convertible

    func testCountUnitIsUnchanged() {
        let q = Quantity(value: 3, unit: .whole)
        let result = UnitConverter.convert(q, to: .metric)
        XCTAssertEqual(result.unit, .whole)
        XCTAssertEqual(result.value, 3, accuracy: 0.001)
    }

    // MARK: - Ranges & ingredient lists

    func testRangeBoundsAreConverted() {
        let q = Quantity(value: 1, upperValue: 2, unit: .cup)
        let result = UnitConverter.convert(q, to: .metric)
        XCTAssertEqual(result.unit, .milliliter)
        XCTAssertEqual(result.value, 237, accuracy: 1)
        XCTAssertEqual(result.upperValue ?? 0, 473, accuracy: 2)
    }

    func testConvertIngredientsPreservesIdsAndNames() {
        let ingredients = [
            Ingredient(name: "milk", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(name: "salt", quantity: nil)
        ]
        let result = UnitConverter.convert(ingredients, to: .metric)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, ingredients[0].id)
        XCTAssertEqual(result[0].name, "milk")
        XCTAssertEqual(result[0].quantity?.unit, .milliliter)
        XCTAssertNil(result[1].quantity) // unchanged, no quantity
    }
}
