//
//  TextParserEntryParityTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class TextParserEntryParityTests: XCTestCase {
    private var parser: TextRecipeParser!

    override func setUp() async throws {
        try await super.setUp()
        parser = TextRecipeParser()
    }

    override func tearDown() async throws {
        parser = nil
        try await super.tearDown()
    }

    func testSectionedRecipe_ParseFromMatchesParseLines() async throws {
        let text = """
        Weeknight Pasta
        Serves 4
        Total time: 45 minutes

        Ingredients:
        1 lb pasta
        2 cups sauce

        Instructions:
        Boil pasta for 10 minutes
        Toss with sauce
        """

        let fromText = try await parser.parse(from: text)
        let fromLines = try await parser.parse(
            lines: normalizedLines(from: text),
            sourceURL: nil,
            sourceTitle: nil,
            imageURL: nil,
            tags: [],
            preferredTitle: nil,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )

        assertEquivalent(fromText, fromLines)
    }

    func testHeaderlessRecipe_ParseFromMatchesParseLines() async throws {
        let text = """
        Scrambled Eggs
        2 eggs
        1 tbsp butter
        Salt and pepper
        Crack eggs into bowl
        Beat eggs with fork until smooth
        Heat butter in pan over medium heat
        Pour eggs into pan and stir constantly
        """

        let fromText = try await parser.parse(from: text)
        let fromLines = try await parser.parse(
            lines: normalizedLines(from: text),
            sourceURL: nil,
            sourceTitle: nil,
            imageURL: nil,
            tags: [],
            preferredTitle: nil,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )

        assertEquivalent(fromText, fromLines)
    }

    func testMetadataBeforeTitle_ParseFromMatchesParseLines() async throws {
        let text = """
        Total time: 45 minutes
        Weeknight Pasta
        Serves 4

        Ingredients:
        1 lb pasta
        2 cups sauce

        Instructions:
        Boil pasta for 10 minutes
        Toss with sauce
        """

        let fromText = try await parser.parse(from: text)
        let fromLines = try await parser.parse(
            lines: normalizedLines(from: text),
            sourceURL: nil,
            sourceTitle: nil,
            imageURL: nil,
            tags: [],
            preferredTitle: nil,
            yieldsOverride: nil,
            totalMinutesOverride: nil
        )

        assertEquivalent(fromText, fromLines)
    }

    private func normalizedLines(from text: String) -> [String] {
        InputNormalizer.normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func assertEquivalent(_ lhs: Recipe, _ rhs: Recipe, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.title, rhs.title, file: file, line: line)
        XCTAssertEqual(lhs.yields, rhs.yields, file: file, line: line)
        XCTAssertEqual(lhs.totalMinutes, rhs.totalMinutes, file: file, line: line)
        XCTAssertEqual(lhs.ingredients.map(\.name), rhs.ingredients.map(\.name), file: file, line: line)
        XCTAssertEqual(lhs.steps.map(\.text), rhs.steps.map(\.text), file: file, line: line)
        XCTAssertEqual(lhs.notes, rhs.notes, file: file, line: line)
    }
}
