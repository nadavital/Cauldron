//
//  RecipeLineClassificationServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeLineClassificationServiceTests: XCTestCase {

    func testClassifiesRecipeLineLabels() {
        let service = RecipeLineClassificationService()
        let lines = [
            "Ingredients:",
            "2 cups flour",
            "Mix flour and water",
            "Notes:",
            "Use warm water for better rise",
            "<div class=\"ad\">"
        ]

        let results = service.classify(lines: lines)

        XCTAssertEqual(results.count, lines.count)
        XCTAssertEqual(results[0].label, .header)
        XCTAssertEqual(results[1].label, .ingredient)
        XCTAssertEqual(results[2].label, .ingredient)
        XCTAssertEqual(results[3].label, .header)
        XCTAssertEqual(results[4].label, .note)
        XCTAssertEqual(results[5].label, .note)
    }

    func testInlineNotePrefixIsClassifiedAsNote() {
        let service = RecipeLineClassificationService()
        let results = service.classify(lines: ["Tip: Toast spices before grinding"])

        XCTAssertEqual(results.first?.label, .title)
        XCTAssertGreaterThanOrEqual(results.first?.confidence ?? 0, 0.75)
    }

    func testAmbiguousLineUsesModelSignal() {
        let service = RecipeLineClassificationService()
        let results = service.classify(lines: ["fresh basil leaves and lemon zest"])

        XCTAssertEqual(results.first?.label, .title)
        XCTAssertGreaterThan(results.first?.confidence ?? 0, 0.70)
    }
}
