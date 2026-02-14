import Foundation
import XCTest
@testable import Cauldron

final class ModelRecipeAssemblerParityTests: XCTestCase {

    func testBananaBreadFixtureMatchesPythonAssemblyShape() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/RecipeSchema/lines/banana_bread.lines.jsonl")

        let raw = try String(contentsOf: fixtureURL, encoding: .utf8)
        let rows = raw
            .split(separator: "\n")
            .compactMap { line -> ModelRecipeAssembler.Row? in
                guard let data = String(line).data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = payload["text"] as? String,
                      let labelRaw = payload["label"] as? String,
                      let label = RecipeLineLabel(rawValue: labelRaw) else {
                    return nil
                }
                let index = payload["line_index"] as? Int ?? 0
                return ModelRecipeAssembler.Row(index: index, text: text, label: label)
            }

        let assembler = ModelRecipeAssembler()
        let assembled = assembler.assemble(rows: rows)

        XCTAssertEqual(assembled.ingredients.count, 2)
        XCTAssertEqual(assembled.steps.count, 3)
        XCTAssertEqual(assembled.noteLines.count, 1)
        XCTAssertEqual(assembled.title, "Banana Bread")
    }

    func testTipsAndMetadataRouteToNotesAndRecipeFields() {
        let rows: [ModelRecipeAssembler.Row] = [
            .init(index: 0, text: "Weeknight Pasta", label: .title),
            .init(index: 1, text: "Serves 4", label: .note),
            .init(index: 2, text: "Total time: 45 minutes", label: .note),
            .init(index: 3, text: "2 cups pasta", label: .ingredient),
            .init(index: 4, text: "1 tbsp olive oil", label: .ingredient),
            .init(index: 5, text: "Cook pasta for 10 minutes", label: .step),
            .init(index: 6, text: "Tips and Variations: Add chili flakes", label: .note)
        ]

        let assembler = ModelRecipeAssembler()
        let assembled = assembler.assemble(rows: rows)

        XCTAssertEqual(assembled.yields, "4 servings")
        XCTAssertEqual(assembled.totalMinutes, 45)
        XCTAssertEqual(assembled.ingredients.count, 2)
        XCTAssertEqual(assembled.steps.count, 1)
        XCTAssertEqual(assembled.noteLines.count, 1)
        XCTAssertTrue(assembled.noteLines[0].contains("Add chili flakes"))
    }
}
