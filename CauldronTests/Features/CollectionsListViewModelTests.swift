//
//  CollectionsListViewModelTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

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
}
