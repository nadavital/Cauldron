import XCTest

final class ReleaseConfigurationTests: XCTestCase {
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
