//
//  CollectionRepositoryTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class CollectionRepositoryTests: XCTestCase {

    func testCollectionOutboxResumesOnlyWhenSameCloudAccountIdentityReturns() async throws {
        let ownerID = UUID()
        let queue = OperationQueueService()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: UUID(),
            ownerId: ownerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-account-a"
        )
        let queuedValue = await queue.getOperation(operationId: operationID)
        let queued = try XCTUnwrap(queuedValue)
        let returningScope = SyncOperationAccountScope(
            ownerId: ownerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-account-a"
        )

        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: queued,
                entityOwnerId: ownerID,
                currentScope: SyncOperationAccountScope(
                    ownerId: ownerID,
                    revision: UUID(),
                    cloudKitIdentity: "icloud-account-b"
                )
            ),
            .deferred
        )
        XCTAssertEqual(
            SyncOperationAccountPolicy.decision(
                operation: queued,
                entityOwnerId: ownerID,
                currentScope: returningScope
            ),
            .migrateLegacy
        )

        let reboundValue = await queue.bindLegacyOperation(operationId: operationID, scope: returningScope)
        let rebound = try XCTUnwrap(reboundValue)
        XCTAssertEqual(rebound.accountIdentity, returningScope.cloudKitIdentity)
        XCTAssertEqual(rebound.accountRevision, returningScope.revision)
        XCTAssertEqual(rebound.status, .pending)
    }

    func testQueuedCollectionRebindMigratesLocalOwnerAndMembershipForSameICloudIdentity() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Legacy collection", userId: previousOwnerID)
        let recipeID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementRecorder = LegacyCollectionGraphRetirementRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            accountScopeProvider: { ownerID in ownerID == canonicalOwnerID ? scope : nil },
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { collectionID, previousOwnerID, canonicalOwnerID, recordNames in
                await retirementRecorder.record(
                    collectionID: collectionID,
                    previousOwnerID: previousOwnerID,
                    canonicalOwnerID: canonicalOwnerID,
                    expectedRecordName: recordNames.sorted().first
                )
                return recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let collectionModel = try CollectionModel.from(collection)
        collectionModel.cloudRecordName = "legacy-collection-record"
        collectionModel.cloudCoverImageRecordName = "legacy-cover-record"
        collectionModel.coverImageModifiedAt = Date()
        context.insert(collectionModel)
        context.insert(
            CollectionMembershipModel(
                collectionId: collection.id,
                recipeId: recipeID,
                ownerId: previousOwnerID
            )
        )
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let rebound = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(rebound.ownerId, canonicalOwnerID)
        XCTAssertEqual(rebound.accountRevision, scope.revision)
        XCTAssertEqual(rebound.status, .pending)
        let migratedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(migratedCollection?.userId, canonicalOwnerID)
        XCTAssertNil(migratedCollection?.cloudRecordName)
        XCTAssertNil(migratedCollection?.cloudCoverImageRecordName)
        XCTAssertNil(migratedCollection?.coverImageModifiedAt)
        let retirement = await retirementRecorder.lastRequest()
        XCTAssertEqual(retirement?.collectionID, collection.id)
        XCTAssertEqual(retirement?.previousOwnerID, previousOwnerID)
        XCTAssertEqual(retirement?.canonicalOwnerID, canonicalOwnerID)
        XCTAssertEqual(retirement?.expectedRecordName, "legacy-collection-record")
        let verificationContext = ModelContext(modelContainer)
        let collectionID = collection.id
        let memberships = try verificationContext.fetch(
            FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate { $0.collectionId == collectionID }
            )
        )
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships.first?.ownerId, canonicalOwnerID)
    }

    func testQueuedCollectionRebindRepairsCanonicalOnlyLocalState() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Already migrated", userId: canonicalOwnerID)
        let recipeID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementRecorder = LegacyCollectionGraphRetirementRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { collectionID, previousOwnerID, canonicalOwnerID, recordNames in
                await retirementRecorder.record(
                    collectionID: collectionID,
                    previousOwnerID: previousOwnerID,
                    canonicalOwnerID: canonicalOwnerID,
                    expectedRecordName: recordNames.sorted().first
                )
                return recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let collectionModel = try CollectionModel.from(collection)
        collectionModel.cloudRecordName = "legacy-collection-record"
        collectionModel.cloudCoverImageRecordName = "legacy-cover-record"
        collectionModel.coverImageModifiedAt = Date()
        context.insert(collectionModel)
        context.insert(
            CollectionMembershipModel(
                collectionId: collection.id,
                recipeId: recipeID,
                ownerId: canonicalOwnerID
            )
        )
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let rebound = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(rebound.ownerId, canonicalOwnerID)
        XCTAssertEqual(rebound.status, .pending)
        let repairedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(repairedCollection?.recipeIds, [recipeID])
        XCTAssertNil(repairedCollection?.cloudRecordName)
        XCTAssertNil(repairedCollection?.cloudCoverImageRecordName)
        XCTAssertNil(repairedCollection?.coverImageModifiedAt)
        let retirement = await retirementRecorder.lastRequest()
        XCTAssertEqual(retirement?.previousOwnerID, previousOwnerID)
        XCTAssertEqual(retirement?.canonicalOwnerID, canonicalOwnerID)
        XCTAssertEqual(retirement?.expectedRecordName, "legacy-collection-record")
    }

    func testQueuedCollectionRebindPreservesConfirmedCanonicalCloudRecord() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Canonical", userId: canonicalOwnerID)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let collectionModel = try CollectionModel.from(collection)
        collectionModel.cloudRecordName = "canonical-record"
        collectionModel.cloudCoverImageRecordName = "canonical-cover"
        let coverModifiedAt = Date()
        collectionModel.coverImageModifiedAt = coverModifiedAt
        context.insert(collectionModel)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let repairedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(repairedCollection?.cloudRecordName, "canonical-record")
        XCTAssertEqual(repairedCollection?.cloudCoverImageRecordName, "canonical-cover")
        XCTAssertEqual(repairedCollection?.coverImageModifiedAt, coverModifiedAt)
    }

    func testQueuedCollectionRebindDeduplicatesCoexistingOwnerGraphs() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let recipeID = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_000)
        let newerDate = Date(timeIntervalSince1970: 2_000)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let recordNamesRecorder = LegacyCollectionRecordNamesRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, recordNames in
                await recordNamesRecorder.record(recordNames)
                return recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let canonicalModel = CollectionModel(
            id: collectionID,
            name: "Older canonical",
            userId: canonicalOwnerID,
            cloudRecordName: "canonical-record",
            updatedAt: olderDate
        )
        let legacyModel = CollectionModel(
            id: collectionID,
            name: "Newer local edit",
            userId: previousOwnerID,
            cloudRecordName: "legacy-record",
            updatedAt: newerDate
        )
        let duplicateLegacyModel = CollectionModel(
            id: collectionID,
            name: "Old duplicate",
            userId: previousOwnerID,
            cloudRecordName: "legacy-record-2",
            updatedAt: olderDate
        )
        context.insert(canonicalModel)
        context.insert(legacyModel)
        context.insert(duplicateLegacyModel)
        context.insert(
            CollectionMembershipModel(
                collectionId: collectionID,
                recipeId: recipeID,
                ownerId: canonicalOwnerID,
                status: CollectionMembershipStatus.removed.rawValue,
                updatedAt: olderDate
            )
        )
        context.insert(
            CollectionMembershipModel(
                collectionId: collectionID,
                recipeId: recipeID,
                ownerId: previousOwnerID,
                status: CollectionMembershipStatus.active.rawValue,
                updatedAt: newerDate
            )
        )
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let verificationContext = ModelContext(modelContainer)
        let collections = try verificationContext.fetch(
            FetchDescriptor<CollectionModel>(
                predicate: #Predicate {
                    $0.id == collectionID && $0.userId == canonicalOwnerID
                }
            )
        )
        let memberships = try verificationContext.fetch(
            FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate {
                    $0.collectionId == collectionID && $0.ownerId == canonicalOwnerID
                }
            )
        )
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first?.name, "Newer local edit")
        XCTAssertNil(collections.first?.cloudRecordName)
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships.first?.status, CollectionMembershipStatus.active.rawValue)
        let retiredNames = await recordNamesRecorder.lastRecordNames()
        XCTAssertEqual(retiredNames, ["canonical-record", "legacy-record", "legacy-record-2"])
    }

    func testQueuedCollectionRebindUsesStableContentTieBreakForCollections() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let tiedDate = Date(timeIntervalSince1970: 3_000)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let emptyRecipeIDs = try JSONEncoder().encode([UUID]())
        context.insert(
            CollectionModel(
                id: collectionID,
                name: "Same name",
                descriptionText: "Alpha",
                userId: canonicalOwnerID,
                recipeIdsBlob: emptyRecipeIDs,
                createdAt: tiedDate,
                updatedAt: tiedDate
            )
        )
        context.insert(
            CollectionModel(
                id: collectionID,
                name: "Same name",
                descriptionText: "Zulu",
                userId: canonicalOwnerID,
                recipeIdsBlob: emptyRecipeIDs,
                createdAt: tiedDate,
                updatedAt: tiedDate
            )
        )
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let repairedCollection = try await scopedRepository.fetch(
            id: collectionID,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(repairedCollection?.description, "Zulu")
        let verificationContext = ModelContext(modelContainer)
        let collections = try verificationContext.fetch(
            FetchDescriptor<CollectionModel>(
                predicate: #Predicate {
                    $0.id == collectionID && $0.userId == canonicalOwnerID
                }
            )
        )
        XCTAssertEqual(collections.count, 1)
    }

    func testQueuedCollectionRebindIgnoresMalformedTombstone() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Keep me", userId: canonicalOwnerID)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(collection))
        let malformedTombstone = DeletedCollectionModel(
            collectionId: collection.id,
            ownerId: canonicalOwnerID,
            deletedAt: Date(),
            cloudRecordName: nil
        )
        malformedTombstone.deletedAt = nil
        context.insert(malformedTombstone)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let repairedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(repairedCollection?.name, "Keep me")
        let verificationContext = ModelContext(modelContainer)
        let collectionID = collection.id
        let tombstones = try verificationContext.fetch(
            FetchDescriptor<DeletedCollectionModel>(
                predicate: #Predicate { $0.collectionId == collectionID }
            )
        )
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testQueuedCollectionRebindMalformedTombstoneDoesNotRetireRemoteOnlyCopy() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementRecorder = LegacyCollectionGraphRetirementRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { collectionID, previousOwnerID, canonicalOwnerID, recordNames in
                await retirementRecorder.record(
                    collectionID: collectionID,
                    previousOwnerID: previousOwnerID,
                    canonicalOwnerID: canonicalOwnerID,
                    expectedRecordName: recordNames.sorted().first
                )
                return recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let malformedTombstone = DeletedCollectionModel(
            collectionId: collectionID,
            ownerId: previousOwnerID,
            deletedAt: Date(),
            cloudRecordName: "remote-only-record"
        )
        malformedTombstone.deletedAt = nil
        context.insert(malformedTombstone)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let completed = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(completed.status, .completed)
        let retirement = await retirementRecorder.lastRequest()
        let remainingOperation = await queue.getOperation(operationId: operationID)
        XCTAssertNil(retirement)
        XCTAssertNil(remainingOperation)
    }

    func testQueuedCollectionRebindMembershipRemovalWinsTimestampTie() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Tie", userId: canonicalOwnerID)
        let recipeID = UUID()
        let tiedDate = Date(timeIntervalSince1970: 5_000)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(collection))
        context.insert(
            CollectionMembershipModel(
                collectionId: collection.id,
                recipeId: recipeID,
                ownerId: canonicalOwnerID,
                status: CollectionMembershipStatus.active.rawValue,
                updatedAt: tiedDate
            )
        )
        context.insert(
            CollectionMembershipModel(
                collectionId: collection.id,
                recipeId: recipeID,
                ownerId: previousOwnerID,
                status: CollectionMembershipStatus.removed.rawValue,
                updatedAt: tiedDate
            )
        )
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let verificationContext = ModelContext(modelContainer)
        let collectionID = collection.id
        let memberships = try verificationContext.fetch(
            FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate {
                    $0.collectionId == collectionID && $0.ownerId == canonicalOwnerID
                }
            )
        )
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships.first?.status, CollectionMembershipStatus.removed.rawValue)
    }

    func testQueuedCollectionDeleteRemovesCanonicalActiveGraph() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Delete me", userId: canonicalOwnerID)
        let recipeID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(collection))
        context.insert(
            CollectionMembershipModel(
                collectionId: collection.id,
                recipeId: recipeID,
                ownerId: canonicalOwnerID
            )
        )
        try context.save()
        let payload = try JSONEncoder().encode(
            CollectionRepository.CollectionDeletePayload(
                collectionId: collection.id,
                ownerId: previousOwnerID
            )
        )
        let operationID = await queue.addOperation(
            type: .delete,
            entityType: .collection,
            entityId: collection.id,
            payload: payload,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        _ = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let verificationContext = ModelContext(modelContainer)
        let collectionID = collection.id
        let collections = try verificationContext.fetch(
            FetchDescriptor<CollectionModel>(predicate: #Predicate { $0.id == collectionID })
        )
        let tombstones = try verificationContext.fetch(
            FetchDescriptor<DeletedCollectionModel>(
                predicate: #Predicate {
                    $0.collectionId == collectionID && $0.ownerId == canonicalOwnerID
                }
            )
        )
        let memberships = try verificationContext.fetch(
            FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate {
                    $0.collectionId == collectionID && $0.ownerId == canonicalOwnerID
                }
            )
        )
        XCTAssertTrue(collections.isEmpty)
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(memberships.count, 1)
        XCTAssertEqual(memberships.first?.status, CollectionMembershipStatus.removed.rawValue)
    }

    func testQueuedCollectionDeleteRebindsFromPayloadWhenLocalStateAlreadyDisappeared() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementRecorder = LegacyCollectionGraphRetirementRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { collectionID, previousOwnerID, canonicalOwnerID, recordNames in
                await retirementRecorder.record(
                    collectionID: collectionID,
                    previousOwnerID: previousOwnerID,
                    canonicalOwnerID: canonicalOwnerID,
                    expectedRecordName: recordNames.sorted().first
                )
                return []
            },
            enforcesVerifiedAccountScope: true
        )
        let payload = try JSONEncoder().encode(
            CollectionRepository.CollectionDeletePayload(
                collectionId: collectionID,
                ownerId: previousOwnerID
            )
        )
        let operationID = await queue.addOperation(
            type: .delete,
            entityType: .collection,
            entityId: collectionID,
            payload: payload,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let rebound = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(rebound.ownerId, canonicalOwnerID)
        XCTAssertEqual(rebound.status, .pending)
        let reboundData = try XCTUnwrap(rebound.payload)
        let reboundPayload = try JSONDecoder().decode(
            CollectionRepository.CollectionDeletePayload.self,
            from: reboundData
        )
        XCTAssertEqual(reboundPayload.collectionId, collectionID)
        XCTAssertEqual(reboundPayload.ownerId, canonicalOwnerID)
        let retirement = await retirementRecorder.lastRequest()
        XCTAssertEqual(retirement?.collectionID, collectionID)
        XCTAssertNil(retirement?.expectedRecordName)
    }

    func testQueuedCollectionRebindCompletesStateLessUpsertWithoutRemoteRetirement() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementRecorder = LegacyCollectionGraphRetirementRecorder()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { collectionID, previousOwnerID, canonicalOwnerID, recordNames in
                await retirementRecorder.record(
                    collectionID: collectionID,
                    previousOwnerID: previousOwnerID,
                    canonicalOwnerID: canonicalOwnerID,
                    expectedRecordName: recordNames.sorted().first
                )
                return []
            },
            enforcesVerifiedAccountScope: true
        )
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let rebound = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(rebound.ownerId, previousOwnerID)
        XCTAssertEqual(rebound.status, .completed)
        let remainingOperation = await queue.getOperation(operationId: rebound.id)
        XCTAssertNil(remainingOperation)
        let retirement = await retirementRecorder.lastRequest()
        XCTAssertNil(retirement)
    }

    func testQueuedCollectionRebindDoesNotMigrateDifferentICloudIdentity() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Other account", userId: previousOwnerID)
        let queue = OperationQueueService()
        let currentScope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-B"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { currentScope },
            legacyCollectionGraphRetirer: { _, _, _, _ in [] },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(collection))
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let unchanged = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertEqual(unchanged.ownerId, previousOwnerID)
        let oldOwnerCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: previousOwnerID
        )
        XCTAssertEqual(oldOwnerCollection?.userId, previousOwnerID)
    }

    func testQueuedCollectionDeleteRebindMigratesTombstoneAndPayloadOwner() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, recordNames in
                recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        context.insert(
            DeletedCollectionModel(
                collectionId: collectionID,
                ownerId: previousOwnerID,
                deletedAt: Date(),
                cloudRecordName: "legacy-deleted-collection-record"
            )
        )
        try context.save()
        let oldPayload = try JSONEncoder().encode(
            CollectionRepository.CollectionDeletePayload(
                collectionId: collectionID,
                ownerId: previousOwnerID
            )
        )
        let operationID = await queue.addOperation(
            type: .delete,
            entityType: .collection,
            entityId: collectionID,
            payload: oldPayload,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let rebound = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        let payloadData = try XCTUnwrap(rebound.payload)
        let payload = try JSONDecoder().decode(
            CollectionRepository.CollectionDeletePayload.self,
            from: payloadData
        )
        XCTAssertEqual(payload.ownerId, canonicalOwnerID)
        let verificationContext = ModelContext(modelContainer)
        let tombstones = try verificationContext.fetch(
            FetchDescriptor<DeletedCollectionModel>(
                predicate: #Predicate { $0.collectionId == collectionID }
            )
        )
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.ownerId, canonicalOwnerID)
        XCTAssertNil(tombstones.first?.cloudRecordName)
    }

    func testQueuedCollectionRebindIncludesEditCommittedDuringCloudRetirement() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let retirementGate = LegacyCollectionRetirementGate()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, recordNames in
                await retirementGate.suspend(returning: recordNames)
            },
            enforcesVerifiedAccountScope: true
        )
        let initialDate = Date(timeIntervalSince1970: 1_000)
        let concurrentEditDate = Date(timeIntervalSince1970: 2_000)
        let context = ModelContext(modelContainer)
        let model = CollectionModel(
            id: collectionID,
            name: "Before retirement",
            userId: previousOwnerID,
            cloudRecordName: "legacy-record",
            updatedAt: initialDate
        )
        model.recipeIdsBlob = try JSONEncoder().encode([UUID]())
        context.insert(model)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let reconciliation = Task {
            try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)
        }
        await retirementGate.waitUntilSuspended()

        let editingContext = ModelContext(modelContainer)
        let editDescriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate {
                $0.id == collectionID && $0.userId == previousOwnerID
            }
        )
        let editedModel = try XCTUnwrap(editingContext.fetch(editDescriptor).first)
        editedModel.name = "Edited while retiring"
        editedModel.updatedAt = concurrentEditDate
        try editingContext.save()

        await retirementGate.resume()
        _ = try await reconciliation.value

        let repaired = try await scopedRepository.fetch(
            id: collectionID,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(repaired?.name, "Edited while retiring")
        XCTAssertEqual(repaired?.updatedAt, concurrentEditDate)
    }

    func testQueuedCollectionRebindStopsWhenAccountScopeChangesDuringCloudRetirement() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collectionID = UUID()
        let queue = OperationQueueService()
        let originalScope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        var activeScope: SyncOperationAccountScope? = originalScope
        let retirementGate = LegacyCollectionRetirementGate()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { activeScope },
            legacyCollectionGraphRetirer: { _, _, _, recordNames in
                await retirementGate.suspend(returning: recordNames)
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let model = CollectionModel(
            id: collectionID,
            name: "Original account data",
            userId: previousOwnerID,
            cloudRecordName: "legacy-record"
        )
        model.recipeIdsBlob = try JSONEncoder().encode([UUID]())
        context.insert(model)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collectionID,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)

        let reconciliation = Task {
            try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)
        }
        await retirementGate.waitUntilSuspended()
        activeScope = SyncOperationAccountScope(
            ownerId: UUID(),
            revision: UUID(),
            cloudKitIdentity: "icloud-B"
        )
        await retirementGate.resume()

        do {
            _ = try await reconciliation.value
            XCTFail("Expected a changed account scope to abort local owner repair")
        } catch let error as CollectionRepositoryError {
            XCTAssertEqual(error, .accountIdentityNotVerified)
        }

        let verificationContext = ModelContext(modelContainer)
        let collections = try verificationContext.fetch(FetchDescriptor<CollectionModel>(
            predicate: #Predicate { $0.id == collectionID }
        ))
        XCTAssertEqual(collections.count, 1)
        XCTAssertEqual(collections.first?.userId, previousOwnerID)
        XCTAssertEqual(collections.first?.cloudRecordName, "legacy-record")
        let unchangedOperation = await queue.getOperation(operationId: operationID)
        XCTAssertEqual(unchangedOperation?.ownerId, previousOwnerID)
    }

    func testQueuedCollectionRebindReplacesOutboxItemWhenLegacyItemDisappears() async throws {
        let previousOwnerID = UUID()
        let canonicalOwnerID = UUID()
        let collection = Collection.new(name: "Racing collection", userId: previousOwnerID)
        let queue = OperationQueueService()
        let scope = SyncOperationAccountScope(
            ownerId: canonicalOwnerID,
            revision: UUID(),
            cloudKitIdentity: "icloud-A"
        )
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: queue,
            currentAccountScopeProvider: { scope },
            legacyCollectionGraphRetirer: { _, _, _, recordNames in
                recordNames
            },
            enforcesVerifiedAccountScope: true
        )
        let context = ModelContext(modelContainer)
        let collectionModel = try CollectionModel.from(collection)
        collectionModel.cloudRecordName = "legacy-collection-record"
        collectionModel.cloudCoverImageRecordName = "legacy-cover-record"
        collectionModel.coverImageModifiedAt = Date()
        context.insert(collectionModel)
        try context.save()
        let operationID = await queue.addOperation(
            type: .update,
            entityType: .collection,
            entityId: collection.id,
            ownerId: previousOwnerID,
            accountRevision: UUID(),
            accountIdentity: "icloud-A"
        )
        let queuedOperation = await queue.getOperation(operationId: operationID)
        let operation = try XCTUnwrap(queuedOperation)
        await queue.removeOperation(operationId: operationID)

        let replacement = try await scopedRepository.reconcileQueuedCollectionOwnerIfNeeded(operation)

        XCTAssertNotEqual(replacement.id, operationID)
        XCTAssertEqual(replacement.ownerId, canonicalOwnerID)
        XCTAssertEqual(replacement.accountIdentity, scope.cloudKitIdentity)
        let oldOwnerCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: previousOwnerID
        )
        XCTAssertNil(oldOwnerCollection)
        let canonicalCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: canonicalOwnerID
        )
        XCTAssertEqual(canonicalCollection?.userId, canonicalOwnerID)
        XCTAssertNil(canonicalCollection?.cloudRecordName)
        XCTAssertNil(canonicalCollection?.cloudCoverImageRecordName)
    }

    var repository: CollectionRepository!
    var cloudKitCore: CloudKitCore!
    var collectionCloudService: CollectionCloudService!
    var modelContainer: ModelContainer!
    var testUserId: UUID!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        CurrentUserSession.shared.signOut()

        // Create in-memory model container for testing
        modelContainer = try TestModelContainer.create(with: [
            CollectionModel.self,
            CollectionMembershipModel.self,
            DeletedCollectionModel.self
        ])

        // Create CloudKit services (will use real services)
        // Note: CloudKit operations will fail in tests, but that's okay for local operations
        cloudKitCore = CloudKitCore()
        collectionCloudService = CollectionCloudService(core: cloudKitCore)

        // Initialize repository
        repository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: OperationQueueService()
        )

        // Create test user ID
        testUserId = UUID()
    }

    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        repository = nil
        cloudKitCore = nil
        collectionCloudService = nil
        modelContainer = nil
        testUserId = nil
        try await super.tearDown()
    }

    private func setCurrentUser(id: UUID) {
        CurrentUserSession.shared.replaceCurrentUserIfChanged(
            User(
                id: id,
                username: "test-\(id.uuidString.prefix(6))",
                displayName: "Test User",
                createdAt: Date()
            )
        )
    }

    // MARK: - Create Tests

    func testCreateRequiresCompleteVerifiedScopeBeforeLocalCommit() async throws {
        let isolatedQueue = OperationQueueService()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: isolatedQueue,
            accountScopeProvider: { _ in nil },
            enforcesVerifiedAccountScope: true
        )
        let collection = Collection.new(name: "Must not commit", userId: testUserId)

        do {
            try await scopedRepository.create(collection)
            XCTFail("Expected account verification to block the mutation")
        } catch CollectionRepositoryError.accountIdentityNotVerified {
            // Expected: no partial local row and no nil-revision queue entry.
        }

        let persistedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: testUserId
        )
        let queuedOperations = await isolatedQueue.getAllOperations()
        XCTAssertNil(persistedCollection)
        XCTAssertTrue(queuedOperations.isEmpty)
    }

    func testCreateAcceptsCompleteScopeBeforeLocalCommit() async throws {
        let revision = UUID()
        let scopedRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: OperationQueueService(),
            accountScopeProvider: { ownerID in
                SyncOperationAccountScope(ownerId: ownerID, revision: revision)
            },
            enforcesVerifiedAccountScope: true
        )
        let collection = Collection.new(name: "Verified commit", userId: testUserId)

        try await scopedRepository.create(collection)

        let persistedCollection = try await scopedRepository.fetch(
            id: collection.id,
            preferredOwnerId: testUserId
        )
        XCTAssertEqual(persistedCollection?.name, "Verified commit")
    }

    func testImmediateCoverMutationPrefersNewlySavedPhysicalRecordAndKeepsLegacyFallback() {
        XCTAssertEqual(
            CollectionRepository.coverMutationRecordName(
                newlySavedRecordName: "collection-random-physical-id",
                legacyRecordName: "legacy-uuid-id"
            ),
            "collection-random-physical-id"
        )
        XCTAssertEqual(
            CollectionRepository.coverMutationRecordName(
                newlySavedRecordName: nil,
                legacyRecordName: "legacy-uuid-id"
            ),
            "legacy-uuid-id"
        )
    }

    func testCollectionDeletionSyncPolicyRequiresRemoteTombstoneBeforeActiveDelete() {
        XCTAssertTrue(CollectionDeletionSyncPolicy.canDeleteActiveRecord(tombstoneSaveError: nil))
        XCTAssertFalse(
            CollectionDeletionSyncPolicy.canDeleteActiveRecord(
                tombstoneSaveError: NSError(domain: "CloudKit", code: 11)
            )
        )
    }

    func testCollectionDeleteReplayPolicyRequiresTombstoneOrOwnerPayload() throws {
        XCTAssertNil(
            CollectionDeleteReplayPolicy.tombstoneForReplay(
                localTombstone: nil,
                payloadData: nil,
                defaultDeletedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
    }

    func testCollectionDeleteReplayPolicySynthesizesTombstoneFromQueuedPayload() throws {
        let collectionId = UUID()
        let ownerId = UUID()
        let deletedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = CollectionRepository.CollectionDeletePayload(
            collectionId: collectionId,
            ownerId: ownerId
        )

        let tombstone = CollectionDeleteReplayPolicy.tombstoneForReplay(
            localTombstone: nil,
            payloadData: try JSONEncoder().encode(payload),
            defaultDeletedAt: deletedAt
        )

        XCTAssertEqual(tombstone?.collectionId, collectionId)
        XCTAssertEqual(tombstone?.ownerId, ownerId)
        XCTAssertEqual(tombstone?.deletedAt, deletedAt)
    }

    func testCollectionSuppressedActiveRecordCleanupCanUseLocalTombstone() {
        let collectionId = UUID()
        let ownerId = UUID()
        let tombstone = DeletedCollectionTombstone(
            collectionId: collectionId,
            ownerId: ownerId,
            deletedAt: Date(timeIntervalSince1970: 1_700_000_000),
            cloudRecordName: "collection-record",
            sourceDeviceId: "test-device"
        )

        let selected = CollectionDeleteReplayPolicy.tombstoneForSuppressedActiveRecord(
            localTombstone: tombstone,
            remoteTombstone: nil
        )

        XCTAssertEqual(selected?.collectionId, collectionId)
        XCTAssertEqual(selected?.ownerId, ownerId)
    }

    func testCollectionSuppressedActiveRecordCleanupRequiresAnyTombstone() {
        XCTAssertNil(
            CollectionDeleteReplayPolicy.tombstoneForSuppressedActiveRecord(
                localTombstone: nil,
                remoteTombstone: nil
            )
        )
    }

    func testCreate_SavesCollectionLocally() async throws {
        // Given
        let collection = Collection.new(name: "Test Collection", userId: testUserId)

        // When
        try await repository.create(collection)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Test Collection")
        XCTAssertEqual(fetched?.userId, testUserId)
    }

    func testNewCollectionDefaultsPublic() {
        let collection = Collection.new(name: "Test Collection", userId: testUserId)

        XCTAssertEqual(collection.visibility, .publicRecipe)
    }

    func testCreate_MultipleCollections() async throws {
        // Given
        let collection1 = Collection.new(name: "Collection 1", userId: testUserId)
        let collection2 = Collection.new(name: "Collection 2", userId: testUserId)

        // When
        try await repository.create(collection1)
        try await repository.create(collection2)

        // Then
        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 2)
    }

    // MARK: - Fetch Tests

    func testFetchAll_EmptyList() async throws {
        // When
        let collections = try await repository.fetchAll()

        // Then
        XCTAssertEqual(collections.count, 0)
    }

    func testFetchAll_ReturnsAllCollections() async throws {
        // Given
        let collection1 = Collection.new(name: "Collection 1", userId: testUserId)
        let collection2 = Collection.new(name: "Collection 2", userId: testUserId)

        try await repository.create(collection1)
        try await repository.create(collection2)

        // When
        let collections = try await repository.fetchAll()

        // Then
        XCTAssertEqual(collections.count, 2)
        XCTAssertTrue(collections.contains { $0.id == collection1.id })
        XCTAssertTrue(collections.contains { $0.id == collection2.id })
    }

    func testFetchUserCollectionsReturnsOnlyRequestedOwnerCollections() async throws {
        let otherUserId = UUID()
        let ownedCollection = Collection.new(name: "Mine", userId: testUserId)
        let otherCollection = Collection.new(name: "Not Mine", userId: otherUserId)
        let privateOwnedCollection = Collection.new(name: "Private Mine", userId: testUserId)
            .updated(visibility: .privateRecipe)

        try await repository.create(ownedCollection)
        try await repository.create(otherCollection)
        try await repository.create(privateOwnedCollection)

        let results = try await repository.fetchUserCollections(ownerId: testUserId)
        let publicResults = try await repository.fetchUserCollections(
            ownerId: testUserId,
            visibility: .publicRecipe
        )

        XCTAssertEqual(Set(results.map(\.id)), Set([ownedCollection.id, privateOwnedCollection.id]))
        XCTAssertEqual(Set(publicResults.map(\.id)), Set([ownedCollection.id]))
    }

    func testFetch_ById_Found() async throws {
        // Given
        let collection = Collection.new(name: "Test Collection", userId: testUserId)
        try await repository.create(collection)

        // When
        let fetched = try await repository.fetch(id: collection.id)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, collection.id)
        XCTAssertEqual(fetched?.name, "Test Collection")
    }

    func testFetch_ById_NotFound() async throws {
        // When
        let fetched = try await repository.fetch(id: UUID())

        // Then
        XCTAssertNil(fetched)
    }

    func testFetchCollections_ContainingRecipe() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()

        let collection1 = Collection(
            name: "Collection 1",
            userId: testUserId,
            recipeIds: [recipeId1, recipeId2]
        )
        let collection2 = Collection(
            name: "Collection 2",
            userId: testUserId,
            recipeIds: [recipeId2]
        )
        let collection3 = Collection(
            name: "Collection 3",
            userId: testUserId,
            recipeIds: []
        )

        try await repository.create(collection1)
        try await repository.create(collection2)
        try await repository.create(collection3)

        // When
        let collections = try await repository.fetchCollections(containingRecipe: recipeId2)

        // Then
        XCTAssertEqual(collections.count, 2)
        XCTAssertTrue(collections.contains { $0.id == collection1.id })
        XCTAssertTrue(collections.contains { $0.id == collection2.id })
        XCTAssertFalse(collections.contains { $0.id == collection3.id })
    }

    // MARK: - Update Tests

    func testUpdate_UpdatesCollectionProperties() async throws {
        // Given
        let collection = Collection.new(name: "Original Name", userId: testUserId)
        try await repository.create(collection)

        // When
        let updated = collection.updated(
            name: "Updated Name",
            description: "New description"
        )
        try await repository.update(updated)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertEqual(fetched?.name, "Updated Name")
        XCTAssertEqual(fetched?.description, "New description")
    }

    func testUpdate_ClearsDescription() async throws {
        // Given
        let collection = Collection(
            name: "Original Name",
            description: "Old description",
            userId: testUserId
        )
        try await repository.create(collection)

        // When
        let updated = collection.updated(clearDescription: true)
        try await repository.update(updated)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertNil(fetched?.description)
    }

    func testUpdate_UpdatesTimestamp_WhenShouldUpdateTimestampIsTrue() async throws {
        // Given
        let collection = Collection.new(name: "Test", userId: testUserId)
        try await repository.create(collection)

        // Sleep briefly to ensure timestamp difference
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // When
        let updated = collection.updated(name: "Updated")
        try await repository.update(updated, shouldUpdateTimestamp: true)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertNotNil(fetched)
        // Updated timestamp should be newer than original
        XCTAssertGreaterThan(fetched!.updatedAt, collection.updatedAt)
    }

    // NOTE: Skipping timestamp preservation test as it's affected by CloudKit sync behavior
    // The repository correctly preserves timestamps in local storage, but CloudKit sync
    // may update them. This is integration-level behavior, not unit test scope.
    /*
    func testUpdate_PreservesTimestamp_WhenShouldUpdateTimestampIsFalse() async throws {
        // Given
        let originalDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let collection = Collection(
            name: "Test",
            userId: testUserId,
            updatedAt: originalDate
        )
        try await repository.create(collection)

        // When
        let updated = collection.updated(name: "Updated")
        try await repository.update(updated, shouldUpdateTimestamp: false)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "Updated")
        // Timestamp should be preserved
        if let fetchedDate = fetched?.updatedAt {
            XCTAssertEqual(fetchedDate.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 1.0)
        } else {
            XCTFail("Updated collection should exist")
        }
    }
    */

    func testUpdate_NonExistentCollection_ThrowsError() async throws {
        // Given
        let collection = Collection.new(name: "Test", userId: testUserId)

        // When/Then
        do {
            try await repository.update(collection)
            XCTFail("Expected error to be thrown")
        } catch CollectionRepositoryError.collectionNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdate_NonOwnedCollection_IsIntentionallyNonDisclosing() async throws {
        // Given
        let ownerId = UUID()
        let otherUserId = UUID()
        let collection = Collection.new(name: "Shared Collection", userId: ownerId)
        try await repository.create(collection)
        setCurrentUser(id: otherUserId)

        // When/Then
        do {
            try await repository.update(collection.updated(name: "Should Not Save"))
            XCTFail("Expected collectionNotFound error")
        } catch CollectionRepositoryError.collectionNotFound {
            // Intentionally indistinguishable from an absent collection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Add/Remove Recipe Tests

    func testAddRecipe_AddsRecipeToCollection() async throws {
        // Given
        let collection = Collection.new(name: "Test Collection", userId: testUserId)
        try await repository.create(collection)
        let recipeId = UUID()

        // When
        try await repository.addRecipe(recipeId, to: collection.id)

        // Then
        let updated = try await repository.fetch(id: collection.id)
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.recipeCount, 1)
        XCTAssertTrue(updated?.recipeIds.contains(recipeId) ?? false)
    }

    func testAddRecipe_ToNonExistentCollection_ThrowsError() async throws {
        // Given
        let recipeId = UUID()
        let collectionId = UUID()

        // When/Then
        do {
            try await repository.addRecipe(recipeId, to: collectionId)
            XCTFail("Expected error to be thrown")
        } catch CollectionRepositoryError.collectionNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAddRecipe_MultipleRecipes() async throws {
        // Given
        let collection = Collection.new(name: "Test Collection", userId: testUserId)
        try await repository.create(collection)
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let recipeId3 = UUID()

        // When
        try await repository.addRecipe(recipeId1, to: collection.id)
        try await repository.addRecipe(recipeId2, to: collection.id)
        try await repository.addRecipe(recipeId3, to: collection.id)

        // Then
        let updated = try await repository.fetch(id: collection.id)
        XCTAssertEqual(updated?.recipeCount, 3)
        XCTAssertTrue(updated?.recipeIds.contains(recipeId1) ?? false)
        XCTAssertTrue(updated?.recipeIds.contains(recipeId2) ?? false)
        XCTAssertTrue(updated?.recipeIds.contains(recipeId3) ?? false)
    }

    func testAddRecipe_ToNonOwnedCollection_IsIntentionallyNonDisclosing() async throws {
        // Given
        let ownerId = UUID()
        let otherUserId = UUID()
        let collection = Collection.new(name: "Shared Collection", userId: ownerId)
        try await repository.create(collection)
        setCurrentUser(id: otherUserId)

        // When/Then
        do {
            try await repository.addRecipe(UUID(), to: collection.id)
            XCTFail("Expected collectionNotFound error")
        } catch CollectionRepositoryError.collectionNotFound {
            // Intentionally indistinguishable from an absent collection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveRecipe_RemovesRecipeFromCollection() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let collection = Collection(
            name: "Test Collection",
            userId: testUserId,
            recipeIds: [recipeId1, recipeId2]
        )
        try await repository.create(collection)

        // When
        try await repository.removeRecipe(recipeId1, from: collection.id)

        // Then
        let updated = try await repository.fetch(id: collection.id)
        XCTAssertEqual(updated?.recipeCount, 1)
        XCTAssertFalse(updated?.recipeIds.contains(recipeId1) ?? true)
        XCTAssertTrue(updated?.recipeIds.contains(recipeId2) ?? false)
    }

    func testFetch_UsesMembershipRemovalOverStaleLegacyRecipeIdsBlob() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let collection = Collection(
            name: "Test Collection",
            userId: testUserId,
            recipeIds: [recipeId1, recipeId2]
        )
        try await repository.create(collection)

        // When
        try await repository.removeRecipe(recipeId2, from: collection.id)

        // Simulate an older synced collection record still carrying the removed recipe
        // in its legacy recipeIds blob.
        let context = ModelContext(modelContainer)
        let collectionId = collection.id
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { $0.id == collectionId }
        )
        let model = try XCTUnwrap(context.fetch(descriptor).first)
        model.recipeIdsBlob = try JSONEncoder().encode([recipeId1, recipeId2])
        try context.save()

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertEqual(fetched?.recipeIds, [recipeId1])
    }

    func testRemoveRecipe_DiffsAgainstMembershipOverlayWhenLegacyRecipeIdsBlobIsStale() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let collection = Collection(
            name: "Test Collection",
            userId: testUserId,
            recipeIds: [recipeId1]
        )
        try await repository.create(collection)
        try await repository.addRecipe(recipeId2, to: collection.id)

        // Simulate a stale local/cloud collection model that predates the add.
        let context = ModelContext(modelContainer)
        let collectionId = collection.id
        let descriptor = FetchDescriptor<CollectionModel>(
            predicate: #Predicate { $0.id == collectionId }
        )
        let model = try XCTUnwrap(context.fetch(descriptor).first)
        model.recipeIdsBlob = try JSONEncoder().encode([recipeId1])
        try context.save()

        // When
        try await repository.removeRecipe(recipeId2, from: collection.id)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertEqual(fetched?.recipeIds, [recipeId1])
        XCTAssertFalse(fetched?.recipeIds.contains(recipeId2) ?? true)
    }

    func testRemoveRecipe_FromNonExistentCollection_ThrowsError() async throws {
        // Given
        let recipeId = UUID()
        let collectionId = UUID()

        // When/Then
        do {
            try await repository.removeRecipe(recipeId, from: collectionId)
            XCTFail("Expected error to be thrown")
        } catch CollectionRepositoryError.collectionNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRemoveRecipeFromAllCollections() async throws {
        // Given
        let recipeId = UUID()
        let collection1 = Collection(
            name: "Collection 1",
            userId: testUserId,
            recipeIds: [recipeId]
        )
        let collection2 = Collection(
            name: "Collection 2",
            userId: testUserId,
            recipeIds: [recipeId, UUID()]
        )
        let collection3 = Collection(
            name: "Collection 3",
            userId: testUserId,
            recipeIds: [UUID()]
        )

        try await repository.create(collection1)
        try await repository.create(collection2)
        try await repository.create(collection3)

        // When
        try await repository.removeRecipeFromAllCollections(recipeId)

        // Then
        let updated1 = try await repository.fetch(id: collection1.id)
        let updated2 = try await repository.fetch(id: collection2.id)
        let updated3 = try await repository.fetch(id: collection3.id)

        XCTAssertEqual(updated1?.recipeCount, 0)
        XCTAssertEqual(updated2?.recipeCount, 1)
        XCTAssertEqual(updated3?.recipeCount, 1)
    }

    // MARK: - Delete Tests

    func testDelete_RemovesCollectionLocally() async throws {
        // Given
        let collection = Collection.new(name: "Test Collection", userId: testUserId)
        try await repository.create(collection)

        // When
        try await repository.delete(id: collection.id)

        // Then
        let fetched = try await repository.fetch(id: collection.id)
        XCTAssertNil(fetched)
    }

    func testDelete_CreatesTombstoneAndRemovedMembershipEdges() async throws {
        let recipeId = UUID()
        let collection = Collection(name: "Test Collection", userId: testUserId, recipeIds: [recipeId])
        try await repository.create(collection)

        try await repository.delete(id: collection.id)

        let context = ModelContext(modelContainer)
        let tombstones = try context.fetch(FetchDescriptor<DeletedCollectionModel>())
        let membershipEdges = try context.fetch(FetchDescriptor<CollectionMembershipModel>())

        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.collectionId, collection.id)
        XCTAssertEqual(tombstones.first?.ownerId, testUserId)
        XCTAssertEqual(tombstones.first?.schemaVersion, DeletedCollectionTombstone.currentSchemaVersion)
        XCTAssertEqual(membershipEdges.count, 1)
        XCTAssertEqual(membershipEdges.first?.collectionId, collection.id)
        XCTAssertEqual(membershipEdges.first?.recipeId, recipeId)
        XCTAssertEqual(membershipEdges.first?.status, CollectionMembershipStatus.removed.rawValue)
    }

    func testDelete_NonOwnedCollection_IsIntentionallyNonDisclosing() async throws {
        // Given
        let ownerId = UUID()
        let otherUserId = UUID()
        let collection = Collection.new(name: "Shared Collection", userId: ownerId)
        try await repository.create(collection)
        setCurrentUser(id: otherUserId)

        // When/Then
        do {
            try await repository.delete(id: collection.id)
            XCTFail("Expected collectionNotFound error")
        } catch CollectionRepositoryError.collectionNotFound {
            // Intentionally indistinguishable from an absent collection.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDelete_NonExistentCollection_ThrowsError() async throws {
        // When/Then
        do {
            try await repository.delete(id: UUID())
            XCTFail("Expected error to be thrown")
        } catch CollectionRepositoryError.collectionNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Search Tests

    func testSearch_EmptyQuery_ReturnsAll() async throws {
        // Given
        let collection1 = Collection.new(name: "Breakfast", userId: testUserId)
        let collection2 = Collection.new(name: "Lunch", userId: testUserId)
        try await repository.create(collection1)
        try await repository.create(collection2)

        // When
        let results = try await repository.search(query: "")

        // Then
        XCTAssertEqual(results.count, 2)
    }

    func testSearch_FindsMatchingCollections() async throws {
        // Given
        let collection1 = Collection.new(name: "Breakfast Recipes", userId: testUserId)
        let collection2 = Collection.new(name: "Lunch Ideas", userId: testUserId)
        let collection3 = Collection.new(name: "Dinner Plans", userId: testUserId)
        try await repository.create(collection1)
        try await repository.create(collection2)
        try await repository.create(collection3)

        // When
        let results = try await repository.search(query: "Breakfast")

        // Then
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Breakfast Recipes")
    }

    func testSearch_CaseInsensitive() async throws {
        // Given
        let collection = Collection.new(name: "Breakfast Recipes", userId: testUserId)
        try await repository.create(collection)

        // When
        let results = try await repository.search(query: "breakfast")

        // Then
        XCTAssertEqual(results.count, 1)
    }

    func testSearch_NoMatches() async throws {
        // Given
        let collection = Collection.new(name: "Breakfast Recipes", userId: testUserId)
        try await repository.create(collection)

        // When
        let results = try await repository.search(query: "Dinner")

        // Then
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - Owner-Scoped Identity Tests

    func testMembershipOverlayKeepsSameCollectionIDSeparatedByOwner() async throws {
        let collectionID = UUID()
        let ownerA = UUID()
        let ownerB = UUID()
        let recipeA = UUID()
        let recipeB = UUID()
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(Collection(
            id: collectionID,
            name: "Owner A",
            userId: ownerA,
            recipeIds: []
        )))
        context.insert(try CollectionModel.from(Collection(
            id: collectionID,
            name: "Owner B",
            userId: ownerB,
            recipeIds: []
        )))
        context.insert(CollectionMembershipModel.from(CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeA,
            ownerId: ownerA,
            status: .active,
            sortOrder: 0,
            sourceDeviceId: "owner-a"
        )))
        context.insert(CollectionMembershipModel.from(CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeB,
            ownerId: ownerB,
            status: .active,
            sortOrder: 0,
            sourceDeviceId: "owner-b"
        )))
        try context.save()

        let fetchedA = try await repository.fetch(id: collectionID, preferredOwnerId: ownerA)
        let fetchedB = try await repository.fetch(id: collectionID, preferredOwnerId: ownerB)

        XCTAssertEqual(fetchedA?.name, "Owner A")
        XCTAssertEqual(fetchedA?.recipeIds, [recipeA])
        XCTAssertEqual(fetchedB?.name, "Owner B")
        XCTAssertEqual(fetchedB?.recipeIds, [recipeB])
    }

    func testUpdateWithSameCollectionIDMutatesOnlyMatchingOwner() async throws {
        let collectionID = UUID()
        let ownerA = UUID()
        let ownerB = UUID()
        let context = ModelContext(modelContainer)
        let collectionA = Collection(id: collectionID, name: "Owner A", userId: ownerA)
        let collectionB = Collection(id: collectionID, name: "Owner B", userId: ownerB)
        context.insert(try CollectionModel.from(collectionA))
        context.insert(try CollectionModel.from(collectionB))
        try context.save()
        setCurrentUser(id: ownerA)

        try await repository.update(
            collectionA.updated(name: "Owner A Updated"),
            queueCloudSync: false
        )

        let fetchedA = try await repository.fetch(id: collectionID, preferredOwnerId: ownerA)
        let fetchedB = try await repository.fetch(id: collectionID, preferredOwnerId: ownerB)
        XCTAssertEqual(fetchedA?.name, "Owner A Updated")
        XCTAssertEqual(fetchedB?.name, "Owner B")
    }

    func testDeleteWithSameCollectionIDRemovesOnlyCurrentOwnersGraph() async throws {
        let collectionID = UUID()
        let ownerA = UUID()
        let ownerB = UUID()
        let recipeA = UUID()
        let recipeB = UUID()
        let context = ModelContext(modelContainer)
        context.insert(try CollectionModel.from(Collection(
            id: collectionID,
            name: "Owner A",
            userId: ownerA,
            recipeIds: [recipeA]
        )))
        context.insert(try CollectionModel.from(Collection(
            id: collectionID,
            name: "Owner B",
            userId: ownerB,
            recipeIds: [recipeB]
        )))
        context.insert(CollectionMembershipModel.from(CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeA,
            ownerId: ownerA,
            status: .active,
            sortOrder: 0,
            sourceDeviceId: "owner-a"
        )))
        context.insert(CollectionMembershipModel.from(CollectionMembershipEdge(
            collectionId: collectionID,
            recipeId: recipeB,
            ownerId: ownerB,
            status: .active,
            sortOrder: 0,
            sourceDeviceId: "owner-b"
        )))
        try context.save()
        setCurrentUser(id: ownerA)

        try await repository.delete(id: collectionID)

        let fetchedA = try await repository.fetch(id: collectionID, preferredOwnerId: ownerA)
        let fetchedB = try await repository.fetch(id: collectionID, preferredOwnerId: ownerB)
        XCTAssertNil(fetchedA)
        XCTAssertEqual(fetchedB?.recipeIds, [recipeB])
        let verificationContext = ModelContext(modelContainer)
        let tombstones = try verificationContext.fetch(FetchDescriptor<DeletedCollectionModel>())
        XCTAssertEqual(tombstones.map(\.ownerId), [ownerA])
        let ownerBEdges = try verificationContext.fetch(
            FetchDescriptor<CollectionMembershipModel>(
                predicate: #Predicate { $0.collectionId == collectionID && $0.ownerId == ownerB }
            )
        )
        XCTAssertEqual(ownerBEdges.count, 1)
        XCTAssertEqual(ownerBEdges.first?.status, CollectionMembershipStatus.active.rawValue)
    }

    func testArchiveIdentityDispositionIgnoresOtherOwnersSameIDTombstone() async throws {
        let collectionID = UUID()
        let currentOwner = UUID()
        let otherOwner = UUID()
        let context = ModelContext(modelContainer)
        context.insert(DeletedCollectionModel(
            collectionId: collectionID,
            ownerId: otherOwner,
            deletedAt: Date(),
            cloudRecordName: nil,
            sourceDeviceId: "other-owner"
        ))
        try context.save()
        setCurrentUser(id: currentOwner)

        let dispositionWithOtherOwnerTombstone = try await repository
            .archiveImportIdentityDisposition(collectionID: collectionID)
        XCTAssertEqual(dispositionWithOtherOwnerTombstone, .preserveStableID)

        context.insert(DeletedCollectionModel(
            collectionId: collectionID,
            ownerId: currentOwner,
            deletedAt: Date(),
            cloudRecordName: nil,
            sourceDeviceId: "current-owner"
        ))
        try context.save()
        let dispositionWithCurrentOwnerTombstone = try await repository
            .archiveImportIdentityDisposition(collectionID: collectionID)
        XCTAssertEqual(dispositionWithCurrentOwnerTombstone, .remapDeletedID)
    }

    func testLegacyStoreFixtureOpensWithCurrentLocalSchema() throws {
        let committedFixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LegacyStoreV1_5/default.store")
        let fixturePath = ProcessInfo.processInfo.environment["CAULDRON_LEGACY_STORE_FIXTURE"]
            ?? committedFixture.path
        let sourceURL = URL(fileURLWithPath: fixturePath)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sourceURL.path),
            "Legacy store fixture unavailable at \(sourceURL.path)"
        )
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CauldronStoreOpen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: sourceURL, to: storeURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: sourceURL.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) {
                try FileManager.default.copyItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
        }

        let schema = CauldronPersistenceSchema.make()
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        _ = try ModelContainer(for: schema, configurations: [config])
    }

    func testShippingSchemaMigratesPopulatedLegacyDurabilityGraphWithoutDataLoss() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CauldronPopulatedStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        // This is the exact committed 1.5-era model set from 521f071. The model
        // source files named in `legacySchema` remain byte-for-byte unchanged
        // from that release. The set intentionally omits DeletedCollectionModel,
        // which was added later.
        let legacySchema = Schema([
            RecipeModel.self,
            DeletedRecipeModel.self,
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            ConnectionModel.self,
            CollectionModel.self,
            CollectionMembershipModel.self,
            SavedRecipeReferenceModel.self,
            SavedCollectionReferenceModel.self
        ])
        let legacyConfiguration = ModelConfiguration(
            schema: legacySchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        let ownerID = UUID()
        let recipeID = UUID()
        let collectionID = UUID()
        let sourceRecipeID = UUID()
        let sourceCollectionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_701_234_567)
        let ingredientsBlob = try JSONEncoder().encode([Ingredient(name: "Durable carrot")])
        let stepsBlob = try JSONEncoder().encode([CookStep(index: 0, text: "Keep every byte.")])
        let tagsBlob = try JSONEncoder().encode([Tag(name: "Fixture")])
        let relatedBlob = try JSONEncoder().encode([sourceRecipeID])
        let recipeIDsBlob = try JSONEncoder().encode([recipeID])
        let quantityBlob = try JSONEncoder().encode(Quantity(value: 2, unit: .cup))

        do {
            let container = try ModelContainer(for: legacySchema, configurations: [legacyConfiguration])
            let context = ModelContext(container)
            context.insert(RecipeModel(
                id: recipeID,
                title: "Populated fixture recipe",
                ingredientsBlob: ingredientsBlob,
                stepsBlob: stepsBlob,
                tagsBlob: tagsBlob,
                relatedRecipeIdsBlob: relatedBlob,
                notes: "Migration sentinel",
                ownerId: ownerID,
                createdAt: timestamp.addingTimeInterval(-100),
                updatedAt: timestamp
            ))
            context.insert(CollectionModel(
                id: collectionID,
                name: "Populated fixture collection",
                userId: ownerID,
                recipeIdsBlob: recipeIDsBlob,
                createdAt: timestamp.addingTimeInterval(-50),
                updatedAt: timestamp
            ))
            context.insert(CollectionMembershipModel(
                collectionId: collectionID,
                recipeId: recipeID,
                ownerId: ownerID,
                status: CollectionMembershipStatus.active.rawValue,
                updatedAt: timestamp,
                sortOrder: 7,
                sourceDeviceId: "fixture-device"
            ))
            context.insert(DeletedRecipeModel(
                recipeId: UUID(),
                deletedAt: timestamp,
                cloudRecordName: "deleted-recipe",
                sourceDeviceId: "fixture-device"
            ))
            context.insert(SavedRecipeReferenceModel(
                userId: ownerID,
                sourceRecipeId: sourceRecipeID,
                sourceOwnerId: UUID(),
                materializedRecipeId: recipeID,
                savedAt: timestamp,
                sourceRecipeUpdatedAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            context.insert(SavedCollectionReferenceModel(
                userId: ownerID,
                sourceCollectionId: sourceCollectionID,
                sourceOwnerId: UUID(),
                sourceCollectionName: "Source collection",
                savedAt: timestamp,
                sourceCollectionUpdatedAt: timestamp,
                createdAt: timestamp,
                updatedAt: timestamp
            ))
            let groceryItem = GroceryItemModel(
                name: "Durable milk",
                quantityBlob: quantityBlob,
                isChecked: true,
                recipeID: recipeID.uuidString,
                recipeName: "Populated fixture recipe",
                addedOrder: 4,
                aiCategory: "Dairy"
            )
            context.insert(GroceryListModel(
                title: "Fixture groceries",
                createdAt: timestamp,
                items: [groceryItem]
            ))
            try context.save()
        }

        let shippingSchema = CauldronPersistenceSchema.make()
        let shippingConfiguration = ModelConfiguration(
            schema: shippingSchema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let reopened = try ModelContainer(for: shippingSchema, configurations: [shippingConfiguration])
        let context = ModelContext(reopened)
        let recipe = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(recipe.ingredientsBlob, ingredientsBlob)
        XCTAssertEqual(recipe.stepsBlob, stepsBlob)
        XCTAssertEqual(recipe.relatedRecipeIdsBlob, relatedBlob)
        XCTAssertEqual(recipe.updatedAt, timestamp)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionModel>()).first?.recipeIdsBlob, recipeIDsBlob)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CollectionMembershipModel>()).first?.sortOrder, 7)
        XCTAssertEqual(try context.fetch(FetchDescriptor<DeletedRecipeModel>()).first?.deletedAt, timestamp)
        XCTAssertTrue(try context.fetch(FetchDescriptor<DeletedCollectionModel>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedRecipeReferenceModel>()).first?.materializedRecipeId, recipeID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<SavedCollectionReferenceModel>()).first?.sourceCollectionId, sourceCollectionID)
        let groceries = try context.fetch(FetchDescriptor<GroceryListModel>())
        XCTAssertEqual(groceries.first?.items?.first?.quantityBlob, quantityBlob)
        XCTAssertEqual(groceries.first?.items?.first?.isChecked, true)

        // Prove the newly added shipping model is writable after migration.
        context.insert(DeletedCollectionModel(
            collectionId: collectionID,
            ownerId: ownerID,
            deletedAt: timestamp,
            cloudRecordName: "deleted-collection",
            sourceDeviceId: "fixture-device"
        ))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<DeletedCollectionModel>()).first?.deletedAt, timestamp)
    }
}

private struct LegacyCollectionGraphRetirementRequest: Sendable {
    let collectionID: UUID
    let previousOwnerID: UUID
    let canonicalOwnerID: UUID
    let expectedRecordName: String?
}

private actor LegacyCollectionGraphRetirementRecorder {
    private var request: LegacyCollectionGraphRetirementRequest?

    func record(
        collectionID: UUID,
        previousOwnerID: UUID,
        canonicalOwnerID: UUID,
        expectedRecordName: String?
    ) {
        request = LegacyCollectionGraphRetirementRequest(
            collectionID: collectionID,
            previousOwnerID: previousOwnerID,
            canonicalOwnerID: canonicalOwnerID,
            expectedRecordName: expectedRecordName
        )
    }

    func lastRequest() -> LegacyCollectionGraphRetirementRequest? {
        request
    }
}

private actor LegacyCollectionRecordNamesRecorder {
    private var recordNames: Set<String> = []

    func record(_ recordNames: Set<String>) {
        self.recordNames = recordNames
    }

    func lastRecordNames() -> Set<String> {
        recordNames
    }
}

private actor LegacyCollectionRetirementGate {
    private var isSuspended = false
    private var continuation: CheckedContinuation<Set<String>, Never>?
    private var recordNames: Set<String> = []

    func suspend(returning recordNames: Set<String>) async -> Set<String> {
        self.recordNames = recordNames
        isSuspended = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume(returning: recordNames)
        continuation = nil
    }
}
