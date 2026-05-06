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

    override func setUp() async throws {
        try await super.setUp()

        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        modelContainer = try TestModelContainer.create()
        repository = makeRepository(modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        repository = nil
        modelContainer = nil
        try await super.tearDown()
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

    func testFetchOwnedCopiesReturnsOnlyMatchingNonPreviewCopies() async throws {
        let sourceId = UUID()
        let otherSourceId = UUID()
        let matchingCopy = makeRecipe(
            title: "Saved Soup",
            ownerId: UUID(),
            originalRecipeId: sourceId,
            isPreview: false
        )
        let previewCopy = makeRecipe(
            title: "Preview Soup",
            ownerId: UUID(),
            originalRecipeId: sourceId,
            isPreview: true
        )
        let unrelatedCopy = makeRecipe(
            title: "Saved Salad",
            ownerId: UUID(),
            originalRecipeId: otherSourceId,
            isPreview: false
        )

        try await repository.create(matchingCopy, skipCloudSync: true)
        try await repository.create(previewCopy, skipCloudSync: true)
        try await repository.create(unrelatedCopy, skipCloudSync: true)

        let results = try await repository.fetchOwnedCopies(originalRecipeIds: [sourceId])

        XCTAssertEqual(results.map(\.id), [matchingCopy.id])
    }

    func testRemoveSelfSavedRecipeCopiesDeletesFollowingCopyOfOwnedOriginal() async throws {
        let currentUserId = UUID()
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
