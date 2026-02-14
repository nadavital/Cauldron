import Foundation
import XCTest

final class LabParityGateTests: XCTestCase {

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

    func testLabelParityGatePassesThreshold() throws {
        let payload = try loadJSON(at: "tools/recipe_schema_model/artifacts/parity_labels.json")
        let mismatchRate = payload["mismatch_rate"] as? Double ?? 1.0
        let threshold = payload["threshold"] as? Double ?? 0.005
        XCTAssertLessThanOrEqual(
            mismatchRate,
            threshold,
            "Label parity gate failed: mismatch_rate=\(mismatchRate), threshold=\(threshold)"
        )
    }

    func testAssemblyParityGatePassesThreshold() throws {
        let payload = try loadJSON(at: "tools/recipe_schema_model/artifacts/parity_assembly.json")
        let mismatchDocs = payload["mismatch_docs"] as? Int ?? Int.max
        let maxMismatchDocs = payload["max_mismatch_docs"] as? Int ?? 2
        XCTAssertLessThanOrEqual(
            mismatchDocs,
            maxMismatchDocs,
            "Assembly parity gate failed: mismatch_docs=\(mismatchDocs), max=\(maxMismatchDocs)"
        )
    }
}
