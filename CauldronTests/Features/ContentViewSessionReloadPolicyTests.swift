import XCTest
@testable import Cauldron

@MainActor
final class ContentViewSessionReloadPolicyTests: XCTestCase {
    func testVerifiedAccountSwitchRebuildsPreloadedData() {
        XCTAssertTrue(ContentView.shouldReloadSession(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: UUID(),
            currentUserId: UUID()
        ))
    }

    func testVerifiedSignOutClearsPriorAccountsPreloadedData() {
        XCTAssertTrue(ContentView.shouldReloadSession(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: UUID(),
            currentUserId: nil
        ))
    }

    func testExplicitSignOutLeavesRootInSettledOnboardingState() {
        let session = CurrentUserSession.shared
        session.currentUser = User(username: "departing", displayName: "Departing User")
        session.isInitialized = true
        session.needsOnboarding = false

        session.signOut()

        XCTAssertNil(session.currentUser)
        XCTAssertTrue(session.isInitialized)
        XCTAssertTrue(session.needsOnboarding)
        XCTAssertFalse(session.isAccountIdentityVerified)
    }

    func testReloadWaitsForIdentityVerificationAndInitialPreload() {
        let oldOwner = UUID()
        let newOwner = UUID()

        XCTAssertFalse(ContentView.shouldReloadSession(
            isInitialized: false,
            isDataReady: true,
            loadedUserId: oldOwner,
            currentUserId: newOwner
        ))
        XCTAssertFalse(ContentView.shouldReloadSession(
            isInitialized: true,
            isDataReady: false,
            loadedUserId: oldOwner,
            currentUserId: newOwner
        ))
    }

    func testUnchangedOwnerDoesNotReload() {
        let owner = UUID()
        XCTAssertFalse(ContentView.shouldReloadSession(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: owner,
            currentUserId: owner
        ))
    }

    func testMainTabRendersOnlyForMatchingVerifiedOwner() {
        let owner = UUID()

        XCTAssertTrue(ContentView.shouldRenderMainTab(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: owner,
            currentUserId: owner
        ))
    }

    func testMainTabDoesNotRenderPriorPreloadDuringAccountSwitch() {
        XCTAssertFalse(ContentView.shouldRenderMainTab(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: UUID(),
            currentUserId: UUID()
        ))
    }

    func testMainTabDoesNotRenderForSignedOutOrUnverifiedIdentity() {
        let owner = UUID()

        XCTAssertFalse(ContentView.shouldRenderMainTab(
            isInitialized: true,
            isDataReady: true,
            loadedUserId: owner,
            currentUserId: nil
        ))
        XCTAssertFalse(ContentView.shouldRenderMainTab(
            isInitialized: false,
            isDataReady: true,
            loadedUserId: owner,
            currentUserId: owner
        ))
        XCTAssertFalse(ContentView.shouldRenderMainTab(
            isInitialized: true,
            isDataReady: false,
            loadedUserId: owner,
            currentUserId: owner
        ))
    }
}
