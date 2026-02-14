import Foundation
import XCTest

final class LabParityGateTests: XCTestCase {

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
            domain: "LabParityGateTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate parity report in any expected path: \(relativePaths.joined(separator: ", "))"]
        )
    }

    func testLabelParityGatePassesThreshold() throws {
        let payload = try loadJSON(atAny: [
            "tools/recipe_schema_model/artifacts/parity_labels.json",
            "CauldronTests/Fixtures/RecipeSchema/artifacts/parity_labels.json"
        ])
        let mismatchRate = payload["mismatch_rate"] as? Double ?? 1.0
        let threshold = payload["threshold"] as? Double ?? 0.005
        XCTAssertLessThanOrEqual(
            mismatchRate,
            threshold,
            "Label parity gate failed: mismatch_rate=\(mismatchRate), threshold=\(threshold)"
        )
    }

    func testAssemblyParityGatePassesThreshold() throws {
        let payload = try loadJSON(atAny: [
            "tools/recipe_schema_model/artifacts/parity_assembly.json",
            "CauldronTests/Fixtures/RecipeSchema/artifacts/parity_assembly.json"
        ])
        let mismatchDocs = payload["mismatch_docs"] as? Int ?? Int.max
        let maxMismatchDocs = payload["max_mismatch_docs"] as? Int ?? 2
        XCTAssertLessThanOrEqual(
            mismatchDocs,
            maxMismatchDocs,
            "Assembly parity gate failed: mismatch_docs=\(mismatchDocs), max=\(maxMismatchDocs)"
        )
    }
}
