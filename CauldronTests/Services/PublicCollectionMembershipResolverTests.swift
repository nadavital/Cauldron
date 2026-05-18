//
//  PublicCollectionMembershipResolverTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class PublicCollectionMembershipResolverTests: XCTestCase {
    private var dependencies: DependencyContainer!
    private var currentUserId: UUID!
    private var sourceOwnerId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        CurrentUserSession.shared.signOut()
        dependencies = DependencyContainer.preview()
        currentUserId = UUID()
        sourceOwnerId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "owner",
                displayName: "Owner",
                createdAt: Date()
            )
        )
    }

    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        dependencies = nil
        currentUserId = nil
        sourceOwnerId = nil
        try await super.tearDown()
    }

    func testRepairPlanCountsPrivateOwnedRecipesOnlyWhenReferencesAreAlreadyPublic() async throws {
        let privateRecipe = makeRecipe(
            title: "Private Soup",
            ownerId: currentUserId,
            visibility: .privateRecipe
        )
        let previewRecipe = makeRecipe(
            title: "Referenced Challah",
            ownerId: sourceOwnerId,
            visibility: .publicRecipe,
            isPreview: true
        )
        try await dependencies.recipeRepository.create(privateRecipe, skipCloudSync: true)
        try await dependencies.recipeRepository.create(previewRecipe, skipCloudSync: true)

        let plan = try await dependencies.publicCollectionMembershipResolver.repairPlan(
            recipeIds: [privateRecipe.id, previewRecipe.id],
            ownerId: currentUserId,
            visibility: .publicRecipe
        )

        XCTAssertEqual(plan.privateOwnedRecipeCount, 1)
        XCTAssertEqual(plan.referencedRecipeCount, 0)
        XCTAssertTrue(plan.requiresRepair)
    }

    func testResolvePublishesPrivateOwnedRecipesAndKeepsPublicRecipeReferences() async throws {
        let privateRecipe = makeRecipe(
            title: "Private Soup",
            ownerId: currentUserId,
            visibility: .privateRecipe
        )
        let previewRecipe = makeRecipe(
            title: "Referenced Challah",
            ownerId: sourceOwnerId,
            visibility: .publicRecipe,
            isPreview: true
        )
        try await dependencies.recipeRepository.create(privateRecipe, skipCloudSync: true)
        try await dependencies.recipeRepository.create(previewRecipe, skipCloudSync: true)

        let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
            recipeIds: [previewRecipe.id, privateRecipe.id],
            ownerId: currentUserId,
            visibility: .publicRecipe
        )

        XCTAssertEqual(resolution.publishedRecipeCount, 1)
        XCTAssertEqual(resolution.copiedRecipeCount, 0)
        XCTAssertFalse(resolution.changedRecipeIds)
        XCTAssertEqual(resolution.recipeIds.count, 2)
        XCTAssertEqual(resolution.recipeIds.last, privateRecipe.id)
        XCTAssertTrue(resolution.recipeIds.contains(previewRecipe.id))

        let fetchedPrivateRecipe = try await dependencies.recipeRepository.fetch(id: privateRecipe.id)
        let updatedPrivateRecipe = try XCTUnwrap(fetchedPrivateRecipe)
        XCTAssertEqual(updatedPrivateRecipe.visibility, .publicRecipe)

        let stillCachedPreview = try await dependencies.recipeRepository.fetch(id: previewRecipe.id)
        XCTAssertNotNil(stillCachedPreview)
    }

    func testResolveKeepsUnknownRecipeIdsSoValidRemoteReferencesAreNotDeletedLocally() async throws {
        let remoteRecipeId = UUID()

        let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
            recipeIds: [remoteRecipeId],
            ownerId: currentUserId,
            visibility: .publicRecipe
        )

        XCTAssertFalse(resolution.changedRecipeIds)
        XCTAssertEqual(resolution.recipeIds, [remoteRecipeId])
        XCTAssertEqual(resolution.publishedRecipeCount, 0)
        XCTAssertEqual(resolution.copiedRecipeCount, 0)
    }

    func testResolveKeepsPublicSourceReferenceEvenWhenLegacyPrivateCopyExists() async throws {
        let sourceRecipe = makeRecipe(
            title: "Shared Tart",
            ownerId: sourceOwnerId,
            visibility: .publicRecipe
        )
        let existingPrivateCopy = Recipe(
            title: "My Tart",
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: .privateRecipe,
            ownerId: currentUserId,
            originalRecipeId: sourceRecipe.id,
            originalCreatorId: sourceOwnerId,
            originalCreatorName: "Source Chef",
            savedAt: Date(),
            sourceRecipeUpdatedAt: sourceRecipe.updatedAt,
            followsSourceUpdates: true
        )

        try await dependencies.recipeRepository.create(sourceRecipe, skipCloudSync: true)
        try await dependencies.recipeRepository.create(existingPrivateCopy, skipCloudSync: true)

        let resolution = try await dependencies.publicCollectionMembershipResolver.resolveRecipeIdsForOwnedPublicCollection(
            recipeIds: [sourceRecipe.id],
            ownerId: currentUserId,
            visibility: .publicRecipe
        )

        XCTAssertEqual(resolution.recipeIds, [sourceRecipe.id])
        XCTAssertEqual(resolution.publishedRecipeCount, 0)
        XCTAssertEqual(resolution.copiedRecipeCount, 0)
        XCTAssertFalse(resolution.changedRecipeIds)

        let fetchedCopy = try await dependencies.recipeRepository.fetch(id: existingPrivateCopy.id)
        XCTAssertEqual(fetchedCopy?.visibility, .privateRecipe)
    }

    private func makeRecipe(
        title: String,
        ownerId: UUID,
        visibility: RecipeVisibility,
        isPreview: Bool = false
    ) -> Recipe {
        Recipe(
            title: title,
            ingredients: [],
            steps: [],
            yields: "4 servings",
            tags: [],
            visibility: visibility,
            ownerId: ownerId,
            isPreview: isPreview
        )
    }
}
