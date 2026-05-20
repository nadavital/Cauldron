//
//  RecipeEditorViewModelRelatedRecipesTests.swift
//  CauldronTests
//

import Foundation
import XCTest
@testable import Cauldron

@MainActor
final class RecipeEditorViewModelRelatedRecipesTests: XCTestCase {
    private var currentUserId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        CurrentUserSession.shared.signOut()
        currentUserId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "editor",
                displayName: "Recipe Editor",
                createdAt: Date()
            )
        )
    }

    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        currentUserId = nil
        try await super.tearDown()
    }

    func testSavePreservesUnresolvedRelatedRecipeIds() async throws {
        let dependencies = DependencyContainer.preview()
        let relatedRecipeId = UUID()
        let recipe = makeRecipe(
            title: "Lemon Pasta",
            relatedRecipeIds: [relatedRecipeId]
        )

        try await dependencies.recipeRepository.create(recipe, skipCloudSync: true)

        let viewModel = RecipeEditorViewModel(
            dependencies: dependencies,
            existingRecipe: recipe
        )

        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(viewModel.relatedRecipes.isEmpty)
        let didSave = await viewModel.save()
        XCTAssertTrue(didSave)

        let savedRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id)
        XCTAssertEqual(savedRecipe?.relatedRecipeIds, [relatedRecipeId])
    }

    func testSaveUsesCanonicalIdForResolvedOwnedRelatedCopy() async throws {
        let dependencies = DependencyContainer.preview()
        let canonicalRelatedRecipeId = UUID()
        let ownedCopy = makeRecipe(
            id: UUID(),
            title: "Saved Sauce",
            originalRecipeId: canonicalRelatedRecipeId,
            followsSourceUpdates: true
        )
        let recipe = makeRecipe(
            title: "Dinner Plate",
            relatedRecipeIds: [canonicalRelatedRecipeId]
        )

        try await dependencies.recipeRepository.create(ownedCopy, skipCloudSync: true)
        try await dependencies.recipeRepository.create(recipe, skipCloudSync: true)

        let viewModel = RecipeEditorViewModel(
            dependencies: dependencies,
            existingRecipe: recipe
        )

        await waitUntil {
            viewModel.relatedRecipes.count == 1
        }

        XCTAssertEqual(viewModel.relatedRecipes.map(\.id), [ownedCopy.id])
        let didSave = await viewModel.save()
        XCTAssertTrue(didSave)

        let savedRecipe = try await dependencies.recipeRepository.fetch(id: recipe.id)
        XCTAssertEqual(savedRecipe?.relatedRecipeIds, [canonicalRelatedRecipeId])
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        originalRecipeId: UUID? = nil,
        followsSourceUpdates: Bool = false,
        relatedRecipeIds: [UUID] = []
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: [
                Ingredient(name: "Salt", quantity: nil)
            ],
            steps: [
                CookStep(index: 0, text: "Season.", timers: [])
            ],
            ownerId: currentUserId,
            originalRecipeId: originalRecipeId,
            sourceRecipeUpdatedAt: originalRecipeId == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000),
            followsSourceUpdates: followsSourceUpdates,
            relatedRecipeIds: relatedRecipeIds
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
