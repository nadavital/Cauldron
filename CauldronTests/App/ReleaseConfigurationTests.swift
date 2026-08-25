import XCTest
import UniformTypeIdentifiers
@testable import Cauldron

final class ReleaseConfigurationTests: XCTestCase {
    func testPortableLibraryArchiveHasAStableFilenameType() throws {
        XCTAssertEqual(UTType.cauldronLibraryArchive.preferredFilenameExtension, "cauldron")
        XCTAssertTrue(UTType.cauldronLibraryArchive.conforms(to: .json))
        XCTAssertTrue(LibraryArchiveDocument.readableContentTypes.contains(.json))

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let infoURL = repositoryRoot.appendingPathComponent("Cauldron/Info.plist")
        let data = try Data(contentsOf: infoURL)
        let info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
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

    func testWidgetUsesSharedEntitlementsInEveryBuildConfiguration() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = repositoryRoot
            .appendingPathComponent("Cauldron.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)
        let assignment = "CODE_SIGN_ENTITLEMENTS = CauldronWidget/CauldronWidget.entitlements;"
        let assignmentCount = project.components(separatedBy: assignment).count - 1

        XCTAssertEqual(
            assignmentCount,
            2,
            "Debug and Release must both sign the widget with its shared capabilities."
        )

        let entitlementsURL = repositoryRoot
            .appendingPathComponent("CauldronWidget/CauldronWidget.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(
            entitlements["com.apple.security.application-groups"] as? [String],
            ["group.Nadav.Cauldron"]
        )
        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
            ["iCloud.Nadav.Cauldron"]
        )
    }

    func testAppRetainsBothHostedSharingAssociatedDomains() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for relativePath in ["Cauldron/Cauldron.entitlements", "Cauldron/CauldronCatalyst.entitlements"] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
            let entitlements = try XCTUnwrap(
                PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            )
            let domains = try XCTUnwrap(entitlements["com.apple.developer.associated-domains"] as? [String])
            XCTAssertTrue(domains.contains("applinks:cauldron-f900a.web.app"), relativePath)
            XCTAssertTrue(domains.contains("applinks:cauldron-f900a.firebaseapp.com"), relativePath)
        }
    }

    func testMacCatalystSandboxAllowsHostedServiceRequests() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let projectFile = repositoryRoot
            .appendingPathComponent("Cauldron.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)
        let assignment = "\"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]\" = Cauldron/CauldronCatalyst.entitlements;"
        let assignmentCount = project.components(separatedBy: assignment).count - 1

        XCTAssertEqual(
            assignmentCount,
            2,
            "Debug and Release must both sign the Catalyst app with its sandbox capabilities."
        )

        let entitlementsURL = repositoryRoot
            .appendingPathComponent("Cauldron/CauldronCatalyst.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.network.client"] as? Bool, true)
        XCTAssertEqual(
            entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
            ["iCloud.Nadav.Cauldron"]
        )
    }
}
