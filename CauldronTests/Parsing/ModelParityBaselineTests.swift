import Foundation
import XCTest

final class ModelParityBaselineTests: XCTestCase {

    private func repositoryRoot() throws -> URL {
        try TestRepositoryLocator.findRepositoryRoot(
            startingAt: #filePath,
            requiredEntries: ["CauldronTests"]
        )
    }

    private func loadJSON(atAny relativePaths: [String]) throws -> [String: Any] {
        let root = try repositoryRoot()
        let fileManager = FileManager.default

        for relativePath in relativePaths {
            let url = root.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            let data = try Data(contentsOf: url)
            let value = try JSONSerialization.jsonObject(with: data, options: [])
            guard let payload = value as? [String: Any] else {
                XCTFail("Expected dictionary payload at \(relativePath)")
                return [:]
            }
            return payload
        }

        throw NSError(
            domain: "ModelParityBaselineTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate parity report in any expected path: \(relativePaths.joined(separator: ", "))"]
        )
    }

    func testLabelParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(atAny: [
            "tools/recipe_schema_model/artifacts/parity_labels.json",
            "CauldronTests/Fixtures/RecipeSchema/artifacts/parity_labels.json"
        ])
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_label_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["total_lines"])
        XCTAssertNotNil(payload["mismatch_lines"])
        XCTAssertNotNil(payload["mismatch_rate"])
        XCTAssertNotNil(payload["fixtures"])
    }

    func testAssemblyParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(atAny: [
            "tools/recipe_schema_model/artifacts/parity_assembly.json",
            "CauldronTests/Fixtures/RecipeSchema/artifacts/parity_assembly.json"
        ])
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_assembly_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["mismatch_docs"])
        XCTAssertNotNil(payload["ingredient_mismatch_docs"])
        XCTAssertNotNil(payload["step_mismatch_docs"])
        XCTAssertNotNil(payload["note_mismatch_docs"])
        XCTAssertNotNil(payload["fixtures"])
    }
}
