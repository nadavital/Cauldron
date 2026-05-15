//
//  CollectionCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class CollectionCloudServiceRecordMappingTests: XCTestCase {
    func testPopulateAndDecodeCollectionPreservesSourceMetadata() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionId = UUID()
        let ownerId = UUID()
        let sourceCollectionId = UUID()
        let sourceOwnerId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let collection = Collection(
            id: collectionId,
            name: "Saved Brunch",
            description: "Weekend things",
            userId: ownerId,
            recipeIds: [UUID()],
            visibility: .publicRecipe,
            symbolName: "fork.knife",
            color: "#4ECDC4",
            originalCollectionId: sourceCollectionId,
            originalCollectionOwnerId: sourceOwnerId,
            originalCollectionName: "Original Brunch",
            savedAt: savedAt,
            sourceCollectionUpdatedAt: sourceUpdatedAt,
            followsSourceUpdates: true,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: collectionId.uuidString)
        )

        await service.populateCollectionRecord(record, from: collection)
        let decoded = try await service.collectionFromRecord(record)

        XCTAssertEqual(decoded.originalCollectionId, sourceCollectionId)
        XCTAssertEqual(decoded.originalCollectionOwnerId, sourceOwnerId)
        XCTAssertEqual(decoded.originalCollectionName, "Original Brunch")
        XCTAssertEqual(decoded.savedAt, savedAt)
        XCTAssertEqual(decoded.sourceCollectionUpdatedAt, sourceUpdatedAt)
        XCTAssertTrue(decoded.followsSourceUpdates)
        XCTAssertEqual(record["originalCollectionId"] as? String, sourceCollectionId.uuidString)
        XCTAssertEqual(record["originalCollectionOwnerId"] as? String, sourceOwnerId.uuidString)
        XCTAssertEqual(record["originalCollectionName"] as? String, "Original Brunch")
        XCTAssertEqual(record["savedAt"] as? Date, savedAt)
        XCTAssertEqual(record["sourceCollectionUpdatedAt"] as? Date, sourceUpdatedAt)
        XCTAssertEqual((record["followsSourceUpdates"] as? NSNumber)?.intValue, 1)
    }

    func testMembershipRecordIDUsesStableCollectionRecipePair() {
        let collectionId = UUID()
        let recipeId = UUID()
        let recordID = CollectionCloudService.membershipRecordID(
            collectionId: collectionId,
            recipeId: recipeId
        )

        XCTAssertEqual(recordID.recordName, "membership_\(collectionId.uuidString)_\(recipeId.uuidString)")
    }

    func testPopulateAndDecodeMembershipEdge() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionId = UUID()
        let recipeId = UUID()
        let ownerId = UUID()
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let edge = CollectionMembershipEdge(
            collectionId: collectionId,
            recipeId: recipeId,
            ownerId: ownerId,
            status: .removed,
            updatedAt: updatedAt,
            sortOrder: 42,
            sourceDeviceId: "device-b",
            schemaVersion: 3
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.collectionMembership,
            recordID: CollectionCloudService.membershipRecordID(
                collectionId: collectionId,
                recipeId: recipeId
            )
        )

        await service.populateMembershipRecord(record, from: edge)
        let decoded = try await service.membershipEdge(from: record)

        XCTAssertEqual(decoded, edge)
        XCTAssertEqual(record["collectionId"] as? String, collectionId.uuidString)
        XCTAssertEqual(record["recipeId"] as? String, recipeId.uuidString)
        XCTAssertEqual(record["ownerId"] as? String, ownerId.uuidString)
        XCTAssertEqual(record["status"] as? String, CollectionMembershipStatus.removed.rawValue)
        XCTAssertEqual(record["updatedAt"] as? Date, updatedAt)
        XCTAssertEqual((record["sortOrder"] as? NSNumber)?.intValue, 42)
        XCTAssertEqual(record["sourceDeviceId"] as? String, "device-b")
        XCTAssertEqual((record["schemaVersion"] as? NSNumber)?.intValue, 3)
    }
}
