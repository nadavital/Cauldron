import XCTest
import UniformTypeIdentifiers
@testable import Cauldron

final class ReleaseConfigurationTests: XCTestCase {
    func testPortableLibraryArchiveHasAStableFilenameType() throws {
        XCTAssertEqual(UTType.cauldronLibraryArchive.preferredFilenameExtension, "cauldron")
        XCTAssertTrue(UTType.cauldronLibraryArchive.conforms(to: .json))
        XCTAssertTrue(LibraryArchiveDocument.readableContentTypes.contains(.json))

        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let declarations = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let archive = try XCTUnwrap(
            declarations.first { $0["UTTypeIdentifier"] as? String == "Nadav.Cauldron.library-archive" }
        )
        XCTAssertEqual(archive["UTTypeConformsTo"] as? [String], ["public.json"])
        let tags = try XCTUnwrap(archive["UTTypeTagSpecification"] as? [String: Any])
        XCTAssertEqual(tags["public.filename-extension"] as? [String], ["cauldron"])

        let importedDeclarations = try XCTUnwrap(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let legacyArchive = try XCTUnwrap(
            importedDeclarations.first {
                $0["UTTypeIdentifier"] as? String == "app.cauldron.library-archive"
            }
        )
        XCTAssertEqual(legacyArchive["UTTypeConformsTo"] as? [String], ["public.json"])
    }

    func testArchivePickerCancellationIsNotReportedAsFailure() {
        XCTAssertTrue(UserProfileView.archivePickerWasCancelled(CocoaError(.userCancelled)))
        XCTAssertFalse(UserProfileView.archivePickerWasCancelled(CocoaError(.fileReadCorruptFile)))
    }

    func testPartialArchiveRestoreMessageExplainsSafeRetry() {
        var report = LibraryArchiveService.RestoreReport()
        report.recipesInserted = 2
        report.collectionsUpdated = 1

        XCTAssertTrue(UserProfileView.archiveRestoreDidChangeLibrary(report))
        let message = UserProfileView.archivePartialRestoreMessage(report)
        XCTAssertTrue(message.contains("2 added and 1 updated"))
        XCTAssertTrue(message.contains("safe to select the same backup again"))
    }

}
