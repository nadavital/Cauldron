import Foundation

struct PersistenceRecoveryReport: Equatable, Sendable {
    let backupDirectory: URL
    let recoveredAt: Date
}

enum PersistenceStoreRecovery {
    enum RecoveryError: LocalizedError {
        case storeArtifactsMissing(URL)
        case backupDirectoryNotEmpty(URL)

        var errorDescription: String? {
            switch self {
            case .storeArtifactsMissing(let url):
                "No persistent store artifacts were found at \(url.path)."
            case .backupDirectoryNotEmpty(let url):
                "The recovery destination is not empty: \(url.path)."
            }
        }
    }

    static func quarantineStore(
        at storeURL: URL,
        fileManager: FileManager = .default,
        recoveredAt: Date = Date(),
        identifier: UUID = UUID()
    ) throws -> PersistenceRecoveryReport {
        let parentDirectory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent
        let artifacts = try fileManager.contentsOfDirectory(
            at: parentDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { url in
            let name = url.lastPathComponent
            return name == storeName ||
                name.hasPrefix(storeName + "-") ||
                name.hasPrefix(storeName + "_")
        }

        guard artifacts.contains(where: { $0.lastPathComponent == storeName }) else {
            throw RecoveryError.storeArtifactsMissing(storeURL)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: recoveredAt)
            .replacingOccurrences(of: ":", with: "-")
        let backupDirectory = parentDirectory
            .appendingPathComponent("Cauldron Store Backups", isDirectory: true)
            .appendingPathComponent("\(timestamp)-\(identifier.uuidString)", isDirectory: true)

        if fileManager.fileExists(atPath: backupDirectory.path) {
            let existing = try fileManager.contentsOfDirectory(atPath: backupDirectory.path)
            guard existing.isEmpty else {
                throw RecoveryError.backupDirectoryNotEmpty(backupDirectory)
            }
        } else {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
        }

        do {
            for artifact in artifacts {
                try fileManager.moveItem(
                    at: artifact,
                    to: backupDirectory.appendingPathComponent(artifact.lastPathComponent)
                )
            }
        } catch {
            // Roll back any partial move so a failed recovery never strands a
            // usable store across two directories.
            for artifact in artifacts {
                let backupArtifact = backupDirectory.appendingPathComponent(artifact.lastPathComponent)
                guard fileManager.fileExists(atPath: backupArtifact.path),
                      !fileManager.fileExists(atPath: artifact.path) else { continue }
                try? fileManager.moveItem(at: backupArtifact, to: artifact)
            }
            throw error
        }

        return PersistenceRecoveryReport(
            backupDirectory: backupDirectory,
            recoveredAt: recoveredAt
        )
    }
}
