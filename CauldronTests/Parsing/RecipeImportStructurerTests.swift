import XCTest
@testable import Cauldron

@MainActor
final class RecipeImportStructurerTests: XCTestCase {
    private let lines = ["Dough", "2 cups flour", "1 cup water", "Method", "Mix flour and water.", "Rest for 20 minutes."]
    private var plan: RecipeImportPlan {
        .init(items: [
            .init(line: 0, role: .header, sectionLine: nil),
            .init(line: 1, role: .ingredient, sectionLine: 0),
            .init(line: 2, role: .ingredient, sectionLine: 0),
            .init(line: 3, role: .header, sectionLine: nil),
            .init(line: 4, role: .step, sectionLine: nil),
            .init(line: 5, role: .step, sectionLine: nil)
        ])
    }

    func testGroundedSectionsPreserveSourceAndTimers() async throws {
        let parser = TextRecipeParser(importStructurer: StubImportStructurer(plan: plan))
        let recipe = try await parser.parse(lines: lines, sourceURL: URL(string: "https://example.com/bread"),
                                            sourceTitle: "Bread", imageURL: nil, preferredTitle: "Bread")
        XCTAssertEqual(recipe.ingredients.count, 2)
        XCTAssertEqual(recipe.ingredients.map(\.section), ["Dough", "Dough"])
        XCTAssertEqual(recipe.steps.map(\.text), ["Mix flour and water.", "Rest for 20 minutes."])
        XCTAssertFalse(recipe.steps[1].timers.isEmpty)
        XCTAssertEqual(recipe.sourceURL?.host, "example.com")
        let rows = try XCTUnwrap(plan.validatedRows(source: lines, baseline: []))
        XCTAssertEqual(rows.map(\.text), lines)
    }

    func testRejectsMissingDuplicateAndOutOfRangeReferences() {
        XCTAssertNil(RecipeImportPlan(items: Array(plan.items.dropLast())).validatedRows(source: lines, baseline: []))
        var duplicate = plan.items
        duplicate[5] = duplicate[4]
        XCTAssertNil(RecipeImportPlan(items: duplicate).validatedRows(source: lines, baseline: []))
        var outOfRange = plan.items
        outOfRange[5] = .init(line: 99, role: .step, sectionLine: nil)
        XCTAssertNil(RecipeImportPlan(items: outOfRange).validatedRows(source: lines, baseline: []))
    }

    func testRejectsInventedOrFutureSectionAndDiscardedContent() {
        for heading in [99, 2, 4] {
            var items = plan.items
            items[1] = .init(line: 1, role: .ingredient, sectionLine: heading)
            XCTAssertNil(RecipeImportPlan(items: items).validatedRows(source: lines, baseline: []))
        }
        var items = plan.items
        items[2] = .init(line: 2, role: .junk, sectionLine: nil)
        XCTAssertNil(RecipeImportPlan(items: items).validatedRows(source: lines, baseline: [
            .init(index: 2, text: lines[2], label: .ingredient)
        ]))
    }

    func testUnavailableAndFailureKeepLocalResult() async throws {
        let text = "Bread\nIngredients:\n2 cups flour\n1 cup water\nInstructions:\nMix flour and water.\nRest for 20 minutes."
        let baseline = try await TextRecipeParser().parse(from: text)
        for stub in [StubImportStructurer(plan: nil), StubImportStructurer(plan: nil, fails: true), StubImportStructurer(plan: plan)] {
            let actual = try await TextRecipeParser(importStructurer: stub).parse(from: text)
            XCTAssertEqual(actual.ingredients.map(\.name), baseline.ingredients.map(\.name))
            XCTAssertEqual(actual.ingredients.map(\.quantity), baseline.ingredients.map(\.quantity))
            XCTAssertEqual(actual.steps.map(\.text), baseline.steps.map(\.text))
        }
    }

    func testCloudCanCorrectAFalseIngredientIntoASectionHeading() async throws {
        let source = ["Dough", "2 cups flour", "1 cup water", "Filling", "3 apples", "Instructions", "Mix flour and water.", "Fill with apples and bake for 25 minutes."]
        let plan = RecipeImportPlan(items: [
            .init(line: 0, role: .header, sectionLine: nil),
            .init(line: 1, role: .ingredient, sectionLine: 0),
            .init(line: 2, role: .ingredient, sectionLine: 0),
            .init(line: 3, role: .header, sectionLine: nil),
            .init(line: 4, role: .ingredient, sectionLine: 3),
            .init(line: 5, role: .header, sectionLine: nil),
            .init(line: 6, role: .step, sectionLine: 5),
            .init(line: 7, role: .step, sectionLine: 5)
        ])
        let recipe = try await TextRecipeParser(importStructurer: StubImportStructurer(plan: plan))
            .parse(lines: source, sourceURL: URL(string: "https://example.com/pastry"), sourceTitle: "Pastry", imageURL: nil)
        XCTAssertEqual(recipe.ingredients.count, 3)
        XCTAssertEqual(recipe.ingredients.map(\.section), ["Dough", "Dough", "Filling"])
        XCTAssertEqual(recipe.steps.map(\.section), [nil, nil])
        var bad = plan.items
        bad[1] = .init(line: 1, role: .header, sectionLine: nil)
        XCTAssertNil(RecipeImportPlan(items: bad).validatedRows(source: source, baseline: [
            .init(index: 1, text: source[1], label: .ingredient)
        ]))
    }

    func testCancellationPropagates() async throws {
        let parser = TextRecipeParser(importStructurer: CancellingImportStructurer())
        do {
            _ = try await parser.parse(from: "Bread\n1 cup flour\nMix flour with water.")
            XCTFail("Cancelled import must not produce a recipe")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
    }
}

private struct StubImportStructurer: RecipeImportStructuring {
    let plan: RecipeImportPlan?
    var fails = false
    func structure(lines: [String]) async throws -> RecipeImportPlan? {
        if fails { throw URLError(.notConnectedToInternet) }
        return plan
    }
}
private struct CancellingImportStructurer: RecipeImportStructuring {
    func structure(lines: [String]) async throws -> RecipeImportPlan? { throw CancellationError() }
}
