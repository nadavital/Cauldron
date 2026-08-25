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

    func testPopulateCollectionRecordClearsRemovedOptionalFields() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionId = UUID()
        let ownerId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_200)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection-cover-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try Data([0x01, 0x02, 0x03]).write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        let record = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: collectionId.uuidString)
        )
        record["description"] = "Old description" as CKRecordValue
        record["emoji"] = ":old:" as CKRecordValue
        record["symbolName"] = "fork.knife" as CKRecordValue
        record["color"] = "#000000" as CKRecordValue
        record["coverImageAsset"] = CKAsset(fileURL: assetURL)
        record["coverImageModifiedAt"] = createdAt as CKRecordValue

        let collection = Collection(
            id: collectionId,
            name: "No Icon",
            description: nil,
            userId: ownerId,
            recipeIds: [],
            visibility: .privateRecipe,
            emoji: nil,
            symbolName: nil,
            color: nil,
            createdAt: createdAt,
            updatedAt: createdAt
        )

        await service.populateCollectionRecord(record, from: collection)

        XCTAssertNil(record["description"])
        XCTAssertNil(record["emoji"])
        XCTAssertNil(record["symbolName"])
        XCTAssertNil(record["color"])
        XCTAssertNil(record["coverImageAsset"])
        XCTAssertNil(record["coverImageModifiedAt"])
    }

    func testDecodeCollectionMarksCloudCoverImageAssetAvailable() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionId = UUID()
        let ownerId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_200)
        let imageModifiedAt = Date(timeIntervalSince1970: 1_800_000_300)
        let assetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection-cover-\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        try Data([0x01, 0x02, 0x03]).write(to: assetURL)
        defer { try? FileManager.default.removeItem(at: assetURL) }

        let record = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: collectionId.uuidString)
        )
        record["collectionId"] = collectionId.uuidString as CKRecordValue
        record["name"] = "Cookbook"
        record["userId"] = ownerId.uuidString as CKRecordValue
        record["visibility"] = RecipeVisibility.publicRecipe.rawValue as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = createdAt as CKRecordValue
        record["coverImageType"] = CoverImageType.customImage.rawValue as CKRecordValue
        record["coverImageAsset"] = CKAsset(fileURL: assetURL)
        record["coverImageModifiedAt"] = imageModifiedAt as CKRecordValue
        record["recipeIds"] = "[]" as CKRecordValue

        let decoded = try await service.collectionFromRecord(record)

        XCTAssertEqual(decoded.coverImageType, .customImage)
        XCTAssertNil(decoded.coverImageURL)
        XCTAssertEqual(decoded.cloudCoverImageRecordName, collectionId.uuidString)
        XCTAssertEqual(decoded.coverImageModifiedAt, imageModifiedAt)
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

    func testMembershipRecordsBuildsBatchWithoutLosingEdgeIdentity() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionId = UUID()
        let ownerId = UUID()
        let edges = (0..<3).map { sortOrder in
            CollectionMembershipEdge(
                collectionId: collectionId,
                recipeId: UUID(),
                ownerId: ownerId,
                status: sortOrder == 2 ? .removed : .active,
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(sortOrder)),
                sortOrder: sortOrder,
                sourceDeviceId: "batch-device"
            )
        }

        let records = await service.membershipRecords(for: edges)

        XCTAssertEqual(records.count, edges.count)
        for (record, edge) in zip(records, edges) {
            XCTAssertTrue(
                record.recordID.recordName.hasPrefix(
                    "membership_\(edge.collectionId.uuidString)_\(edge.recipeId.uuidString)_"
                )
            )
            XCTAssertNotEqual(
                record.recordID,
                CollectionCloudService.membershipRecordID(
                    collectionId: edge.collectionId,
                    recipeId: edge.recipeId
                )
            )
            let decodedEdge = try await service.membershipEdge(from: record)
            XCTAssertEqual(decodedEdge, edge)
        }
    }

    func testCanonicalUserAuthorityAcceptsCurrentAndLegacyRecordNames() {
        let userId = UUID().uuidString
        let identity = "_abc123"

        XCTAssertEqual(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: "user_\(identity)",
                storedUserID: userId,
                creatorRecordName: identity,
                expectedUserID: userId,
                currentIdentityRecordName: nil
            ),
            identity
        )
        XCTAssertEqual(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: identity,
                storedUserID: userId,
                creatorRecordName: identity,
                expectedUserID: userId,
                currentIdentityRecordName: nil
            ),
            identity
        )
    }

    func testCanonicalUserAuthorityRejectsWritableOwnerSpoofAndNoncanonicalRecord() {
        let expectedUserId = UUID().uuidString
        let attackerIdentity = "_attacker"

        XCTAssertNil(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: "user__victim",
                storedUserID: expectedUserId,
                creatorRecordName: attackerIdentity,
                expectedUserID: expectedUserId,
                currentIdentityRecordName: nil
            )
        )
        XCTAssertNil(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: "user_\(attackerIdentity)",
                storedUserID: UUID().uuidString,
                creatorRecordName: attackerIdentity,
                expectedUserID: expectedUserId,
                currentIdentityRecordName: nil
            )
        )
    }

    func testCanonicalUserAuthorityResolvesCurrentUserAliasOnlyWithKnownIdentity() {
        let userId = UUID().uuidString
        let identity = "_current"

        XCTAssertEqual(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: "user_\(identity)",
                storedUserID: userId,
                creatorRecordName: CKCurrentUserDefaultName,
                expectedUserID: userId,
                currentIdentityRecordName: identity
            ),
            identity
        )
        XCTAssertNil(
            CollectionCloudService.canonicalUserAuthorityRecordName(
                recordType: CloudKitCore.RecordType.user,
                recordName: "user_\(identity)",
                storedUserID: userId,
                creatorRecordName: CKCurrentUserDefaultName,
                expectedUserID: userId,
                currentIdentityRecordName: nil
            )
        )
    }

    func testCollectionStateCreatorMustMatchCanonicalAuthority() {
        let authority = "_owner"

        XCTAssertTrue(
            CollectionCloudService.recordCreatorMatchesAuthority(
                authority,
                authorityRecordName: authority,
                currentIdentityRecordName: nil
            )
        )
        XCTAssertFalse(
            CollectionCloudService.recordCreatorMatchesAuthority(
                "_attacker",
                authorityRecordName: authority,
                currentIdentityRecordName: nil
            )
        )
        XCTAssertFalse(
            CollectionCloudService.recordCreatorMatchesAuthority(
                nil,
                authorityRecordName: authority,
                currentIdentityRecordName: nil
            )
        )
        XCTAssertTrue(
            CollectionCloudService.recordCreatorMatchesAuthority(
                nil,
                authorityRecordName: authority,
                currentIdentityRecordName: nil,
                permitsUnclaimedRecord: true
            )
        )
    }

    func testCurrentUserAliasCannotAuthorizeAnotherOwner() {
        XCTAssertTrue(
            CollectionCloudService.recordCreatorMatchesAuthority(
                CKCurrentUserDefaultName,
                authorityRecordName: "_current",
                currentIdentityRecordName: "_current"
            )
        )
        XCTAssertFalse(
            CollectionCloudService.recordCreatorMatchesAuthority(
                CKCurrentUserDefaultName,
                authorityRecordName: "_friend",
                currentIdentityRecordName: "_current"
            )
        )
    }

    func testNewStateRecordIDsCannotBePreclaimedThroughLegacyDeterministicAlias() {
        let collectionID = UUID()
        let recipeID = UUID()
        let firstNonce = UUID()
        let secondNonce = UUID()

        let legacyCollection = CollectionCloudService.collectionRecordID(collectionId: collectionID)
        let newCollection = CollectionCloudService.newCollectionRecordID(
            collectionId: collectionID,
            nonce: firstNonce
        )
        XCTAssertNotEqual(newCollection, legacyCollection)
        XCTAssertEqual(legacyCollection.recordName, collectionID.uuidString)
        XCTAssertEqual(
            newCollection.recordName,
            "collection_\(collectionID.uuidString)_\(firstNonce.uuidString)"
        )

        let legacyTombstone = CollectionCloudService.deletedCollectionRecordID(collectionId: collectionID)
        let firstTombstone = CollectionCloudService.newDeletedCollectionRecordID(
            collectionId: collectionID,
            nonce: firstNonce
        )
        let secondTombstone = CollectionCloudService.newDeletedCollectionRecordID(
            collectionId: collectionID,
            nonce: secondNonce
        )
        XCTAssertNotEqual(firstTombstone, legacyTombstone)
        XCTAssertNotEqual(firstTombstone, secondTombstone)
        XCTAssertEqual(
            firstTombstone.recordName,
            "deletedCollection_\(collectionID.uuidString)_\(firstNonce.uuidString)"
        )

        let legacyMembership = CollectionCloudService.membershipRecordID(
            collectionId: collectionID,
            recipeId: recipeID
        )
        let newMembership = CollectionCloudService.newMembershipRecordID(
            collectionId: collectionID,
            recipeId: recipeID,
            nonce: firstNonce
        )
        XCTAssertNotEqual(newMembership, legacyMembership)
        XCTAssertEqual(
            newMembership.recordName,
            "membership_\(collectionID.uuidString)_\(recipeID.uuidString)_\(firstNonce.uuidString)"
        )
    }

    func testCollectionRecordIdentityRequiresOwnerLogicalIDAndPhysicalRecordName() {
        let identity = CollectionCloudIdentity(ownerId: UUID(), collectionId: UUID())
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: "physical-owner-record")
        )
        record["collectionId"] = identity.collectionId.uuidString as CKRecordValue
        record["userId"] = identity.ownerId.uuidString as CKRecordValue

        XCTAssertTrue(CollectionCloudService.collectionRecordMatchesIdentity(
            record,
            identity: identity,
            expectedRecordName: "physical-owner-record"
        ))
        XCTAssertFalse(CollectionCloudService.collectionRecordMatchesIdentity(
            record,
            identity: CollectionCloudIdentity(ownerId: UUID(), collectionId: identity.collectionId),
            expectedRecordName: "physical-owner-record"
        ))
        XCTAssertFalse(CollectionCloudService.collectionRecordMatchesIdentity(
            record,
            identity: identity,
            expectedRecordName: "attacker-record"
        ))
    }

    func testKnownPhysicalCollectionRecordSurvivesEmptyQueryIndexFallback() throws {
        let identity = CollectionCloudIdentity(ownerId: UUID(), collectionId: UUID())
        let expectedRecordName = "collection_\(identity.collectionId.uuidString)_\(UUID().uuidString)"
        let directRecord = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: expectedRecordName)
        )
        directRecord["collectionId"] = identity.collectionId.uuidString as CKRecordValue
        directRecord["userId"] = identity.ownerId.uuidString as CKRecordValue

        let validated = try CollectionCloudService.validatedKnownCollectionRecord(
            directRecord,
            identity: identity,
            expectedRecordName: expectedRecordName
        )

        XCTAssertEqual(validated.recordID.recordName, expectedRecordName)
    }

    func testKnownPhysicalCollectionRecordRejectsMismatchedLogicalIdentity() {
        let identity = CollectionCloudIdentity(ownerId: UUID(), collectionId: UUID())
        let expectedRecordName = "collection_\(identity.collectionId.uuidString)_\(UUID().uuidString)"
        let directRecord = CKRecord(
            recordType: CloudKitCore.RecordType.collection,
            recordID: CKRecord.ID(recordName: expectedRecordName)
        )
        directRecord["collectionId"] = identity.collectionId.uuidString as CKRecordValue
        directRecord["userId"] = UUID().uuidString as CKRecordValue

        XCTAssertThrowsError(try CollectionCloudService.validatedKnownCollectionRecord(
            directRecord,
            identity: identity,
            expectedRecordName: expectedRecordName
        ))
    }

    func testConflictSelectionUpdatesNewestRecordFromCanonicalCreatorOnly() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let candidates = [
            CreatorBoundRecordCandidate(
                recordName: "owner-old",
                creatorRecordName: "owner",
                updatedAt: old
            ),
            CreatorBoundRecordCandidate(
                recordName: "attacker-newest",
                creatorRecordName: "attacker",
                updatedAt: new.addingTimeInterval(100)
            ),
            CreatorBoundRecordCandidate(
                recordName: "owner-new",
                creatorRecordName: "owner",
                updatedAt: new
            ),
        ]

        XCTAssertEqual(
            CollectionCloudService.preferredCreatorBoundRecordName(
                candidates,
                authorityRecordName: "owner"
            ),
            "owner-new"
        )
        XCTAssertNil(
            CollectionCloudService.preferredCreatorBoundRecordName(
                candidates,
                authorityRecordName: "unknown"
            )
        )
    }

    func testCollectionCreatorTakesPriorityAndFallbackRequiresExactAuthenticatedCreator() {
        XCTAssertTrue(CollectionCloudService.collectionStateCreatorIsAuthorized(
            recordCreatorName: "collection-owner",
            collectionCreatorName: "collection-owner",
            fallbackAuthenticatedCreatorName: nil
        ))
        XCTAssertFalse(CollectionCloudService.collectionStateCreatorIsAuthorized(
            recordCreatorName: "attacker",
            collectionCreatorName: "collection-owner",
            fallbackAuthenticatedCreatorName: "attacker"
        ))
        XCTAssertTrue(CollectionCloudService.collectionStateCreatorIsAuthorized(
            recordCreatorName: "legacy-owner",
            collectionCreatorName: nil,
            fallbackAuthenticatedCreatorName: "legacy-owner"
        ))
        XCTAssertFalse(CollectionCloudService.collectionStateCreatorIsAuthorized(
            recordCreatorName: "attacker",
            collectionCreatorName: nil,
            fallbackAuthenticatedCreatorName: "legacy-owner"
        ))
        XCTAssertFalse(CollectionCloudService.collectionStateCreatorIsAuthorized(
            recordCreatorName: nil,
            collectionCreatorName: nil,
            fallbackAuthenticatedCreatorName: "legacy-owner"
        ))
    }

    func testDuplicateLogicalMembershipRecordsPreferNewestState() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let collectionID = UUID()
        let recipeID = UUID()
        let ownerID = UUID()
        let oldEdge = CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeID,
            ownerId: ownerID,
            status: .active,
            updatedAt: Date(timeIntervalSince1970: 100),
            sortOrder: 1
        )
        let newEdge = CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeID,
            ownerId: ownerID,
            status: .removed,
            updatedAt: Date(timeIntervalSince1970: 200),
            sortOrder: 1
        )
        let oldRecord = CKRecord(
            recordType: CloudKitCore.RecordType.collectionMembership,
            recordID: CKRecord.ID(recordName: "old")
        )
        let newRecord = CKRecord(
            recordType: CloudKitCore.RecordType.collectionMembership,
            recordID: CKRecord.ID(recordName: "new")
        )
        await service.populateMembershipRecord(oldRecord, from: oldEdge)
        await service.populateMembershipRecord(newRecord, from: newEdge)

        let selected = CollectionCloudService.deduplicatedMembershipRecords([oldRecord, newRecord])
        XCTAssertEqual(selected.map(\.recordID.recordName), ["new"])
    }

    func testPublicationLeaseWrapsWholeActualOperationDuringDeletionRace() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let ownerID = UUID()
        let operationEntered = expectation(description: "publication operation entered")
        let operationMayFinish = CollectionCloudServiceTestLatch()
        let deletionFinished = CollectionCloudServiceTestFlag()

        let publication = Task {
            try await service.withPublicationLease(ownerID: ownerID) {
                operationEntered.fulfill()
                await operationMayFinish.wait()
            }
        }
        await fulfillment(of: [operationEntered], timeout: 2)

        let deletion = Task {
            let lease = await AccountDeletionGate.shared.begin(ownerID: ownerID)
            await deletionFinished.set()
            return lease
        }
        for _ in 0..<100 {
            if !(await AccountDeletionGate.shared.permitsWrite(ownerID: ownerID)) { break }
            await Task.yield()
        }

        let permitsDuringDrain = await AccountDeletionGate.shared.permitsWrite(ownerID: ownerID)
        let deletionFinishedBeforeRelease = await deletionFinished.value
        XCTAssertFalse(permitsDuringDrain)
        XCTAssertFalse(deletionFinishedBeforeRelease)

        await operationMayFinish.open()
        try await publication.value
        let deletionLease = await deletion.value
        let deletionFinishedAfterRelease = await deletionFinished.value
        XCTAssertTrue(deletionFinishedAfterRelease)
        await AccountDeletionGate.shared.end(deletionLease)
    }

    func testPublicationLeaseActualPathRejectsOperationAfterDeletionAdmissionCloses() async throws {
        let service = CollectionCloudService(core: CloudKitCore())
        let ownerID = UUID()
        let deletionLease = await AccountDeletionGate.shared.begin(ownerID: ownerID)
        let operationRan = CollectionCloudServiceTestFlag()

        do {
            try await service.withPublicationLease(ownerID: ownerID) {
                await operationRan.set()
            }
            XCTFail("Expected deletion gate to reject publication")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .invalidRecord)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let didRun = await operationRan.value
        XCTAssertFalse(didRun)
        await AccountDeletionGate.shared.end(deletionLease)
    }
}

private actor CollectionCloudServiceTestLatch {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor CollectionCloudServiceTestFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}
