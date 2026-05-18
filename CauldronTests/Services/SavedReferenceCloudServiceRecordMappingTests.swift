//
//  SavedReferenceCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class SavedReferenceCloudServiceRecordMappingTests: XCTestCase {
    func testPopulateAndDecodeSavedRecipeReference() async throws {
        let service = SavedReferenceCloudService(core: CloudKitCore())
        let userId = UUID()
        let sourceRecipeId = UUID()
        let sourceOwnerId = UUID()
        let materializedRecipeId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reference = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            sourceOwnerId: sourceOwnerId,
            sourceRecipeName: "Spiced Lentils",
            originalCreatorName: "Nadav",
            materializedRecipeId: materializedRecipeId,
            cloudRecordName: SavedReferenceCloudService.recipeReferenceRecordName(
                userId: userId,
                sourceRecipeId: sourceRecipeId
            ),
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceUpdatedAt,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.savedRecipeReference,
            recordID: CKRecord.ID(recordName: reference.cloudRecordName!)
        )

        await service.populateRecipeReferenceRecord(record, from: reference)
        let decoded = try await service.recipeReference(from: record)

        XCTAssertEqual(decoded.id, reference.id)
        XCTAssertEqual(decoded.userId, userId)
        XCTAssertEqual(decoded.sourceRecipeId, sourceRecipeId)
        XCTAssertEqual(decoded.sourceOwnerId, sourceOwnerId)
        XCTAssertEqual(decoded.sourceRecipeName, "Spiced Lentils")
        XCTAssertEqual(decoded.originalCreatorName, "Nadav")
        XCTAssertEqual(decoded.materializedRecipeId, materializedRecipeId)
        XCTAssertEqual(decoded.cloudRecordName, record.recordID.recordName)
        XCTAssertEqual(decoded.savedAt, savedAt)
        XCTAssertEqual(decoded.sourceRecipeUpdatedAt, sourceUpdatedAt)
        XCTAssertEqual(record["sourceRecipeId"] as? String, sourceRecipeId.uuidString)
    }

    func testPopulateAndDecodeSavedCollectionReference() async throws {
        let service = SavedReferenceCloudService(core: CloudKitCore())
        let userId = UUID()
        let sourceCollectionId = UUID()
        let sourceOwnerId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_800_100_000)
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let reference = SavedCollectionReference(
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceOwnerId,
            sourceCollectionName: "Weeknight Book",
            cloudRecordName: SavedReferenceCloudService.collectionReferenceRecordName(
                userId: userId,
                sourceCollectionId: sourceCollectionId
            ),
            savedAt: savedAt,
            sourceCollectionUpdatedAt: sourceUpdatedAt,
            createdAt: savedAt,
            updatedAt: savedAt
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.savedCollectionReference,
            recordID: CKRecord.ID(recordName: reference.cloudRecordName!)
        )

        await service.populateCollectionReferenceRecord(record, from: reference)
        let decoded = try await service.collectionReference(from: record)

        XCTAssertEqual(decoded.id, reference.id)
        XCTAssertEqual(decoded.userId, userId)
        XCTAssertEqual(decoded.sourceCollectionId, sourceCollectionId)
        XCTAssertEqual(decoded.sourceOwnerId, sourceOwnerId)
        XCTAssertEqual(decoded.sourceCollectionName, "Weeknight Book")
        XCTAssertEqual(decoded.cloudRecordName, record.recordID.recordName)
        XCTAssertEqual(decoded.savedAt, savedAt)
        XCTAssertEqual(decoded.sourceCollectionUpdatedAt, sourceUpdatedAt)
        XCTAssertEqual(record["sourceCollectionId"] as? String, sourceCollectionId.uuidString)
    }
}
