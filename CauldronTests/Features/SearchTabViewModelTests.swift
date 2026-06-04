//
//  SearchTabViewModelTests.swift
//  CauldronTests
//
//  Tests for SearchTabViewModel's deterministic, synchronous state logic:
//  category selection and people-search input handling. These avoid the
//  debounced/network paths so they stay fast and non-flaky.
//

import XCTest
@testable import Cauldron

/// Tests for SearchTabViewModel.
/// Note: ViewModels are created as local variables to avoid @Observable + @MainActor
/// deinitialization issues during test teardown (Swift issue #85221).
@MainActor
final class SearchTabViewModelTests: XCTestCase {

    private func makeViewModel() -> SearchTabViewModel {
        SearchTabViewModel(dependencies: DependencyContainer.preview())
    }

    // MARK: - Category Selection

    func testToggleCategorySelectsUnselectedCategory() {
        let viewModel = makeViewModel()
        XCTAssertFalse(viewModel.selectedCategories.contains(.dinner))

        viewModel.toggleCategory(.dinner)

        XCTAssertTrue(viewModel.selectedCategories.contains(.dinner))
    }

    func testToggleCategoryTwiceDeselectsCategory() {
        let viewModel = makeViewModel()

        viewModel.toggleCategory(.dessert)
        XCTAssertTrue(viewModel.selectedCategories.contains(.dessert))

        viewModel.toggleCategory(.dessert)
        XCTAssertFalse(viewModel.selectedCategories.contains(.dessert))
    }

    func testMultipleCategoriesCanBeSelectedIndependently() {
        let viewModel = makeViewModel()

        viewModel.toggleCategory(.breakfast)
        viewModel.toggleCategory(.vegan)
        viewModel.toggleCategory(.italian)

        XCTAssertEqual(viewModel.selectedCategories, [.breakfast, .vegan, .italian])

        // Removing one leaves the others intact.
        viewModel.toggleCategory(.vegan)
        XCTAssertEqual(viewModel.selectedCategories, [.breakfast, .italian])
    }

    // MARK: - People Search

    func testUpdatePeopleSearchWithEmptyQueryClearsResults() {
        let viewModel = makeViewModel()
        viewModel.peopleSearchResults = [User(username: "stale", displayName: "Stale Result")]

        viewModel.updatePeopleSearch("")

        XCTAssertTrue(viewModel.peopleSearchResults.isEmpty)
    }

    func testUpdatePeopleSearchWithWhitespaceOnlyQueryClearsResults() {
        let viewModel = makeViewModel()
        viewModel.peopleSearchResults = [User(username: "stale", displayName: "Stale Result")]

        // Whitespace trims to empty, so results should be cleared.
        viewModel.updatePeopleSearch("   ")

        XCTAssertTrue(viewModel.peopleSearchResults.isEmpty)
    }

    // MARK: - Recipe Search Input

    func testUpdateRecipeSearchWithShortQueryClearsPublicRecipes() {
        let viewModel = makeViewModel()
        viewModel.publicRecipes = [Recipe(title: "Stale Public Recipe", ingredients: [], steps: [])]

        // A single-character query is below the minimum search length and
        // should immediately clear stale public results.
        viewModel.updateRecipeSearch("a")

        XCTAssertTrue(viewModel.publicRecipes.isEmpty)
    }

    // MARK: - Initial State

    func testInitialStateIsEmpty() {
        let viewModel = makeViewModel()

        XCTAssertTrue(viewModel.selectedCategories.isEmpty)
        XCTAssertTrue(viewModel.peopleSearchResults.isEmpty)
        XCTAssertTrue(viewModel.recipeSearchResults.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertFalse(viewModel.isLoadingPeople)
    }
}
