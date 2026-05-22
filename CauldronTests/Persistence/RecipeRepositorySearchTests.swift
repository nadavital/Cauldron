//
//  RecipeRepositorySearchTests.swift
//  CauldronTests
//

import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class RecipeRepositorySearchTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var repository: RecipeRepository!
    private var currentUserId: UUID!

    override func setUp() async throws {
        try await super.setUp()

        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        CurrentUserSession.shared.signOut()
        currentUserId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "tester",
                displayName: "Tester",
                createdAt: Date()
            )
        )
        modelContainer = try TestModelContainer.create()
        repository = makeRepository(modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        CurrentUserSession.shared.signOut()
        repository = nil
        modelContainer = nil
        currentUserId = nil
        try await super.tearDown()
    }

    func testRecipeDeletionSyncPolicyRequiresRemoteTombstoneBeforeActiveDelete() {
        XCTAssertTrue(RecipeDeletionSyncPolicy.canDeleteActiveRecords(tombstoneSaveError: nil))
        XCTAssertFalse(
            RecipeDeletionSyncPolicy.canDeleteActiveRecords(
                tombstoneSaveError: NSError(domain: "CloudKit", code: 11)
            )
        )
    }

    func testSearchByTagExcludesPreviewRecipes() async throws {
        let tag = Tag(name: "Dinner")
        let ownedRecipe = makeRecipe(
            title: "Owned Pasta",
            tags: [tag],
            ownerId: UUID(),
            isPreview: false
        )
        let previewRecipe = makeRecipe(
            title: "Community Pasta Preview",
            tags: [tag],
            ownerId: UUID(),
            isPreview: true
        )

        try await repository.create(ownedRecipe, skipCloudSync: true)
        try await repository.create(previewRecipe, skipCloudSync: true)

        let results = try await repository.search(tag: tag.name)

        XCTAssertEqual(results.map(\.id), [ownedRecipe.id])
    }

    func testSearchByTitleExcludesPreviewRecipes() async throws {
        let ownedRecipe = makeRecipe(
            title: "Lemon Pasta",
            tags: [],
            ownerId: UUID(),
            isPreview: false
        )
        let previewRecipe = makeRecipe(
            title: "Lemon Pasta Preview",
            tags: [],
            ownerId: UUID(),
            isPreview: true
        )

        try await repository.create(ownedRecipe, skipCloudSync: true)
        try await repository.create(previewRecipe, skipCloudSync: true)

        let results = try await repository.search(title: "Lemon")

        XCTAssertEqual(results.map(\.id), [ownedRecipe.id])
    }

    func testFetchRecentExcludesPreviewRecipes() async throws {
        let oldOwnedRecipe = makeRecipe(
            title: "Old Soup",
            ownerId: UUID(),
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let recentPreviewRecipe = makeRecipe(
            title: "Recent Preview Soup",
            ownerId: UUID(),
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 3_000),
            isPreview: true
        )
        let recentOwnedRecipe = makeRecipe(
            title: "Recent Soup",
            ownerId: UUID(),
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        try await repository.create(oldOwnedRecipe, skipCloudSync: true)
        try await repository.create(recentPreviewRecipe, skipCloudSync: true)
        try await repository.create(recentOwnedRecipe, skipCloudSync: true)

        let results = try await repository.fetchRecent(limit: 10)

        XCTAssertEqual(results.map(\.id), [recentOwnedRecipe.id, oldOwnedRecipe.id])
    }

    func testFetchLibraryRecipesReturnsOnlyRequestedOwnersNonPreviewRecipes() async throws {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let currentUsersRecipe = makeRecipe(
            title: "My Soup",
            ownerId: currentUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )
        let otherUsersRecipe = makeRecipe(
            title: "Other Soup",
            ownerId: otherUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 3_000),
            isPreview: false
        )
        let previewRecipe = makeRecipe(
            title: "Preview Soup",
            ownerId: currentUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 4_000),
            isPreview: true
        )

        try await repository.create(currentUsersRecipe, skipCloudSync: true)
        try await repository.create(otherUsersRecipe, skipCloudSync: true)
        try await repository.create(previewRecipe, skipCloudSync: true)

        let results = try await repository.fetchLibraryRecipes(ownerId: currentUserId)

        XCTAssertEqual(results.map(\.id), [currentUsersRecipe.id])
    }

    func testFetchByIdPrefersRequestedOwnerWhenDuplicateIdsExist() async throws {
        let sharedRecipeId = UUID()
        let currentUserId = UUID()
        let otherUserId = UUID()
        let currentUsersRecipe = makeRecipe(
            id: sharedRecipeId,
            title: "Current User Copy",
            ownerId: currentUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let otherUsersRecipe = makeRecipe(
            id: sharedRecipeId,
            title: "Other User Cached Copy",
            ownerId: otherUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        try await repository.create(currentUsersRecipe, skipCloudSync: true)
        try await repository.create(otherUsersRecipe, skipCloudSync: true)

        let fetched = try await repository.fetch(id: sharedRecipeId, preferredOwnerId: currentUserId)

        XCTAssertEqual(fetched?.title, "Current User Copy")
        XCTAssertEqual(fetched?.ownerId, currentUserId)
    }

    func testUpdateRecipeInDatabaseUpdatesMatchingOwnerWhenDuplicateIdsExist() async throws {
        let sharedRecipeId = UUID()
        let currentUserId = UUID()
        let otherUserId = UUID()
        let currentUsersRecipe = makeRecipe(
            id: sharedRecipeId,
            title: "Current User Copy",
            ownerId: currentUserId,
            originalRecipeId: nil,
            isPreview: false
        )
        let otherUsersRecipe = makeRecipe(
            id: sharedRecipeId,
            title: "Other User Cached Copy",
            ownerId: otherUserId,
            originalRecipeId: nil,
            isPreview: false
        )

        try await repository.create(currentUsersRecipe, skipCloudSync: true)
        try await repository.create(otherUsersRecipe, skipCloudSync: true)

        let updatedCurrentUsersRecipe = makeRecipe(
            id: sharedRecipeId,
            title: "Updated Current User Copy",
            ownerId: currentUserId,
            originalRecipeId: nil,
            isPreview: false
        )
        try await repository.updateRecipeInDatabase(
            updatedCurrentUsersRecipe,
            shouldUpdateTimestamp: false
        )

        let context = ModelContext(modelContainer)
        let models = try context.fetch(FetchDescriptor<RecipeModel>(
            predicate: #Predicate { $0.id == sharedRecipeId }
        ))
        let currentModel = try XCTUnwrap(models.first { $0.ownerId == currentUserId })
        let otherModel = try XCTUnwrap(models.first { $0.ownerId == otherUserId })

        XCTAssertEqual(currentModel.title, "Updated Current User Copy")
        XCTAssertEqual(otherModel.title, "Other User Cached Copy")
    }

    func testFetchOwnedCopiesReturnsOnlyMatchingNonPreviewCopies() async throws {
        let sourceId = UUID()
        let otherSourceId = UUID()
        let matchingCopy = makeRecipe(
            title: "Saved Soup",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            isPreview: false
        )
        let previewCopy = makeRecipe(
            title: "Preview Soup",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            isPreview: true
        )
        let unrelatedCopy = makeRecipe(
            title: "Saved Salad",
            ownerId: currentUserId,
            originalRecipeId: otherSourceId,
            isPreview: false
        )

        try await repository.create(matchingCopy, skipCloudSync: true)
        try await repository.create(previewCopy, skipCloudSync: true)
        try await repository.create(unrelatedCopy, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(originalRecipeIds: [sourceId])

        XCTAssertEqual(results.map(\.id), [matchingCopy.id])
    }

    func testFetchOwnedCopiesExcludesCopiesOwnedByOtherUsers() async throws {
        let sourceId = UUID()
        let otherUserCopy = makeRecipe(
            title: "Other User Soup",
            ownerId: UUID(),
            originalRecipeId: sourceId,
            isPreview: false
        )
        let currentUserCopy = makeRecipe(
            title: "My Soup",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            isPreview: false
        )

        try await repository.create(otherUserCopy, skipCloudSync: true)
        try await repository.create(currentUserCopy, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(originalRecipeIds: [sourceId])

        XCTAssertEqual(results.map(\.id), [currentUserCopy.id])
    }

    func testFetchOwnedCopiesDoesNotTreatSameTitleAndIngredientCountAsSavedCopy() async throws {
        let sourceId = UUID()
        let unrelatedSameShape = makeRecipe(
            title: "Saved Soup",
            ownerId: UUID(),
            originalRecipeId: UUID(),
            isPreview: false
        )

        try await repository.create(unrelatedSameShape, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(originalRecipeIds: [sourceId])

        XCTAssertTrue(results.isEmpty)
    }

    func testFetchOwnedCopiesCanRequireCopiesThatStillFollowSource() async throws {
        let sourceId = UUID()
        let ownerId = UUID()
        let followingCopy = makeRecipe(
            title: "Following Sauce",
            ownerId: ownerId,
            originalRecipeId: sourceId,
            followsSourceUpdates: true,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let editedFork = makeRecipe(
            title: "Edited Sauce",
            ownerId: ownerId,
            originalRecipeId: sourceId,
            followsSourceUpdates: false,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        try await repository.create(followingCopy, skipCloudSync: true)
        try await repository.create(editedFork, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(
            originalRecipeIds: [sourceId],
            ownerId: ownerId,
            followingSourceOnly: true
        )

        XCTAssertEqual(results.map(\.id), [followingCopy.id])
    }

    func testFetchOwnedCopiesUsesCurrentSessionWhenOwnerIsOmitted() async throws {
        let sourceId = UUID()
        let ownedCopy = makeRecipe(
            title: "My Saved Sauce",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            followsSourceUpdates: true,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )

        try await repository.create(ownedCopy, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(originalRecipeIds: [sourceId])

        XCTAssertEqual(results.map(\.id), [ownedCopy.id])
    }

    func testToggleFavoritePrefersCurrentUsersDuplicateRecipeRow() async throws {
        let recipeId = UUID()
        let otherUserId = UUID()
        let nonOwnedSource = Recipe(
            id: recipeId,
            title: "Source Sauce",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Season.", timers: [])],
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: otherUserId,
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let ownedCopy = Recipe(
            id: recipeId,
            title: "My Sauce",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Season.", timers: [])],
            isFavorite: false,
            visibility: .privateRecipe,
            ownerId: currentUserId,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        try await repository.create(nonOwnedSource, skipCloudSync: true)
        try await repository.create(ownedCopy, skipCloudSync: true)

        try await repository.toggleFavorite(id: recipeId)

        let currentUserRows = try await repository.fetchLibraryRecipes(ownerId: currentUserId)
        let otherUserRows = try await repository.fetchLibraryRecipes(ownerId: otherUserId)
        XCTAssertEqual(currentUserRows.first?.isFavorite, true)
        XCTAssertEqual(otherUserRows.first?.isFavorite, false)
    }

    func testReplayStaleRecipeUpdateCompletesWhenRemoteTombstoneAlreadyWon() async throws {
        let recipeId = UUID()
        await repository.operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: recipeId
        )
        guard let operation = await repository.operationQueueService.getOperation(for: recipeId, entityType: .recipe) else {
            return XCTFail("Expected queued recipe update operation")
        }
        try await repository.deletedRecipeRepository.markAsDeleted(
            recipeId: recipeId,
            cloudRecordName: nil,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        await repository.replayRecipeUpsertOperationForTesting(operation)

        let queued = await repository.operationQueueService.getOperation(for: recipeId, entityType: .recipe)
        XCTAssertNil(queued)
    }

    func testResolveLocalRelatedRecipesPrefersOwnedCopyOverPreview() async throws {
        let sourceId = UUID()
        let preview = makeRecipe(
            id: sourceId,
            title: "Preview Sauce",
            ownerId: UUID(),
            originalRecipeId: nil,
            isPreview: true
        )
        let ownedCopy = makeRecipe(
            title: "Saved Sauce",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            isPreview: false
        )

        try await repository.create(preview, skipCloudSync: true)
        try await repository.create(ownedCopy, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: true
        )

        XCTAssertEqual(resolution.recipes.map(\.id), [ownedCopy.id])
        XCTAssertTrue(resolution.missingIds.isEmpty)
    }

    func testResolveLocalRelatedRecipesCanTreatPreviewAsMissing() async throws {
        let sourceId = UUID()
        let preview = makeRecipe(
            id: sourceId,
            title: "Preview Sauce",
            ownerId: UUID(),
            originalRecipeId: nil,
            isPreview: true
        )

        try await repository.create(preview, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: false
        )

        XCTAssertTrue(resolution.recipes.isEmpty)
        XCTAssertEqual(resolution.missingIds, [sourceId])
    }

    func testResolveLocalRelatedRecipesPrefersCurrentUsersOwnedCopy() async throws {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let sourceId = UUID()
        let currentUsersCopy = makeRecipe(
            title: "My Saved Sauce",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let otherUsersCopy = makeRecipe(
            title: "Someone Else's Saved Sauce",
            ownerId: otherUserId,
            originalRecipeId: sourceId,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        try await repository.create(currentUsersCopy, skipCloudSync: true)
        try await repository.create(otherUsersCopy, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: true,
            preferredOwnerId: currentUserId
        )

        XCTAssertEqual(resolution.recipes.map(\.id), [currentUsersCopy.id])
        XCTAssertTrue(resolution.missingIds.isEmpty)
    }

    func testResolveLocalRelatedRecipesPrefersCurrentUsersOwnedCopyOverNonOwnedDirectMatch() async throws {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let sourceId = UUID()
        let nonOwnedDirectMatch = makeRecipe(
            id: sourceId,
            title: "Original Sauce",
            ownerId: otherUserId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )
        let currentUsersCopy = makeRecipe(
            title: "My Saved Sauce",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )

        try await repository.create(nonOwnedDirectMatch, skipCloudSync: true)
        try await repository.create(currentUsersCopy, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: true,
            preferredOwnerId: currentUserId
        )

        XCTAssertEqual(resolution.recipes.map(\.id), [currentUsersCopy.id])
        XCTAssertTrue(resolution.missingIds.isEmpty)
    }

    func testResolveLocalRelatedRecipesTreatsNonOwnedDirectMatchAsMissingWhenPreferredOwnerIsSet() async throws {
        let currentUserId = UUID()
        let otherUserId = UUID()
        let sourceId = UUID()
        let nonOwnedDirectMatch = makeRecipe(
            id: sourceId,
            title: "Original Sauce",
            ownerId: otherUserId,
            originalRecipeId: nil,
            isPreview: false
        )

        try await repository.create(nonOwnedDirectMatch, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: true,
            preferredOwnerId: currentUserId
        )

        XCTAssertTrue(resolution.recipes.isEmpty)
        XCTAssertEqual(resolution.missingIds, [sourceId])
    }

    func testResolveLocalRelatedRecipesDoesNotSubstituteEditedForkForCanonicalReference() async throws {
        let currentUserId = UUID()
        let sourceId = UUID()
        let editedFork = makeRecipe(
            title: "My Edited Sauce",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            followsSourceUpdates: false,
            isPreview: false
        )

        try await repository.create(editedFork, skipCloudSync: true)

        let resolution = try await repository.resolveLocalRelatedRecipes(
            referenceIds: [sourceId],
            includePreviews: false,
            preferredOwnerId: currentUserId
        )

        XCTAssertTrue(resolution.recipes.isEmpty)
        XCTAssertEqual(resolution.missingIds, [sourceId])
    }

    func testRemoveSelfSavedRecipeCopiesDeletesFollowingCopyOfOwnedOriginal() async throws {
        let currentUserId = try XCTUnwrap(self.currentUserId)
        let sourceId = UUID()
        let original = makeRecipe(
            id: sourceId,
            title: "Owned Roast Chicken",
            ownerId: currentUserId,
            originalRecipeId: nil,
            followsSourceUpdates: false,
            isPreview: false
        )
        let selfSavedCopy = makeRecipe(
            title: "Owned Roast Chicken",
            ownerId: currentUserId,
            originalRecipeId: sourceId,
            followsSourceUpdates: true,
            isPreview: false
        )
        let externalCopy = makeRecipe(
            title: "External Soup",
            ownerId: currentUserId,
            originalRecipeId: UUID(),
            followsSourceUpdates: true,
            isPreview: false
        )

        try await repository.create(original, skipCloudSync: true)
        try await repository.create(selfSavedCopy, skipCloudSync: true)
        try await repository.create(externalCopy, skipCloudSync: true)

        let removedCount = try await repository.removeSelfSavedRecipeCopies(currentUserId: currentUserId)
        let remainingRecipes = try await repository.fetchAll()

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(Set(remainingRecipes.map(\.id)), Set([sourceId, externalCopy.id]))
    }

    func testCreatePreviewDoesNotClearDeletedRecipeTombstone() async throws {
        let recipeId = UUID()
        let ownerId = UUID()
        let preview = makeRecipe(
            id: recipeId,
            title: "Preview Soup",
            ownerId: ownerId,
            originalRecipeId: nil,
            isPreview: true
        )

        try await repository.deletedRecipeRepository.markAsDeleted(
            recipeId: recipeId,
            cloudRecordName: recipeId.uuidString
        )
        try await repository.create(preview, skipCloudSync: true)

        let isDeleted = try await repository.deletedRecipeRepository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted)
    }

    func testRemoveDuplicateRecipesMergesIntoCanonicalNonPreviewRecipe() async throws {
        let recipeId = UUID()
        let ownerId = UUID()
        let previewDuplicate = makeRecipe(
            id: recipeId,
            title: "Preview Shell",
            ownerId: ownerId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: true
        )
        let ownedCanonical = Recipe(
            id: recipeId,
            title: "Owned Recipe",
            ingredients: [
                Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup))
            ],
            steps: [
                CookStep(index: 0, text: "Mix.", timers: [])
            ],
            imageURL: URL(string: "file:///tmp/recipe.jpg"),
            isFavorite: true,
            visibility: .publicRecipe,
            ownerId: ownerId,
            cloudRecordName: "private-record",
            cloudImageRecordName: "image-record",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        let context = ModelContext(modelContainer)
        context.insert(try RecipeModel.from(previewDuplicate))
        context.insert(try RecipeModel.from(ownedCanonical))
        try context.save()

        let removedCount = try await repository.removeDuplicateRecipes()
        let remaining = try await repository.fetchAll()

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, recipeId)
        XCTAssertEqual(remaining.first?.title, "Owned Recipe")
        XCTAssertEqual(remaining.first?.ownerId, ownerId)
        XCTAssertEqual(remaining.first?.cloudRecordName, "private-record")
        XCTAssertEqual(remaining.first?.cloudImageRecordName, "image-record")
        XCTAssertEqual(remaining.first?.imageURL?.lastPathComponent, "recipe.jpg")
        XCTAssertTrue(remaining.first?.imageURL?.path.contains("/RecipeImages/") ?? false)
        XCTAssertEqual(remaining.first?.visibility, .publicRecipe)
        XCTAssertTrue(remaining.first?.isFavorite ?? false)
        XCTAssertFalse(remaining.first?.isPreview ?? true)
    }

    func testRemoveDuplicateRecipesDoesNotGraftCopyLineageOntoOriginalCanonical() async throws {
        let recipeId = UUID()
        let ownerId = UUID()
        let sourceId = UUID()
        let copiedDuplicate = makeRecipe(
            id: recipeId,
            title: "Copied Duplicate",
            ownerId: ownerId,
            originalRecipeId: sourceId,
            followsSourceUpdates: true,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let originalCanonical = Recipe(
            id: recipeId,
            title: "Owned Original",
            ingredients: [
                Ingredient(name: "Flour", quantity: Quantity(value: 2, unit: .cup))
            ],
            steps: [
                CookStep(index: 0, text: "Mix.", timers: [])
            ],
            visibility: .publicRecipe,
            ownerId: ownerId,
            cloudRecordName: "private-record",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        let context = ModelContext(modelContainer)
        context.insert(try RecipeModel.from(copiedDuplicate))
        context.insert(try RecipeModel.from(originalCanonical))
        try context.save()

        let removedCount = try await repository.removeDuplicateRecipes()
        let remaining = try await repository.fetchAll()

        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.id, recipeId)
        XCTAssertEqual(remaining.first?.title, "Owned Original")
        XCTAssertNil(remaining.first?.originalRecipeId)
        XCTAssertNil(remaining.first?.savedAt)
        XCTAssertFalse(remaining.first?.isFollowingSourceUpdates ?? true)
    }

    func testRemoveDuplicateRecipesDoesNotMergeRecipesWithDifferentOwners() async throws {
        let recipeId = UUID()
        let firstOwnerId = UUID()
        let secondOwnerId = UUID()
        let firstRecipe = makeRecipe(
            id: recipeId,
            title: "First Owner Recipe",
            ownerId: firstOwnerId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            isPreview: false
        )
        let secondRecipe = makeRecipe(
            id: recipeId,
            title: "Second Owner Recipe",
            ownerId: secondOwnerId,
            originalRecipeId: nil,
            updatedAt: Date(timeIntervalSince1970: 2_000),
            isPreview: false
        )

        let context = ModelContext(modelContainer)
        context.insert(try RecipeModel.from(firstRecipe))
        context.insert(try RecipeModel.from(secondRecipe))
        try context.save()

        let removedCount = try await repository.removeDuplicateRecipes()
        let remaining = try await repository.fetchAll()

        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(Set(remaining.compactMap(\.ownerId)), [firstOwnerId, secondOwnerId])
    }

    private func makeRecipe(
        title: String,
        tags: [Tag],
        ownerId: UUID,
        isPreview: Bool
    ) -> Recipe {
        Recipe(
            title: title,
            ingredients: [
                Ingredient(name: "Pasta", quantity: Quantity(value: 1, unit: .pound))
            ],
            steps: [
                CookStep(index: 0, text: "Cook pasta.", timers: [])
            ],
            tags: tags,
            ownerId: ownerId,
            isPreview: isPreview
        )
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        ownerId: UUID,
        originalRecipeId: UUID?,
        followsSourceUpdates: Bool? = nil,
        updatedAt: Date = Date(),
        isPreview: Bool
    ) -> Recipe {
        let followsSourceUpdates = followsSourceUpdates ?? (originalRecipeId != nil)
        return Recipe(
            id: id,
            title: title,
            ingredients: [
                Ingredient(name: "Salt", quantity: nil)
            ],
            steps: [
                CookStep(index: 0, text: "Season.", timers: [])
            ],
            ownerId: ownerId,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeId,
            savedAt: originalRecipeId == nil ? nil : Date(timeIntervalSince1970: 1_700_000_000),
            sourceRecipeUpdatedAt: originalRecipeId == nil ? nil : Date(timeIntervalSince1970: 1_700_000_100),
            followsSourceUpdates: followsSourceUpdates,
            isPreview: isPreview
        )
    }

    private func makeRepository(modelContainer: ModelContainer) -> RecipeRepository {
        let cloudKitCore = CloudKitCore()
        let recipeCloudService = RecipeCloudService(core: cloudKitCore)
        let imageManager = RecipeImageManager(
            directoryName: "RecipeRepositorySearchTests-\(UUID().uuidString)",
            uploadToCloudWithDatabase: nil,
            downloadFromCloudWithDatabase: nil
        )

        return RecipeRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            deletedRecipeRepository: DeletedRecipeRepository(modelContainer: modelContainer),
            imageManager: imageManager,
            imageSyncManager: ImageSyncManager(),
            operationQueueService: OperationQueueService(),
            externalShareService: ExternalShareService(imageManager: imageManager)
        )
    }
}
