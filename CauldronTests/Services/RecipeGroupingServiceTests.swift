//
//  RecipeGroupingServiceTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeGroupingServiceTests: XCTestCase {
    func testDeduplicateLocalLibraryRecipes_RemovesSelfSavedCopyWhenOriginalExists() {
        let currentUserId = UUID()
        let sourceId = UUID()
        let selfSavedCopyId = UUID()
        let original = makeRecipe(
            id: sourceId,
            title: "Roast Chicken",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["chicken"]
        )
        let selfSavedCopy = makeRecipe(
            id: selfSavedCopyId,
            title: "Roast Chicken",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["chicken"],
            originalRecipeId: sourceId
        )

        let recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
            [selfSavedCopy, original],
            currentUserId: currentUserId
        )

        XCTAssertEqual(recipes.map(\.id), [sourceId])
    }

    func testDeduplicateLocalLibraryRecipes_KeepsExternalSavedCopyWhenSourceIsNotOwnedLocally() {
        let currentUserId = UUID()
        let externalSourceId = UUID()
        let savedCopyId = UUID()
        let savedCopy = makeRecipe(
            id: savedCopyId,
            title: "Lentil Soup",
            ownerId: currentUserId,
            tags: ["Soup"],
            ingredients: ["lentils"],
            originalRecipeId: externalSourceId
        )

        let recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
            [savedCopy],
            currentUserId: currentUserId
        )

        XCTAssertEqual(recipes.map(\.id), [savedCopyId])
    }

    func testDeduplicateLocalLibraryRecipes_KeepsEditedForkOfExternalRecipe() {
        let currentUserId = UUID()
        let externalSourceId = UUID()
        let forkId = UUID()
        let editedFork = makeRecipe(
            id: forkId,
            title: "Spicy Lentil Soup",
            ownerId: currentUserId,
            tags: ["Soup"],
            ingredients: ["lentils"],
            originalRecipeId: externalSourceId,
            followsSourceUpdates: false
        )

        let recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
            [editedFork],
            currentUserId: currentUserId
        )

        XCTAssertEqual(recipes.map(\.id), [forkId])
    }

    func testDeduplicateLocalLibraryRecipes_CanHideRelatedReferenceRecipes() {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let parentId = UUID()
        let relatedId = UUID()
        let parent = makeRecipe(
            id: parentId,
            title: "Pasta Dinner",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["pasta"],
            relatedRecipeIds: [relatedId]
        )
        let related = makeRecipe(
            id: relatedId,
            title: "Tomato Sauce",
            ownerId: otherUserId,
            tags: ["Sauce"],
            ingredients: ["tomato"]
        )

        let recipes = RecipeGroupingService.deduplicateLocalLibraryRecipes(
            [related, parent],
            currentUserId: currentUserId,
            hidingRelatedRecipeReferences: true
        )

        XCTAssertEqual(recipes.map(\.id), [parentId])
    }

    func testHideRelatedRecipeReferences_UsesCanonicalSourceIdForOwnedCopies() {
        let currentUserId = UUID()
        let canonicalRelatedId = UUID()
        let ownedCopyId = UUID()
        let parent = makeRecipe(
            title: "Dinner Plate",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["rice"],
            relatedRecipeIds: [canonicalRelatedId]
        )
        let ownedRelatedCopy = makeRecipe(
            id: ownedCopyId,
            title: "Saved Sauce",
            ownerId: currentUserId,
            tags: ["Sauce"],
            ingredients: ["tomato"],
            originalRecipeId: canonicalRelatedId
        )

        let recipes = RecipeGroupingService.hideRelatedRecipeReferences([ownedRelatedCopy, parent])

        XCTAssertEqual(recipes.map(\.id), [parent.id])
    }

    func testHideRelatedRecipeReferences_KeepsCurrentUsersOwnedOriginalRecipe() {
        let currentUserId = UUID()
        let originalId = UUID()
        let parent = makeRecipe(
            title: "Dinner Plate",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["rice"],
            relatedRecipeIds: [originalId]
        )
        let ownedOriginal = makeRecipe(
            id: originalId,
            title: "Tomato Sauce",
            ownerId: currentUserId,
            tags: ["Sauce"],
            ingredients: ["tomato"]
        )

        let recipes = RecipeGroupingService.hideRelatedRecipeReferences(
            [ownedOriginal, parent],
            currentUserId: currentUserId
        )

        XCTAssertEqual(Set(recipes.map(\.id)), Set([ownedOriginal.id, parent.id]))
    }

    func testHideRelatedRecipeReferences_KeepsCurrentUsersOwnedSavedCopy() {
        let currentUserId = UUID()
        let sourceId = UUID()
        let parent = makeRecipe(
            title: "Dinner Plate",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["rice"],
            relatedRecipeIds: [sourceId]
        )
        let ownedSavedCopy = makeRecipe(
            title: "Saved Tomato Sauce",
            ownerId: currentUserId,
            tags: ["Sauce"],
            ingredients: ["tomato"],
            originalRecipeId: sourceId
        )

        let recipes = RecipeGroupingService.hideRelatedRecipeReferences(
            [ownedSavedCopy, parent],
            currentUserId: currentUserId
        )

        XCTAssertEqual(Set(recipes.map(\.id)), Set([ownedSavedCopy.id, parent.id]))
    }

    func testHideRelatedRecipeReferences_UsesLocalCopyIdForRemappedRelatedIds() {
        let currentUserId = UUID()
        let canonicalRelatedId = UUID()
        let ownedCopyId = UUID()
        let parent = makeRecipe(
            title: "Dinner Plate",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["rice"],
            relatedRecipeIds: [ownedCopyId]
        )
        let ownedRelatedCopy = makeRecipe(
            id: ownedCopyId,
            title: "Saved Sauce",
            ownerId: currentUserId,
            tags: ["Sauce"],
            ingredients: ["tomato"],
            originalRecipeId: canonicalRelatedId
        )

        let recipes = RecipeGroupingService.hideRelatedRecipeReferences([ownedRelatedCopy, parent])

        XCTAssertEqual(recipes.map(\.id), [parent.id])
    }

    func testHideRelatedRecipeReferences_DoesNotReturnEmptyLibraryForCycles() {
        let currentUserId = UUID()
        let firstId = UUID()
        let secondId = UUID()
        let first = makeRecipe(
            id: firstId,
            title: "First",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["rice"],
            relatedRecipeIds: [secondId]
        )
        let second = makeRecipe(
            id: secondId,
            title: "Second",
            ownerId: currentUserId,
            tags: ["Dinner"],
            ingredients: ["beans"],
            relatedRecipeIds: [firstId]
        )

        let recipes = RecipeGroupingService.hideRelatedRecipeReferences([first, second])

        XCTAssertEqual(Set(recipes.map(\.id)), Set([firstId, secondId]))
    }

    func testGroupAndRankRecipes_PrioritizesExactTitleMatch() {
        let currentUserId = UUID()
        let owner1 = UUID()
        let owner2 = UUID()

        let exact = makeRecipe(
            title: "Spicy Chili",
            ownerId: owner1,
            tags: ["Dinner"],
            ingredients: ["ground beef"]
        )
        let partial = makeRecipe(
            title: "Chili Oil Noodles",
            ownerId: owner2,
            tags: ["Noodles"],
            ingredients: ["noodles"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [partial, exact],
            friends: [],
            currentUserId: currentUserId,
            filterText: "Spicy Chili"
        )

        XCTAssertEqual(groups.first?.primaryRecipe.id, exact.id)
    }

    func testGroupAndRankRecipes_BoostsFriendSaves() {
        let currentUserId = UUID()
        let friendId = UUID()
        let owner2 = UUID()

        let friend = User(id: friendId, username: "friend", displayName: "Friend Chef")

        let baseId = UUID()
        let friendSavedCopy = makeRecipe(
            id: UUID(),
            title: "Tomato Soup",
            ownerId: friendId,
            tags: ["Soup"],
            ingredients: ["tomato"],
            originalRecipeId: baseId
        )
        let other = makeRecipe(
            title: "Tomato Soup",
            ownerId: owner2,
            tags: ["Soup"],
            ingredients: ["tomato"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [other, friendSavedCopy],
            friends: [friend],
            currentUserId: currentUserId,
            filterText: "tomato soup"
        )

        XCTAssertFalse(groups.isEmpty)
        XCTAssertFalse(groups[0].friendSavers.isEmpty)
    }

    func testGroupAndRankRecipes_MatchesIngredientTokens() {
        let currentUserId = UUID()
        let owner1 = UUID()
        let owner2 = UUID()

        let ingredientMatch = makeRecipe(
            title: "Simple Pasta",
            ownerId: owner1,
            tags: ["Dinner"],
            ingredients: ["garlic", "olive oil", "pasta"]
        )
        let noMatch = makeRecipe(
            title: "Banana Bread",
            ownerId: owner2,
            tags: ["Dessert"],
            ingredients: ["banana", "flour", "sugar"]
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [noMatch, ingredientMatch],
            friends: [],
            currentUserId: currentUserId,
            filterText: "garlic pasta"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.primaryRecipe.id, ingredientMatch.id)
    }

    func testGroupAndRankRecipes_DedupesSameSavedRecipeFromLocalAndPublicSources() {
        let currentUserId = UUID()
        let ownerId = UUID()
        let sourceId = UUID()
        let savedRecipeId = UUID()

        let savedCopy = makeRecipe(
            id: savedRecipeId,
            title: "Spicy Vodka Pasta",
            ownerId: ownerId,
            tags: ["Dinner"],
            ingredients: ["pasta", "tomato"],
            originalRecipeId: sourceId
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [savedCopy],
            publicRecipes: [savedCopy],
            friends: [],
            currentUserId: currentUserId,
            filterText: "vodka pasta"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.saveCount, 1)
        XCTAssertEqual(groups.first?.primaryRecipe.id, savedRecipeId)
    }

    func testGroupAndRankRecipes_PrefersFreshestDuplicateVariantWhenScoresTie() {
        let currentUserId = UUID()
        let ownerId = UUID()
        let recipeId = UUID()
        let staleDate = Date(timeIntervalSince1970: 1_700_000_000)
        let freshDate = Date(timeIntervalSince1970: 1_700_000_500)

        let staleLocalRecipe = makeRecipe(
            id: recipeId,
            title: "Spicy Vodka Pasta",
            ownerId: ownerId,
            tags: ["Dinner"],
            ingredients: ["pasta", "tomato"],
            updatedAt: staleDate
        )
        let freshPublicRecipe = makeRecipe(
            id: recipeId,
            title: "Spicy Vodka Pasta",
            ownerId: ownerId,
            tags: ["Dinner"],
            ingredients: ["pasta", "tomato"],
            updatedAt: freshDate
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [staleLocalRecipe],
            publicRecipes: [freshPublicRecipe],
            friends: [],
            currentUserId: currentUserId,
            filterText: "vodka pasta"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.primaryRecipe.updatedAt, freshDate)
    }

    func testGroupAndRankRecipes_CountsDistinctSavedCopiesTowardPopularity() {
        let currentUserId = UUID()
        let sourceOwnerId = UUID()
        let saver1Id = UUID()
        let saver2Id = UUID()
        let sourceId = UUID()

        let original = makeRecipe(
            id: sourceId,
            title: "Lentil Soup",
            ownerId: sourceOwnerId,
            tags: ["Soup"],
            ingredients: ["lentils"]
        )
        let savedCopy1 = makeRecipe(
            id: UUID(),
            title: "Lentil Soup",
            ownerId: saver1Id,
            tags: ["Soup"],
            ingredients: ["lentils"],
            originalRecipeId: sourceId
        )
        let savedCopy2 = makeRecipe(
            id: UUID(),
            title: "Lentil Soup",
            ownerId: saver2Id,
            tags: ["Soup"],
            ingredients: ["lentils"],
            originalRecipeId: sourceId
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [original, savedCopy1, savedCopy2],
            friends: [],
            currentUserId: currentUserId,
            filterText: "lentil soup"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.primaryRecipe.id, sourceId)
        XCTAssertEqual(groups.first?.saveCount, 3)
    }

    func testGroupAndRankRecipes_TreatsIndependentForkAsStandaloneRecipe() {
        let currentUserId = UUID()
        let sourceOwnerId = UUID()
        let forkOwnerId = UUID()
        let sourceId = UUID()
        let forkId = UUID()

        let original = makeRecipe(
            id: sourceId,
            title: "Lentil Soup",
            ownerId: sourceOwnerId,
            tags: ["Soup"],
            ingredients: ["lentils"]
        )
        let fork = Recipe(
            id: forkId,
            title: "Spicy Lentil Soup",
            ingredients: [Ingredient(name: "lentils", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "2 servings",
            tags: [Tag(name: "Soup")].compactMap { $0 },
            ownerId: forkOwnerId,
            updatedAt: Date(),
            originalRecipeId: sourceId,
            savedAt: Date(),
            sourceRecipeUpdatedAt: Date(),
            followsSourceUpdates: false
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [original, fork],
            friends: [],
            currentUserId: currentUserId,
            filterText: "lentil soup"
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.primaryRecipe.id)), Set([sourceId, forkId]))
    }

    func testGroupAndRankRecipes_UsesStableGroupedIdentifier() {
        let currentUserId = UUID()
        let ownerId = UUID()
        let groupId = UUID()

        let original = makeRecipe(
            id: groupId,
            title: "Roast Chicken",
            ownerId: ownerId,
            tags: ["Dinner"],
            ingredients: ["chicken"]
        )
        let savedCopy = makeRecipe(
            id: UUID(),
            title: "Roast Chicken",
            ownerId: UUID(),
            tags: ["Dinner"],
            ingredients: ["chicken"],
            originalRecipeId: groupId
        )

        let groups = RecipeGroupingService.groupAndRankRecipes(
            localRecipes: [],
            publicRecipes: [original, savedCopy],
            friends: [],
            currentUserId: currentUserId,
            filterText: "roast chicken"
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.id, groupId)
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        ownerId: UUID,
        tags: [String],
        ingredients: [String],
        updatedAt: Date = Date(),
        originalRecipeId: UUID? = nil,
        followsSourceUpdates: Bool? = nil,
        savedAt: Date? = nil,
        sourceRecipeUpdatedAt: Date? = nil,
        relatedRecipeIds: [UUID] = []
    ) -> Recipe {
        let isFollowingCopy = followsSourceUpdates ?? (originalRecipeId != nil)
        return Recipe(
            id: id,
            title: title,
            ingredients: ingredients.map { Ingredient(name: $0, quantity: nil) },
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "2 servings",
            tags: tags.compactMap { Tag(name: $0) },
            ownerId: ownerId,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            savedAt: originalRecipeId == nil ? savedAt : (savedAt ?? Date(timeIntervalSince1970: 1_700_000_000)),
            sourceRecipeUpdatedAt: originalRecipeId == nil ? sourceRecipeUpdatedAt : (sourceRecipeUpdatedAt ?? Date(timeIntervalSince1970: 1_700_000_100)),
            followsSourceUpdates: isFollowingCopy,
            relatedRecipeIds: relatedRecipeIds
        )
    }
}
