import Foundation

enum TestRepositoryLocator {
    static func findRepositoryRoot(
        startingAt filePath: String = #filePath,
        requiredEntries: [String]
    ) throws -> URL {
        let fileManager = FileManager.default

        var startingPoints: [URL] = [URL(fileURLWithPath: filePath).deletingLastPathComponent()]

        let environment = ProcessInfo.processInfo.environment
        let environmentKeys = ["CI_WORKSPACE", "GITHUB_WORKSPACE", "SRCROOT", "PROJECT_DIR", "PWD"]
        for key in environmentKeys {
            if let value = environment[key], !value.isEmpty {
                startingPoints.append(URL(fileURLWithPath: value))
            }
        }

        for start in startingPoints {
            var candidate = start.standardizedFileURL
            while true {
                let hasAllEntries = requiredEntries.allSatisfy { entry in
                    fileManager.fileExists(atPath: candidate.appendingPathComponent(entry).path)
                }
                if hasAllEntries {
                    return candidate
                }

                let parent = candidate.deletingLastPathComponent()
                if parent.path == candidate.path {
                    break
                }
                candidate = parent
            }
        }

        let message = "Unable to locate repository root from #filePath"
        throw NSError(
            domain: "TestRepositoryLocator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
