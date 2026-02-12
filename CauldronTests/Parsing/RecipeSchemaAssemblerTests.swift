//
//  RecipeSchemaAssemblerTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeSchemaAssemblerTests: XCTestCase {

    func testAssembleRoutesIngredientsStepsAndNotes() {
        let assembler = RecipeSchemaAssembler()
        let lines = [
            "Ingredients:",
            "2 eggs",
            "Steps:",
            "Whisk eggs until smooth",
            "Notes:",
            "Use room temperature eggs"
        ]
        let classifications: [RecipeLineClassification] = [
            .init(line: lines[0], label: .header, confidence: 0.99),
            .init(line: lines[1], label: .ingredient, confidence: 0.99),
            .init(line: lines[2], label: .header, confidence: 0.99),
            .init(line: lines[3], label: .step, confidence: 0.99),
            .init(line: lines[4], label: .header, confidence: 0.99),
            .init(line: lines[5], label: .note, confidence: 0.99)
        ]

        let assembly = assembler.assemble(
            lines: lines,
            classifications: classifications,
            confidenceThreshold: 0.72,
            fallbackLabel: { _ in .junk }
        )

        XCTAssertEqual(assembly.ingredients.map(\.text), ["2 eggs"])
        XCTAssertEqual(assembly.steps.map(\.text), ["Whisk eggs until smooth"])
        XCTAssertEqual(assembly.notes, ["Use room temperature eggs"])
    }

    func testLowConfidenceFallsBackToHeuristicLabel() {
        let assembler = RecipeSchemaAssembler()
        let lines = ["Bake for 20 minutes"]
        let classifications: [RecipeLineClassification] = [
            .init(line: lines[0], label: .ingredient, confidence: 0.40)
        ]

        let assembly = assembler.assemble(
            lines: lines,
            classifications: classifications,
            confidenceThreshold: 0.72,
            fallbackLabel: { _ in .step }
        )

        XCTAssertTrue(assembly.ingredients.isEmpty)
        XCTAssertEqual(assembly.steps.map(\.text), ["Bake for 20 minutes"])
    }

    func testHeaderInsideIngredientSectionIsRecoveredAsIngredient() {
        let assembler = RecipeSchemaAssembler()
        let lines = [
            "Ingredients",
            "Butter and sugar, for the pan",
            "2 eggs",
            "Instructions",
            "Mix and bake"
        ]
        let classifications: [RecipeLineClassification] = [
            .init(line: lines[0], label: .header, confidence: 0.99),
            .init(line: lines[1], label: .header, confidence: 0.99),
            .init(line: lines[2], label: .ingredient, confidence: 0.99),
            .init(line: lines[3], label: .header, confidence: 0.99),
            .init(line: lines[4], label: .step, confidence: 0.99)
        ]

        let assembly = assembler.assemble(
            lines: lines,
            classifications: classifications,
            confidenceThreshold: 0.72,
            fallbackLabel: { _ in .junk }
        )

        XCTAssertEqual(
            assembly.ingredients.map(\.text),
            ["Butter and sugar, for the pan", "2 eggs"]
        )
        XCTAssertEqual(assembly.steps.map(\.text), ["Mix and bake"])
    }

    func testIngredientSectionWithoutInstructionsHeaderRecoversStepLines() {
        let assembler = RecipeSchemaAssembler()
        let lines = [
            "Ingredients:",
            "1 cup flour",
            "1 cup sugar",
            "Preheat your oven to 350°F",
            "In a medium-sized bowl, mix the flour and sugar together",
            "Bake for about 20 minutes"
        ]
        let classifications: [RecipeLineClassification] = [
            .init(line: lines[0], label: .header, confidence: 0.99),
            .init(line: lines[1], label: .ingredient, confidence: 0.99),
            .init(line: lines[2], label: .ingredient, confidence: 0.99),
            .init(line: lines[3], label: .ingredient, confidence: 0.99),
            .init(line: lines[4], label: .ingredient, confidence: 0.99),
            .init(line: lines[5], label: .ingredient, confidence: 0.99)
        ]

        let assembly = assembler.assemble(
            lines: lines,
            classifications: classifications,
            confidenceThreshold: 0.72,
            fallbackLabel: { _ in .junk }
        )

        XCTAssertEqual(assembly.ingredients.map(\.text), ["1 cup flour", "1 cup sugar"])
        XCTAssertEqual(
            assembly.steps.map(\.text),
            [
                "Preheat your oven to 350°F",
                "In a medium-sized bowl, mix the flour and sugar together",
                "Bake for about 20 minutes"
            ]
        )
    }
}
