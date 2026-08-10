import XCTest
import CloudKit
import SwiftUI
@testable import Cauldron

final class PendingShareManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PendingShareManagerTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testPendingURLSurvivesManagerRecreationAndIsConsumedOnce() async throws {
        let suiteName = "PendingShareManagerTests.persistence.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        firstDefaults.removePersistentDomain(forName: suiteName)
        defer { firstDefaults.removePersistentDomain(forName: suiteName) }

        let url = try XCTUnwrap(URL(string: "cauldron://import/recipe/7DBEAFFD-895F-43B1-9985-463F36EA5D8C"))
        let firstManager = PendingShareManager(defaults: firstDefaults)
        await firstManager.setPendingURL(url)

        let secondManager = PendingShareManager(defaults: UserDefaults(suiteName: suiteName))
        let peekedURL = await secondManager.peekPendingURL()
        XCTAssertEqual(peekedURL, url)

        let consumedURL = await secondManager.consumePendingURL()

        let consumedAgain = await secondManager.consumePendingURL()
        XCTAssertEqual(consumedURL, url)
        XCTAssertNil(consumedAgain)
    }

    func testClearOnlyRemovesMatchingPendingURL() async throws {
        let url = try XCTUnwrap(URL(string: "https://cauldron-f900a.web.app/recipe/one"))
        let differentURL = try XCTUnwrap(URL(string: "https://cauldron-f900a.web.app/recipe/two"))
        let manager = PendingShareManager(defaults: defaults)

        await manager.setPendingURL(url)
        await manager.clearPendingURL(matching: differentURL)
        let retainedURL = await manager.consumePendingURL()
        XCTAssertEqual(retainedURL, url)

        await manager.setPendingURL(url)
        await manager.clearPendingURL(matching: url)
        let clearedURL = await manager.consumePendingURL()
        XCTAssertNil(clearedURL)
    }

    func testNewestQueuedURLSupersedesOlderPendingURL() async throws {
        let firstURL = try XCTUnwrap(URL(string: "https://cauldron-f900a.web.app/recipe/first"))
        let newestURL = try XCTUnwrap(URL(string: "https://cauldron-f900a.web.app/recipe/newest"))
        let manager = PendingShareManager(defaults: defaults)

        await manager.setPendingURL(firstURL)
        await manager.setPendingURL(newestURL)

        let pendingURL = await manager.peekPendingURL()
        XCTAssertEqual(pendingURL, newestURL)
    }

    func testLaunchSplashIsSuppressedForPendingOrActiveExternalShare() {
        XCTAssertTrue(ContentView.shouldPresentLaunchSplash(
            hasPendingExternalShare: false,
            isRoutingExternalShare: false
        ))
        XCTAssertFalse(ContentView.shouldPresentLaunchSplash(
            hasPendingExternalShare: true,
            isRoutingExternalShare: false
        ))
        XCTAssertFalse(ContentView.shouldPresentLaunchSplash(
            hasPendingExternalShare: false,
            isRoutingExternalShare: true
        ))
    }

    func testOnlyTransientNetworkShareErrorsAreRetried() {
        XCTAssertTrue(ContentView.isTransientShareError(
            ExternalShareError.networkError(URLError(.notConnectedToInternet))
        ))
        XCTAssertTrue(ContentView.isTransientShareError(URLError(.timedOut)))
        XCTAssertTrue(ContentView.isTransientShareError(ExternalShareError.temporarilyUnavailable))
        XCTAssertTrue(ContentView.isTransientShareError(CKError(.requestRateLimited)))
        XCTAssertFalse(ContentView.isTransientShareError(
            ExternalShareError.networkError(URLError(.badURL))
        ))
        XCTAssertFalse(ContentView.isTransientShareError(URLError(.unsupportedURL)))
        XCTAssertFalse(ContentView.isTransientShareError(ExternalShareError.invalidResponse))
        XCTAssertFalse(ContentView.isTransientShareError(ExternalShareError.invalidRecipe))
    }

    func testPendingShareRetriesOnlyAfterReturningActiveWhenReady() {
        XCTAssertFalse(ContentView.shouldRetryPendingShare(
            scenePhase: .background,
            isDataReady: true,
            hasActiveShare: false
        ))
        XCTAssertFalse(ContentView.shouldRetryPendingShare(
            scenePhase: .active,
            isDataReady: false,
            hasActiveShare: false
        ))
        XCTAssertFalse(ContentView.shouldRetryPendingShare(
            scenePhase: .active,
            isDataReady: true,
            hasActiveShare: true
        ))
        XCTAssertTrue(ContentView.shouldRetryPendingShare(
            scenePhase: .active,
            isDataReady: true,
            hasActiveShare: false
        ))
    }
}
