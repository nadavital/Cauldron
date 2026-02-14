import Foundation
import XCTest

final class ModelParityBaselineTests: XCTestCase {

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Parsing
            .deletingLastPathComponent() // CauldronTests
            .deletingLastPathComponent() // repo root
    }

    private func loadJSON(at relativePath: String) throws -> [String: Any] {
        let url = repositoryRoot().appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let value = try JSONSerialization.jsonObject(with: data, options: [])
        guard let payload = value as? [String: Any] else {
            XCTFail("Expected dictionary payload at \(relativePath)")
            return [:]
        }
        return payload
    }

    func testLabelParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(at: "tools/recipe_schema_model/artifacts/parity_labels.json")
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_label_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["total_lines"])
        XCTAssertNotNil(payload["mismatch_lines"])
        XCTAssertNotNil(payload["mismatch_rate"])
        XCTAssertNotNil(payload["fixtures"])
    }

    func testAssemblyParityReportExistsAndHasRequiredFields() throws {
        let payload = try loadJSON(at: "tools/recipe_schema_model/artifacts/parity_assembly.json")
        XCTAssertEqual(payload["report_type"] as? String, "swift_python_assembly_parity")
        XCTAssertNotNil(payload["total_fixtures"])
        XCTAssertNotNil(payload["mismatch_docs"])
        XCTAssertNotNil(payload["ingredient_mismatch_docs"])
        XCTAssertNotNil(payload["step_mismatch_docs"])
        XCTAssertNotNil(payload["note_mismatch_docs"])
        XCTAssertNotNil(payload["fixtures"])
    }
}
