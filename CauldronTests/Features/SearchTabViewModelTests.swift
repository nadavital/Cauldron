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
        XCTAssertEqual(viewModel.timeFilter, .any)
        XCTAssertEqual(viewModel.sortOrder, .relevance)
        XCTAssertFalse(viewModel.hasActiveRefinements)
    }

    // MARK: - Filtering & Sorting

    private func makeGroup(title: String, minutes: Int?, created: Date = Date()) -> SearchRecipeGroup {
        SearchRecipeGroup(
            id: UUID(),
            primaryRecipe: Recipe(title: title, ingredients: [], steps: [], totalMinutes: minutes, createdAt: created),
            saveCount: 0,
            friendSavers: [],
            ownerTier: .apprentice,
            relevanceScore: 0
        )
    }

    func testTimeFilterKeepsOnlyMatchingRecipes() {
        let viewModel = makeViewModel()
        viewModel.recipeSearchResults = [
            makeGroup(title: "Quick", minutes: 10),
            makeGroup(title: "Medium", minutes: 40),
            makeGroup(title: "Unknown", minutes: nil)
        ]

        viewModel.timeFilter = .under15
        let titles = viewModel.displayedRecipeResults.map(\.primaryRecipe.title)
        XCTAssertEqual(titles, ["Quick"])
    }

    func testTimeFilterAnyKeepsEverythingIncludingUnknownTimes() {
        let viewModel = makeViewModel()
        viewModel.recipeSearchResults = [
            makeGroup(title: "A", minutes: 10),
            makeGroup(title: "B", minutes: nil)
        ]

        viewModel.timeFilter = .any
        XCTAssertEqual(viewModel.displayedRecipeResults.count, 2)
    }

    func testSortQuickestOrdersByTimeWithUnknownLast() {
        let viewModel = makeViewModel()
        viewModel.recipeSearchResults = [
            makeGroup(title: "Slow", minutes: 60),
            makeGroup(title: "Unknown", minutes: nil),
            makeGroup(title: "Fast", minutes: 10)
        ]

        viewModel.sortOrder = .quickest
        let titles = viewModel.displayedRecipeResults.map(\.primaryRecipe.title)
        XCTAssertEqual(titles, ["Fast", "Slow", "Unknown"])
    }

    func testSortAlphabeticalIsCaseInsensitive() {
        let viewModel = makeViewModel()
        viewModel.recipeSearchResults = [
            makeGroup(title: "banana bread", minutes: nil),
            makeGroup(title: "Apple Pie", minutes: nil)
        ]

        viewModel.sortOrder = .alphabetical
        let titles = viewModel.displayedRecipeResults.map(\.primaryRecipe.title)
        XCTAssertEqual(titles, ["Apple Pie", "banana bread"])
    }

    func testClearRefinementsResetsFilterAndSort() {
        let viewModel = makeViewModel()
        viewModel.timeFilter = .under30
        viewModel.sortOrder = .newest
        XCTAssertTrue(viewModel.hasActiveRefinements)

        viewModel.clearRefinements()
        XCTAssertEqual(viewModel.timeFilter, .any)
        XCTAssertEqual(viewModel.sortOrder, .relevance)
        XCTAssertFalse(viewModel.hasActiveRefinements)
    }
}
