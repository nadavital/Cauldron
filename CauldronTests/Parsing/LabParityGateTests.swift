import Foundation
import XCTest

final class LabParityGateTests: XCTestCase {

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
            domain: "LabParityGateTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(resourceName).json in bundle or fallback paths"]
        )
    }

    func testLabelParityGatePassesThreshold() throws {
        let payload = try loadJSON(resourceName: "parity_labels")
        let mismatchRate = payload["mismatch_rate"] as? Double ?? 1.0
        let threshold = payload["threshold"] as? Double ?? 0.005
        XCTAssertLessThanOrEqual(
            mismatchRate,
            threshold,
            "Label parity gate failed: mismatch_rate=\(mismatchRate), threshold=\(threshold)"
        )
    }

    func testAssemblyParityGatePassesThreshold() throws {
        let payload = try loadJSON(resourceName: "parity_assembly")
        let mismatchDocs = payload["mismatch_docs"] as? Int ?? Int.max
        let maxMismatchDocs = payload["max_mismatch_docs"] as? Int ?? 2
        XCTAssertLessThanOrEqual(
            mismatchDocs,
            maxMismatchDocs,
            "Assembly parity gate failed: mismatch_docs=\(mismatchDocs), max=\(maxMismatchDocs)"
        )
    }
}
