//
//  CollectionsListViewModelTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class CollectionsListViewModelTests: XCTestCase {
    func testSplitCollectionsForDisplayKeepsLegacyCopiesEditableButSeparatesSavedReferences() {
        let currentUserId = UUID()
        let sourceOwnerId = UUID()
        let sourceCollectionId = UUID()
        let unrelatedOwnerId = UUID()
        let now = Date()

        let ownedCollection = Collection(
            id: UUID(),
            name: "Weeknight",
            userId: currentUserId,
            updatedAt: now
        )
        let legacyCopiedCollection = Collection(
            id: UUID(),
            name: "Old Saved Copy",
            userId: currentUserId,
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            savedAt: now,
            followsSourceUpdates: true,
            updatedAt: now.addingTimeInterval(-10)
        )
        let savedSourceCollection = Collection(
            id: sourceCollectionId,
            name: "Source Brunch",
            userId: sourceOwnerId,
            updatedAt: now.addingTimeInterval(-20)
        )
        let unrelatedNonOwnedCollection = Collection(
            id: UUID(),
            name: "Not Saved",
            userId: unrelatedOwnerId,
            updatedAt: now
        )
        let savedReference = SavedCollectionReference(
            userId: currentUserId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            sourceCollectionName: "Source Brunch",
            savedAt: now
        )

        let sections = CollectionsListViewModel.splitCollectionsForDisplay(
            localCollections: [ownedCollection, legacyCopiedCollection, unrelatedNonOwnedCollection],
            savedReferences: [savedReference],
            fetchedSourceCollections: [sourceCollectionId: savedSourceCollection],
            currentUserId: currentUserId
        )

        XCTAssertEqual(sections.owned.map(\.id), [ownedCollection.id, legacyCopiedCollection.id])
        XCTAssertEqual(sections.saved.map(\.id), [savedSourceCollection.id])
        XCTAssertFalse(sections.saved.contains { $0.id == legacyCopiedCollection.id })
        XCTAssertFalse(sections.owned.contains { $0.id == unrelatedNonOwnedCollection.id })
        XCTAssertFalse(sections.saved.contains { $0.id == unrelatedNonOwnedCollection.id })
    }

    func testCustomCoverPagePolicyDoesNotReserveMissingCustomCoverAheadOfRecipeImages() {
        XCTAssertFalse(
            CollectionCoverPagePolicy.shouldReserveCustomCoverPage(
                coverImageType: .customImage,
                coverImageURL: nil,
                cloudCoverImageRecordName: nil,
                hasLoadedCustomCoverImage: false
            )
        )
    }

    func testCustomCoverPagePolicyReservesExistingCustomCover() {
        XCTAssertTrue(
            CollectionCoverPagePolicy.shouldReserveCustomCoverPage(
                coverImageType: .customImage,
                coverImageURL: URL(fileURLWithPath: "/tmp/cover.jpg"),
                cloudCoverImageRecordName: nil,
                hasLoadedCustomCoverImage: false
            )
        )

        XCTAssertTrue(
            CollectionCoverPagePolicy.shouldReserveCustomCoverPage(
                coverImageType: .customImage,
                coverImageURL: nil,
                cloudCoverImageRecordName: "collection-cover-record",
                hasLoadedCustomCoverImage: false
            )
        )
    }

    func testCustomCoverImageCacheKeyChangesWhenModifiedAtChanges() {
        let collectionId = UUID()
        let imageURL = URL(fileURLWithPath: "/tmp/\(collectionId.uuidString).jpg")
        let original = Collection(
            id: collectionId,
            name: "Covers",
            userId: UUID(),
            coverImageType: .customImage,
            coverImageURL: imageURL,
            coverImageModifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let replacedAtSamePath = original.updated(
            coverImageType: .customImage,
            coverImageURL: imageURL,
            coverImageModifiedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertNotEqual(original.customCoverImageCacheKey, replacedAtSamePath.customCoverImageCacheKey)
    }

    func testLoadCollectionsDoesNotUseNonOwnedLocalRecipeRowsForOwnedCollectionImages() async throws {
        let dependencies = DependencyContainer.preview()
        let currentUserId = UUID()
        let sourceOwnerId = UUID()
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: currentUserId,
                username: "tester",
                displayName: "Tester",
                createdAt: Date()
            )
        )
        defer { CurrentUserSession.shared.signOut() }

        let sourceRecipeId = UUID()
        let sourceRecipe = Recipe(
            id: sourceRecipeId,
            title: "Cached Source",
            ingredients: [],
            steps: [],
            yields: "4 servings",
            imageURL: URL(string: "https://example.com/source.jpg"),
            visibility: .publicRecipe,
            ownerId: sourceOwnerId
        )
        let ownedCollection = Collection(
            name: "Mine",
            userId: currentUserId,
            recipeIds: [sourceRecipeId]
        )
        try await dependencies.recipeRepository.create(sourceRecipe, skipCloudSync: true)
        try await dependencies.collectionRepository.create(ownedCollection)

        let viewModel = CollectionsListViewModel(dependencies: dependencies)
        await viewModel.loadCollections()

        let loadedCollection = try XCTUnwrap(viewModel.ownedCollections.first)
        XCTAssertEqual(viewModel.recipeImageSources(for: loadedCollection).first?.imageURL, nil)
    }
}
