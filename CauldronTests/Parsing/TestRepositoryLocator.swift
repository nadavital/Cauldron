import Foundation

enum TestRepositoryLocator {
    private static func hasRequiredEntries(
        at root: URL,
        requiredEntries: [String],
        fileManager: FileManager
    ) -> Bool {
        requiredEntries.allSatisfy { entry in
            fileManager.fileExists(atPath: root.appendingPathComponent(entry).path)
        }
    }

    private static func ancestorChain(from start: URL) -> [URL] {
        var result: [URL] = []
        var candidate = start.standardizedFileURL
        while true {
            result.append(candidate)
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path {
                break
            }
            candidate = parent
        }
        return result
    }

    static func findRepositoryRoot(
        startingAt filePath: String = #filePath,
        requiredEntries: [String]
    ) throws -> URL {
        let fileManager = FileManager.default

        var startingPoints: [URL] = []
        startingPoints.append(URL(fileURLWithPath: filePath).deletingLastPathComponent())
        startingPoints.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))

        let environment = ProcessInfo.processInfo.environment
        let environmentKeys = [
            "CI_WORKSPACE",
            "GITHUB_WORKSPACE",
            "SRCROOT",
            "PROJECT_DIR",
            "PWD",
            "BUILD_WORKSPACE_DIRECTORY",
            "XCTestConfigurationFilePath"
        ]
        for key in environmentKeys {
            if let value = environment[key], !value.isEmpty {
                startingPoints.append(URL(fileURLWithPath: value))
            }
        }

        // Common CI checkout roots.
        startingPoints.append(URL(fileURLWithPath: "/Volumes/workspace/repository"))
        startingPoints.append(URL(fileURLWithPath: "/Volumes/workspace/repository/Cauldron"))

        var seen = Set<String>()
        var candidates: [URL] = []
        for start in startingPoints {
            for ancestor in ancestorChain(from: start) {
                if seen.insert(ancestor.path).inserted {
                    candidates.append(ancestor)
                }
            }
        }

        let nestedNames = ["repository", "repo", "Cauldron", "source"]
        for candidate in candidates {
            let probeRoots = [candidate] + nestedNames.map { candidate.appendingPathComponent($0) }
            for probe in probeRoots {
                if hasRequiredEntries(at: probe, requiredEntries: requiredEntries, fileManager: fileManager) {
                    return probe
                }
            }
        }

        let inspected = candidates.prefix(8).map(\.path).joined(separator: ", ")
        let message = "Unable to locate repository root from #filePath (inspected: \(inspected))"
        throw NSError(
            domain: "TestRepositoryLocator",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
