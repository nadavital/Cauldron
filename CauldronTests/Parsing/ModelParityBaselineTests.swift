import Foundation
import XCTest

final class ModelParityBaselineTests: XCTestCase {

    private func loadJSON(resourceName: String) throws -> [String: Any] {
        let fileManager = FileManager.default
        let bundle = Bundle(for: Self.self)

        if let bundledURL = bundle.url(forResource: resourceName, withExtension: "json") {
            let data = try Data(contentsOf: bundledURL)
            let value = try JSONSerialization.jsonObject(with: data, options: [])
            guard let payload = value as? [String: Any] else {
                XCTFail("Expected dictionary payload in bundled resource \(resourceName).json")
                return [:]
            }
            return payload
        }

        let fallbackPaths = [
            "CauldronTests/Fixtures/RecipeSchema/artifacts/\(resourceName).json",
            "tools/recipe_schema_model/artifacts/\(resourceName).json"
        ]
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)

        for relativePath in fallbackPaths {
            let url = cwd.appendingPathComponent(relativePath)
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
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(resourceName).json in bundle or fallback paths"]
        )
    }

    func testLabelParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(resourceName: "parity_labels")
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_label_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["total_lines"])
        XCTAssertNotNil(payload["mismatch_lines"])
        XCTAssertNotNil(payload["mismatch_rate"])
        XCTAssertNotNil(payload["fixtures"])
    }

    func testAssemblyParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(resourceName: "parity_assembly")
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_assembly_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["mismatch_docs"])
        XCTAssertNotNil(payload["ingredient_mismatch_docs"])
        XCTAssertNotNil(payload["step_mismatch_docs"])
        XCTAssertNotNil(payload["note_mismatch_docs"])
        XCTAssertNotNil(payload["fixtures"])
    }
}
