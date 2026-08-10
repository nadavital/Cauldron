import Foundation
import XCTest
@testable import Cauldron

final class PersistenceStoreRecoveryTests: XCTestCase {
    func testQuarantineMovesStoreAndSidecarsButPreservesUnrelatedFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = root.appendingPathComponent("default.store")
        let artifacts = [store, URL(fileURLWithPath: store.path + "-wal"), URL(fileURLWithPath: store.path + "-shm")]
        for (index, artifact) in artifacts.enumerated() {
            try Data("artifact-\(index)".utf8).write(to: artifact)
        }
        let unrelated = root.appendingPathComponent("recipe-image.jpg")
        try Data("image".utf8).write(to: unrelated)

        let report = try PersistenceStoreRecovery.quarantineStore(
            at: store,
            recoveredAt: Date(timeIntervalSince1970: 1_700_000_000),
            identifier: UUID(uuidString: "018f9344-54ff-42fc-83a8-c2a92e2d1b10")!
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        for artifact in artifacts {
            XCTAssertFalse(FileManager.default.fileExists(atPath: artifact.path))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: report.backupDirectory.appendingPathComponent(artifact.lastPathComponent).path
            ))
        }
    }

    func testQuarantineRefusesToRecoverWithoutPrimaryStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PersistenceRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = root.appendingPathComponent("default.store")
        try Data().write(to: URL(fileURLWithPath: store.path + "-wal"))

        XCTAssertThrowsError(try PersistenceStoreRecovery.quarantineStore(at: store))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.path + "-wal"))
    }
}
