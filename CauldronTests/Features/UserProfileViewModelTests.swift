//
//  UserProfileViewModelTests.swift
//  CauldronTests
//
//  Tests for UserProfileViewModel's deterministic, synchronous logic:
//  current-user detection, recipe search filtering, and connection display limits.
//

import XCTest
@testable import Cauldron

/// Tests for UserProfileViewModel.
/// Note: ViewModels are created as local variables to avoid @Observable + @MainActor
/// deinitialization issues during test teardown (Swift issue #85221).
@MainActor
final class UserProfileViewModelTests: XCTestCase {

    private func makeViewModel(user: User) -> UserProfileViewModel {
        UserProfileViewModel(user: user, dependencies: DependencyContainer.preview())
    }

    private func makeSharedRecipe(title: String) -> SharedRecipe {
        SharedRecipe(
            recipe: Recipe(title: title, ingredients: [], steps: []),
            sharedBy: User(username: "owner", displayName: "Owner")
        )
    }

    // MARK: - Current User Detection

    func testIsCurrentUserFalseForDifferentUser() {
        let viewModel = makeViewModel(user: User(username: "someone", displayName: "Someone Else"))

        // A freshly-created random user id won't match the session's current user.
        XCTAssertFalse(viewModel.isCurrentUser)
    }

    func testIsCurrentUserTrueWhenIdMatchesSession() {
        // currentUserId is derived from the container's connectionManager, so the
        // probe and the view model under test must share the same container.
        let dependencies = DependencyContainer.preview()
        let sessionId = dependencies.connectionManager.currentUserId

        let viewModel = UserProfileViewModel(
            user: User(id: sessionId, username: "me", displayName: "Me"),
            dependencies: dependencies
        )

        XCTAssertTrue(viewModel.isCurrentUser)
    }

    // MARK: - Recipe Filtering

    func testFilteredRecipesMirrorsUserRecipesWhenSearchEmpty() {
        let viewModel = makeViewModel(user: User(username: "chef", displayName: "Chef"))

        viewModel.userRecipes = [
            makeSharedRecipe(title: "Pancakes"),
            makeSharedRecipe(title: "Waffles")
        ]

        XCTAssertEqual(viewModel.filteredRecipes.count, 2)
    }

    func testFilteredRecipesAppliesSearchQuery() {
        let viewModel = makeViewModel(user: User(username: "chef", displayName: "Chef"))
        viewModel.userRecipes = [
            makeSharedRecipe(title: "Chocolate Cake"),
            makeSharedRecipe(title: "Vanilla Pudding"),
            makeSharedRecipe(title: "Chocolate Mousse")
        ]

        viewModel.searchText = "chocolate"

        XCTAssertEqual(viewModel.filteredRecipes.count, 2)
        XCTAssertTrue(viewModel.filteredRecipes.allSatisfy {
            $0.recipe.title.lowercased().contains("chocolate")
        })
    }

    func testFilteredRecipesEmptyWhenNoMatch() {
        let viewModel = makeViewModel(user: User(username: "chef", displayName: "Chef"))
        viewModel.userRecipes = [makeSharedRecipe(title: "Pancakes")]

        viewModel.searchText = "sushi"

        XCTAssertTrue(viewModel.filteredRecipes.isEmpty)
    }

    // MARK: - Displayed Connections

    func testDisplayedConnectionsCapsAtSix() {
        let viewModel = makeViewModel(user: User(username: "chef", displayName: "Chef"))
        viewModel.connections = (0..<10).map { _ in
            ManagedConnection(
                connection: Connection(
                    fromUserId: UUID(),
                    toUserId: UUID(),
                    status: .accepted
                ),
                syncState: .synced
            )
        }

        XCTAssertEqual(viewModel.displayedConnections.count, 6)
    }

    func testDisplayedConnectionsReturnsAllWhenFewerThanSix() {
        let viewModel = makeViewModel(user: User(username: "chef", displayName: "Chef"))
        viewModel.connections = (0..<3).map { _ in
            ManagedConnection(
                connection: Connection(
                    fromUserId: UUID(),
                    toUserId: UUID(),
                    status: .accepted
                ),
                syncState: .synced
            )
        }

        XCTAssertEqual(viewModel.displayedConnections.count, 3)
    }
}
