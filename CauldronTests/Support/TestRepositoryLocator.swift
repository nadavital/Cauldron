import Foundation

enum TestRepositoryLocator {
    private static let projectMarker = "Cauldron.xcodeproj/project.pbxproj"

    static func root(
        filePath: String = #filePath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        var startingPoints = [
            URL(fileURLWithPath: filePath).deletingLastPathComponent(),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        ]

        for key in ["SRCROOT", "PROJECT_DIR"] {
            if let path = environment[key], !path.isEmpty {
                startingPoints.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }

        if let workspace = environment["CI_WORKSPACE"], !workspace.isEmpty {
            let workspaceURL = URL(fileURLWithPath: workspace, isDirectory: true)
            startingPoints.append(workspaceURL)
            startingPoints.append(workspaceURL.appendingPathComponent("repository", isDirectory: true))
        }

        for startingPoint in startingPoints {
            var candidate = startingPoint.standardizedFileURL
            while candidate.path != "/" {
                let marker = candidate.appendingPathComponent(projectMarker)
                if FileManager.default.fileExists(atPath: marker.path) {
                    return candidate
                }
                candidate.deleteLastPathComponent()
            }
        }

        let searchedPaths = startingPoints.map(\.path).joined(separator: ", ")
        throw NSError(
            domain: "TestRepositoryLocator",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not locate the repository root from: \(searchedPaths)"
            ]
        )
    }
}
