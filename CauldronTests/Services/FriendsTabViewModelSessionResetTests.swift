//
//  FriendsTabViewModelSessionResetTests.swift
//  CauldronTests
//
//  Regression tests for FriendsTabViewModel session reset (cross-account leak
//  prevention). resetSessionState() must clear all browsed shared content so a
//  signed-out / switched user never sees the prior user's shared recipes,
//  collections, sections, or sharer tiers.
//
//  FriendsTabViewModel is a `.shared` singleton, so every test restores it to a
//  clean slate in tearDown to keep the rest of the suite green.
//

import XCTest
@testable import Cauldron

@MainActor
final class FriendsTabViewModelSessionResetTests: XCTestCase {

    override func tearDown() {
        // The view model is a process-wide singleton; never leak populated
        // state into other tests.
        FriendsTabViewModel.shared.resetSessionState()
        super.tearDown()
    }

    /// Populating the singleton's browsable state and then resetting must leave
    /// a fully clean slate across every published field.
    func testResetSessionStateClearsAllSharedContent() {
        let viewModel = FriendsTabViewModel.shared
        viewModel.resetSessionState() // start from a known clean state

        let sharer = TestFixtures.sampleUser1
        let sharedRecipe = SharedRecipe(
            recipe: TestFixtures.sampleRecipe,
            sharedBy: sharer,
            sharedAt: Date()
        )
        let collection = Collection(
            name: "Friend's Desserts",
            description: nil,
            userId: sharer.id,
            visibility: .publicRecipe
        )

        // Put it in a non-empty / loaded-looking state (everything achievable
        // offline via the public observable surface).
        viewModel.sharedRecipes = [sharedRecipe]
        viewModel.sharedCollections = [collection]
        viewModel.recentlyAdded = [sharedRecipe]
        viewModel.tagSections = [(tag: "dessert", recipes: [sharedRecipe])]
        viewModel.sharerTiers = [sharer.id: .apprentice]
        viewModel.isLoading = true
        viewModel.showSuccessAlert = true
        viewModel.showErrorAlert = true
        viewModel.alertMessage = "boom"

        // Precondition: state is populated.
        XCTAssertFalse(viewModel.sharedRecipes.isEmpty)
        XCTAssertFalse(viewModel.sharedCollections.isEmpty)

        // When the session is reset (sign-out / account change)
        viewModel.resetSessionState()

        // Then no prior-user state remains anywhere.
        XCTAssertTrue(viewModel.sharedRecipes.isEmpty)
        XCTAssertTrue(viewModel.sharedCollections.isEmpty)
        XCTAssertTrue(viewModel.recentlyAdded.isEmpty)
        XCTAssertTrue(viewModel.tagSections.isEmpty)
        XCTAssertTrue(viewModel.sharerTiers.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.showSuccessAlert)
        XCTAssertFalse(viewModel.showErrorAlert)
        XCTAssertTrue(viewModel.alertMessage.isEmpty)
    }

    /// resetSessionState() is idempotent: calling it from an already-clean state
    /// keeps every field empty (no crashes, no spurious flags).
    func testResetSessionStateIsIdempotent() {
        let viewModel = FriendsTabViewModel.shared
        viewModel.resetSessionState()
        viewModel.resetSessionState()

        XCTAssertTrue(viewModel.sharedRecipes.isEmpty)
        XCTAssertTrue(viewModel.sharedCollections.isEmpty)
        XCTAssertTrue(viewModel.recentlyAdded.isEmpty)
        XCTAssertTrue(viewModel.tagSections.isEmpty)
        XCTAssertTrue(viewModel.sharerTiers.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    /// loadSharedRecipes with no signed-in user must reset to a clean slate
    /// (the load path short-circuits to resetSessionState when userId is nil).
    /// This exercises the reset without requiring CloudKit.
    func testLoadWithNoCurrentUserResetsState() async {
        let viewModel = FriendsTabViewModel.shared
        let dependencies = DependencyContainer.preview()
        viewModel.configure(dependencies: dependencies)

        // Seed some stale state.
        viewModel.sharedRecipes = [
            SharedRecipe(recipe: TestFixtures.sampleRecipe, sharedBy: TestFixtures.sampleUser1)
        ]
        XCTAssertFalse(viewModel.sharedRecipes.isEmpty)

        // Ensure there is no signed-in user for this call, restoring afterward.
        let previousUser = CurrentUserSession.shared.currentUser
        CurrentUserSession.shared.signOut()
        defer {
            if let previousUser {
                CurrentUserSession.shared.replaceCurrentUserIfChanged(previousUser)
            }
        }

        await viewModel.loadSharedRecipes()

        XCTAssertTrue(viewModel.sharedRecipes.isEmpty, "Stale shared recipes must be cleared when no user is signed in")
        XCTAssertTrue(viewModel.sharedCollections.isEmpty)
        XCTAssertTrue(viewModel.recentlyAdded.isEmpty)
        XCTAssertTrue(viewModel.tagSections.isEmpty)
    }
}
