//
//  UnitsServiceTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
@testable import Cauldron

@MainActor
final class UnitsServiceTests: XCTestCase {

    var service: UnitsService!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        service = UnitsService()
    }

    override func tearDown() async throws {
        service = nil
        try await super.tearDown()
    }

    // MARK: - Same Unit Tests

    func testConvert_SameUnit_ReturnsOriginal() async {
        // Given
        let quantity = Quantity(value: 2.5, unit: .cup)

        // When
        let result = await service.convert(quantity, to: .cup)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value, 2.5)
        XCTAssertEqual(result?.unit, .cup)
    }

    // MARK: - Volume Conversion Tests

    func testConvert_CupsToMilliliters() async {
        // Given - 1 cup = 236.588 ml
        let quantity = Quantity(value: 1, unit: .cup)

        // When
        let result = await service.convert(quantity, to: .milliliter)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 236.588, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .milliliter)
    }

    func testConvert_TeaspoonsToTablespoons() async {
        // Given - 3 tsp = 1 tbsp
        let quantity = Quantity(value: 3, unit: .teaspoon)

        // When
        let result = await service.convert(quantity, to: .tablespoon)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .tablespoon)
    }

    func testConvert_TablespoonsToFluidOunces() async {
        // Given - 2 tbsp = 1 fl oz
        let quantity = Quantity(value: 2, unit: .tablespoon)

        // When
        let result = await service.convert(quantity, to: .fluidOunce)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .fluidOunce)
    }

    func testConvert_CupsToPints() async {
        // Given - 2 cups = 1 pint
        let quantity = Quantity(value: 2, unit: .cup)

        // When
        let result = await service.convert(quantity, to: .pint)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .pint)
    }

    func testConvert_PintsToQuarts() async {
        // Given - 2 pints = 1 quart
        let quantity = Quantity(value: 2, unit: .pint)

        // When
        let result = await service.convert(quantity, to: .quart)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .quart)
    }

    func testConvert_QuartsToGallons() async {
        // Given - 4 quarts = 1 gallon
        let quantity = Quantity(value: 4, unit: .quart)

        // When
        let result = await service.convert(quantity, to: .gallon)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .gallon)
    }

    func testConvert_LitersToMilliliters() async {
        // Given - 1 liter = 1000 ml
        let quantity = Quantity(value: 1, unit: .liter)

        // When
        let result = await service.convert(quantity, to: .milliliter)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1000.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .milliliter)
    }

    // MARK: - Weight Conversion Tests

    func testConvert_PoundsToOunces() async {
        // Given - 1 pound = 16 ounces
        let quantity = Quantity(value: 1, unit: .pound)

        // When
        let result = await service.convert(quantity, to: .ounce)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 16.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .ounce)
    }

    func testConvert_OuncesToGrams() async {
        // Given - 1 ounce ≈ 28.35 grams
        let quantity = Quantity(value: 1, unit: .ounce)

        // When
        let result = await service.convert(quantity, to: .gram)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 28.3495, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .gram)
    }

    func testConvert_KilogramsToGrams() async {
        // Given - 1 kilogram = 1000 grams
        let quantity = Quantity(value: 1, unit: .kilogram)

        // When
        let result = await service.convert(quantity, to: .gram)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 1000.0, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .gram)
    }

    func testConvert_PoundsToKilograms() async {
        // Given - 1 pound ≈ 0.454 kg
        let quantity = Quantity(value: 1, unit: .pound)

        // When
        let result = await service.convert(quantity, to: .kilogram)

        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.value ?? 0, 0.454, accuracy: 0.01)
        XCTAssertEqual(result?.unit, .kilogram)
    }

    // MARK: - Invalid Conversion Tests

    func testConvert_VolumeToWeight_ReturnsNil() async {
        // Given - Can't convert cups to grams
        let quantity = Quantity(value: 1, unit: .cup)

        // When
        let result = await service.convert(quantity, to: .gram)

        // Then
        XCTAssertNil(result)
    }

    func testConvert_WeightToVolume_ReturnsNil() async {
        // Given - Can't convert grams to cups
        let quantity = Quantity(value: 100, unit: .gram)

        // When
        let result = await service.convert(quantity, to: .cup)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Normalization Tests

    func testNormalize_VolumeToMetric() async {
        // Given
        let quantity = Quantity(value: 1, unit: .cup)

        // When
        let result = await service.normalize(quantity, preferMetric: true)

        // Then
        XCTAssertEqual(result.unit, .milliliter)
        XCTAssertEqual(result.value, 236.588, accuracy: 0.01)
    }

    func testNormalize_VolumeToImperial() async {
        // Given
        let quantity = Quantity(value: 250, unit: .milliliter)

        // When
        let result = await service.normalize(quantity, preferMetric: false)

        // Then
        XCTAssertEqual(result.unit, .cup)
        XCTAssertEqual(result.value, 1.057, accuracy: 0.01)
    }

    func testNormalize_AlreadyMetric_NoChange() async {
        // Given
        let quantity = Quantity(value: 500, unit: .milliliter)

        // When
        let result = await service.normalize(quantity, preferMetric: true)

        // Then - Should remain unchanged
        XCTAssertEqual(result.unit, .milliliter)
        XCTAssertEqual(result.value, 500)
    }

    func testNormalize_AlreadyImperial_NoChange() async {
        // Given
        let quantity = Quantity(value: 2, unit: .cup)

        // When
        let result = await service.normalize(quantity, preferMetric: false)

        // Then - Should remain unchanged
        XCTAssertEqual(result.unit, .cup)
        XCTAssertEqual(result.value, 2)
    }

    func testNormalize_Weight_NoChange() async {
        // Given - Weight units aren't normalized (only volume)
        let quantity = Quantity(value: 100, unit: .gram)

        // When
        let result = await service.normalize(quantity, preferMetric: true)

        // Then - Should remain unchanged
        XCTAssertEqual(result.unit, .gram)
        XCTAssertEqual(result.value, 100)
    }

    // MARK: - Round Trip Conversion Tests

    func testConvert_RoundTrip_CupsToLitersToCups() async {
        // Given
        let originalQuantity = Quantity(value: 2.5, unit: .cup)

        // When - Convert to liters and back
        let liters = await service.convert(originalQuantity, to: .liter)
        let backToCups = await service.convert(liters!, to: .cup)

        // Then - Should get original value back (within rounding)
        XCTAssertEqual(backToCups?.value ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(backToCups?.unit, .cup)
    }

    func testConvert_RoundTrip_PoundsToGramsToPounds() async {
        // Given
        let originalQuantity = Quantity(value: 1.5, unit: .pound)

        // When - Convert to grams and back
        let grams = await service.convert(originalQuantity, to: .gram)
        let backToPounds = await service.convert(grams!, to: .pound)

        // Then - Should get original value back (within rounding)
        XCTAssertEqual(backToPounds?.value ?? 0, 1.5, accuracy: 0.01)
        XCTAssertEqual(backToPounds?.unit, .pound)
    }
}
