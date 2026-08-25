//
//  CollectionCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for collection operations.
//

import Foundation
import CloudKit
import CryptoKit
import os

struct DeletedCollectionTombstone: Sendable, Equatable {
    nonisolated static let currentSchemaVersion = 1

    let collectionId: UUID
    let ownerId: UUID
    let deletedAt: Date
    let cloudRecordName: String?
    let sourceDeviceId: String?
    let schemaVersion: Int

    nonisolated init(
        collectionId: UUID,
        ownerId: UUID,
        deletedAt: Date,
        cloudRecordName: String?,
        sourceDeviceId: String?,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.collectionId = collectionId
        self.ownerId = ownerId
        self.deletedAt = deletedAt
        self.cloudRecordName = cloudRecordName
        self.sourceDeviceId = sourceDeviceId
        self.schemaVersion = schemaVersion
    }
}

struct CollectionSyncSnapshot: Sendable {
    let collections: [Collection]
    let membershipEdges: [CollectionMembershipEdge]
    let deletedCollections: [DeletedCollectionTombstone]
}

nonisolated struct CreatorBoundRecordCandidate: Equatable, Sendable {
    let recordName: String
    let creatorRecordName: String?
    let updatedAt: Date
}

nonisolated struct CollectionCloudIdentity: Hashable, Sendable {
    let ownerId: UUID
    let collectionId: UUID
}

/// CloudKit service for collection-related operations.
///
/// Handles:
/// - Collection CRUD operations
/// - Collection reference management (saved collections)
/// - Cover image upload/download
actor CollectionCloudService {
    private enum CollectionCreatorLookup {
        case absent
        case authorized(String)
        case invalid
    }

    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "CollectionCloudService")
    private let maxSaveAttempts = 3
    private let publicationAuthorizer: @Sendable (VerifiedAccountMutationContext) async -> Bool

    init(
        core: CloudKitCore,
        publicationAuthorizer: (@Sendable (VerifiedAccountMutationContext) async -> Bool)? = nil
    ) {
        self.core = core
        self.publicationAuthorizer = publicationAuthorizer ?? { context in
            await MainActor.run {
                CurrentUserSession.shared.permitsMutation(context)
            }
        }
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - Collection CRUD

    /// Save collection to PUBLIC database
    @discardableResult
    func saveCollection(
        _ collection: Collection,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws -> String {
        logger.info("💾 Saving collection: \(collection.name)")
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: collection.userId,
            provided: authorizationContext
        )

        let db = try await core.getPublicDatabase()
        let currentIdentity = try await validatedCurrentOwnerIdentity(for: collection.userId, in: db)
        let existingRecords = try await fetchCollectionRecords(
            collectionId: collection.id,
            ownerId: collection.userId,
            expectedRecordName: collection.cloudRecordName,
            in: db
        )
        let knownRecordName = collection.cloudRecordName.flatMap { expectedName in
            existingRecords.first(where: { record in
                record.recordID.recordName == expectedName &&
                    Self.recordCreatorMatchesAuthority(
                        record.creatorUserRecordID?.recordName,
                        authorityRecordName: currentIdentity.recordName,
                        currentIdentityRecordName: currentIdentity.recordName
                    )
            })?.recordID.recordName
        }
        let recordID = (knownRecordName ?? Self.preferredCreatorBoundRecordName(
            existingRecords.map {
                CreatorBoundRecordCandidate(
                    recordName: $0.recordID.recordName,
                    creatorRecordName: $0.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                        ? currentIdentity.recordName
                        : $0.creatorUserRecordID?.recordName,
                    updatedAt: ($0["updatedAt"] as? Date) ?? .distantPast
                )
            },
            authorityRecordName: currentIdentity.recordName
        )).map(CKRecord.ID.init(recordName:))
            ?? Self.newCollectionRecordID(collectionId: collection.id)
        var conflictCandidate: CKRecord?

        if try await isSuppressedByDeletedCollectionTombstone(collection, in: db) {
            logger.warning("Skipping save for collection suppressed by deleted tombstone: \(collection.id)")
            try await deleteCollectionRecordIfPresent(
                collection.id,
                ownerId: collection.userId,
                authorizationContext: authorizationContext,
                in: db
            )
            throw CloudKitError.invalidRecord
        }

        for attempt in 1...maxSaveAttempts {
            let record: CKRecord
            if let conflictCandidate {
                record = conflictCandidate
            } else {
                record = try await fetchOrCreateCollectionRecord(recordID: recordID, in: db)
            }
            guard Self.recordCreatorMatchesAuthority(
                record.creatorUserRecordID?.recordName,
                authorityRecordName: currentIdentity.recordName,
                currentIdentityRecordName: currentIdentity.recordName,
                permitsUnclaimedRecord: true
            ) else {
                logger.error("Refusing to overwrite a Collection record claimed by another CloudKit creator")
                throw CloudKitError.invalidRecord
            }

            let shouldClearMissingOptionalFields = conflictCandidate == nil
            populateCollectionRecord(
                record,
                from: collection,
                clearingMissingOptionalFields: shouldClearMissingOptionalFields
            )

            do {
                guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: collection.userId) else {
                    throw CloudKitError.invalidRecord
                }
                defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
                try await authorizeMutation(ownerID: collection.userId, context: authorizationContext)
                let savedRecord = try await db.save(record)
                logger.info("✅ Saved collection to PUBLIC database")
                return savedRecord.recordID.recordName
            } catch let error as CKError where error.code == .serverRecordChanged {
                let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
                guard let serverRecord else {
                    logger.error("❌ Conflict without server record payload for collection: \(collection.name)")
                    throw error
                }
                guard Self.recordCreatorMatchesAuthority(
                    serverRecord.creatorUserRecordID?.recordName,
                    authorityRecordName: currentIdentity.recordName,
                    currentIdentityRecordName: currentIdentity.recordName
                ) else {
                    logger.error("Refusing Collection conflict recovery against another CloudKit creator")
                    throw CloudKitError.invalidRecord
                }

                logger.warning("⚠️ Save conflict for collection '\(collection.name)', retrying (\(attempt)/\(self.maxSaveAttempts))")
                conflictCandidate = makeConflictResolvedRecord(serverRecord: serverRecord, localCollection: collection)
            } catch {
                throw error
            }
        }

        logger.error("❌ Exhausted conflict retries for collection '\(collection.name)'")
        throw CloudKitError.syncConflict
    }

    /// Fetch user's own collections
    func fetchCollections(forUserId userId: UUID) async throws -> [Collection] {
        logger.info("📥 Fetching collections for user: \(userId)")

        let collections = try await fetchCollectionsWithoutOverlay(forUserId: userId)
        let collectionsWithMemberships = await applyMembershipOverlay(to: collections)
        logger.info("✅ Fetched \(collectionsWithMemberships.count) collections")
        return collectionsWithMemberships
    }

    /// Fetches all collection state needed by the repository in one logical pass.
    /// Unlike `fetchCollections`, this deliberately avoids the membership/tombstone
    /// overlay because the repository merges those same records into its durable store.
    func fetchSyncSnapshot(forUserId userId: UUID) async throws -> CollectionSyncSnapshot {
        async let collections = fetchCollectionsWithoutOverlay(forUserId: userId)
        async let membershipEdges = fetchMembershipEdges(forUserId: userId)
        async let deletedCollections = fetchDeletedCollectionTombstones(ownerId: userId)

        return try await CollectionSyncSnapshot(
            collections: collections,
            membershipEdges: membershipEdges,
            deletedCollections: deletedCollections
        )
    }

    private func fetchCollectionsWithoutOverlay(forUserId userId: UUID) async throws -> [Collection] {

        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var collections: [Collection] = []
        var cursor: CKQueryOperation.Cursor?

        do {
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }

                for (_, result) in results.matchResults {
                    let record = try result.get()
                    guard let collection = try? collectionFromRecord(record),
                          collection.userId == userId,
                          try await collectionRecordIsOwnerAuthenticated(record, in: db) else {
                        continue
                    }
                    collections.append(collection)
                }

                cursor = results.queryCursor
            } while cursor != nil
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty owner collection list")
                return []
            }
            throw error
        }

        return deduplicatedAndSortedCollections(collections)
    }

    /// Fetch shared collections from friends
    func fetchSharedCollections(friendIds: [UUID]) async throws -> [Collection] {
        guard !friendIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()

        do {
            var collections: [Collection] = []
            for friendIdChunk in Self.chunkedStrings(friendIds.map(\.uuidString)) {
                let predicate = NSPredicate(
                    format: "userId IN %@ AND visibility != %@",
                    friendIdChunk,
                    RecipeVisibility.privateRecipe.rawValue
                )
                let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

                let records = try await fetchAllRecords(matching: query, in: db)
                for record in records {
                    guard let collection = try? collectionFromRecord(record),
                          friendIds.contains(collection.userId),
                          try await collectionRecordIsOwnerAuthenticated(record, in: db) else { continue }
                    collections.append(collection)
                }
            }

            return await applyMembershipOverlay(to: deduplicatedAndSortedCollections(collections))
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    /// Query collections by owner and visibility
    func queryCollections(ownerIds: [UUID], visibility: RecipeVisibility) async throws -> [Collection] {
        logger.info("🔍 Querying collections from \(ownerIds.count) owners with visibility: \(visibility.rawValue)")

        guard !ownerIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()

        do {
            var collections: [Collection] = []
            for ownerIdChunk in Self.chunkedStrings(ownerIds.map(\.uuidString)) {
                let predicate = NSPredicate(
                    format: "userId IN %@ AND visibility == %@",
                    ownerIdChunk,
                    visibility.rawValue
                )

                let query = CKQuery(recordType: CloudKitCore.RecordType.collection, predicate: predicate)
                query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

                let records = try await fetchAllRecords(matching: query, in: db)
                for record in records {
                    guard let collection = try? collectionFromRecord(record),
                          ownerIds.contains(collection.userId),
                          try await collectionRecordIsOwnerAuthenticated(record, in: db) else { continue }
                    collections.append(collection)
                }
            }

            let collectionsWithMemberships = await applyMembershipOverlay(to: deduplicatedAndSortedCollections(collections))
            logger.info("✅ Found \(collectionsWithMemberships.count) collections")
            return collectionsWithMemberships
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("Collection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    func fetchPublicCollections(
        identities: [CollectionCloudIdentity]
    ) async throws -> [CollectionCloudIdentity: Collection] {
        let uniqueIdentities = Array(Set(identities))
        guard !uniqueIdentities.isEmpty else { return [:] }

        let db = try await core.getPublicDatabase()
        var collectionsByIdentity: [CollectionCloudIdentity: Collection] = [:]

        for identity in uniqueIdentities {
            do {
                for record in try await fetchCollectionRecords(
                    collectionId: identity.collectionId,
                    ownerId: identity.ownerId,
                    in: db
                ) {
                    let collection = try collectionFromRecord(record)
                    guard collection.userId == identity.ownerId,
                          collection.visibility != .privateRecipe,
                          try await collectionRecordIsOwnerAuthenticated(record, in: db) else { continue }
                    let existing = collectionsByIdentity[identity]
                    if existing == nil || existing!.updatedAt < collection.updatedAt {
                        collectionsByIdentity[identity] = collection
                    }
                }
            } catch {
                logger.warning(
                    "Failed to fetch saved source collection \(identity.collectionId.uuidString) " +
                    "for owner \(identity.ownerId.uuidString): \(error.localizedDescription)"
                )
                throw error
            }
        }

        let overlaidCollections = await applyMembershipOverlay(to: Array(collectionsByIdentity.values))
        return Dictionary(uniqueKeysWithValues: overlaidCollections.map {
            (CollectionCloudIdentity(ownerId: $0.userId, collectionId: $0.id), $0)
        })
    }

    /// Delete collection from PUBLIC database
    func deleteCollection(
        _ collectionId: UUID,
        ownerId: UUID,
        expectedRecordName: String? = nil,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        logger.info("🗑️ Deleting collection: \(collectionId)")
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: ownerId,
            provided: authorizationContext
        )

        try await deleteMembershipEdges(
            forCollectionId: collectionId,
            ownerId: ownerId,
            authorizationContext: authorizationContext
        )

        let db = try await core.getPublicDatabase()
        try await deleteCollectionRecordIfPresent(
            collectionId,
            ownerId: ownerId,
            expectedRecordName: expectedRecordName,
            authorizationContext: authorizationContext,
            in: db
        )
    }

    private func deleteCollectionRecordIfPresent(
        _ collectionId: UUID,
        ownerId: UUID,
        expectedRecordName: String? = nil,
        authorizationContext: VerifiedAccountMutationContext,
        in db: CKDatabase
    ) async throws {
        let currentIdentity = try await core.getCurrentUserRecordID()
        _ = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
        let records = try await fetchCollectionRecords(
            collectionId: collectionId,
            ownerId: ownerId,
            expectedRecordName: expectedRecordName,
            in: db
        )
            .filter {
                Self.recordCreatorMatchesAuthority(
                    $0.creatorUserRecordID?.recordName,
                    authorityRecordName: currentIdentity.recordName,
                    currentIdentityRecordName: currentIdentity.recordName
                )
            }
        guard !records.isEmpty else {
            logger.info("Collection not found in CloudKit (already deleted): \(collectionId)")
            return
        }
        try await authorizeMutation(ownerID: ownerId, context: authorizationContext)
        try await deleteRecordIDs(records.map(\.recordID), in: db)
        logger.info("✅ Deleted \(records.count) collection record(s)")
    }

    // MARK: - Collection Membership

    nonisolated static func collectionRecordID(collectionId: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: collectionId.uuidString)
    }

    /// New Collection records use an unguessable physical name. The original
    /// UUID-only name remains a compatibility alias for records created by
    /// older versions, but a foreign preclaim can no longer block creation.
    nonisolated static func newCollectionRecordID(
        collectionId: UUID,
        nonce: UUID = UUID()
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: "collection_\(collectionId.uuidString)_\(nonce.uuidString)")
    }

    nonisolated static func deletedCollectionRecordID(collectionId: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "deletedCollection_\(collectionId.uuidString)")
    }

    /// New public state records use an unguessable suffix. The deterministic
    /// identifier above remains a read/delete compatibility alias for records
    /// written by older app versions, but is no longer a global creation lock
    /// another authenticated user can preclaim.
    nonisolated static func newDeletedCollectionRecordID(
        collectionId: UUID,
        nonce: UUID = UUID()
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: "deletedCollection_\(collectionId.uuidString)_\(nonce.uuidString)")
    }

    func saveDeletedCollectionTombstone(
        _ tombstone: DeletedCollectionTombstone,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: tombstone.ownerId,
            provided: authorizationContext
        )
        let db = try await core.getPublicDatabase()
        let currentIdentity = try await validatedCurrentOwnerIdentity(for: tombstone.ownerId, in: db)
        let existingRecords = try await fetchDeletedCollectionRecords(
            collectionId: tombstone.collectionId,
            ownerId: tombstone.ownerId,
            in: db
        )
        let recordID = Self.preferredCreatorBoundRecordName(
            existingRecords.map {
                CreatorBoundRecordCandidate(
                    recordName: $0.recordID.recordName,
                    creatorRecordName: $0.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                        ? currentIdentity.recordName
                        : $0.creatorUserRecordID?.recordName,
                    updatedAt: ($0["deletedAt"] as? Date) ?? .distantPast
                )
            },
            authorityRecordName: currentIdentity.recordName
        ).map(CKRecord.ID.init(recordName:))
            ?? Self.newDeletedCollectionRecordID(collectionId: tombstone.collectionId)
        var tombstoneToSave = tombstone
        var conflictCandidate: CKRecord?

        for attempt in 1...maxSaveAttempts {
            let record: CKRecord
            if let conflictCandidate {
                record = conflictCandidate
            } else {
                record = try await fetchOrCreateDeletedCollectionRecord(recordID: recordID, in: db)
            }
            guard Self.recordCreatorMatchesAuthority(
                record.creatorUserRecordID?.recordName,
                authorityRecordName: currentIdentity.recordName,
                currentIdentityRecordName: currentIdentity.recordName,
                permitsUnclaimedRecord: true
            ) else {
                logger.error("Refusing to overwrite a DeletedCollection record claimed by another CloudKit creator")
                throw CloudKitError.invalidRecord
            }

            populateDeletedCollectionRecord(record, from: tombstoneToSave)

            do {
                guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: tombstone.ownerId) else {
                    throw CloudKitError.invalidRecord
                }
                defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
                try await authorizeMutation(ownerID: tombstone.ownerId, context: authorizationContext)
                _ = try await db.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }

                let serverTombstone = try? deletedCollectionTombstone(from: serverRecord)
                tombstoneToSave = DeletedCollectionTombstone(
                    collectionId: tombstone.collectionId,
                    ownerId: tombstone.ownerId,
                    deletedAt: max(tombstone.deletedAt, serverTombstone?.deletedAt ?? tombstone.deletedAt),
                    cloudRecordName: tombstone.cloudRecordName ?? serverTombstone?.cloudRecordName,
                    sourceDeviceId: tombstone.sourceDeviceId ?? serverTombstone?.sourceDeviceId,
                    schemaVersion: max(tombstone.schemaVersion, serverTombstone?.schemaVersion ?? tombstone.schemaVersion)
                )
                conflictCandidate = serverRecord
                logger.warning("DeletedCollection save conflict for \(tombstone.collectionId), retrying \(attempt)/\(self.maxSaveAttempts)")
            } catch {
                throw error
            }
        }

        throw CloudKitError.syncConflict
    }

    func fetchDeletedCollectionTombstones(ownerId: UUID) async throws -> [DeletedCollectionTombstone] {
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.deletedCollection, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]

        do {
            var tombstones: [DeletedCollectionTombstone] = []
            var cursor: CKQueryOperation.Cursor?

            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }

                for (_, result) in results.matchResults {
                    guard let record = try? result.get(),
                          let tombstone = try? deletedCollectionTombstone(from: record),
                          tombstone.ownerId == ownerId,
                          try await isCollectionStateRecordAuthorized(
                              record,
                              collectionId: tombstone.collectionId,
                              ownerId: ownerId,
                              in: db
                          ) else {
                        continue
                    }
                    tombstones.append(tombstone)
                }
                cursor = results.queryCursor
            } while cursor != nil

            return Dictionary(grouping: tombstones) {
                CollectionCloudIdentity(ownerId: $0.ownerId, collectionId: $0.collectionId)
            }
                .compactMap { _, duplicates in duplicates.max(by: { $0.deletedAt < $1.deletedAt }) }
                .sorted { $0.deletedAt > $1.deletedAt }
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("DeletedCollection record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    nonisolated static func membershipRecordID(collectionId: UUID, recipeId: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "membership_\(collectionId.uuidString)_\(recipeId.uuidString)")
    }

    nonisolated static func newMembershipRecordID(
        collectionId: UUID,
        recipeId: UUID,
        nonce: UUID = UUID()
    ) -> CKRecord.ID {
        CKRecord.ID(recordName: "membership_\(collectionId.uuidString)_\(recipeId.uuidString)_\(nonce.uuidString)")
    }

    func saveMembershipEdge(
        _ edge: CollectionMembershipEdge,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: edge.ownerId,
            provided: authorizationContext
        )
        try await withPublicationLease(ownerID: edge.ownerId) {
            try await saveMembershipEdge(
                edge,
                authorizationContext: authorizationContext,
                publicationLeaseHeld: true
            )
        }
    }

    private func saveMembershipEdge(
        _ edge: CollectionMembershipEdge,
        authorizationContext: VerifiedAccountMutationContext,
        publicationLeaseHeld: Bool
    ) async throws {
        precondition(publicationLeaseHeld)
        let db = try await core.getPublicDatabase()
        let currentIdentity = try await validatedCurrentOwnerIdentity(for: edge.ownerId, in: db)
        let existingRecords = try await fetchMembershipRecords(
            matching: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "ownerId == %@", edge.ownerId.uuidString),
                NSPredicate(format: "collectionId == %@", edge.collectionId.uuidString),
                NSPredicate(format: "recipeId == %@", edge.recipeId.uuidString),
            ]),
            expectedOwnerId: edge.ownerId
        )
        let recordID = Self.preferredCreatorBoundRecordName(
            existingRecords.map {
                CreatorBoundRecordCandidate(
                    recordName: $0.recordID.recordName,
                    creatorRecordName: $0.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                        ? currentIdentity.recordName
                        : $0.creatorUserRecordID?.recordName,
                    updatedAt: ($0["updatedAt"] as? Date) ?? .distantPast
                )
            },
            authorityRecordName: currentIdentity.recordName
        ).map(CKRecord.ID.init(recordName:))
            ?? Self.newMembershipRecordID(collectionId: edge.collectionId, recipeId: edge.recipeId)
        var record = try await fetchOrCreateMembershipRecord(recordID: recordID, in: db)

        for attempt in 1...maxSaveAttempts {
            guard Self.recordCreatorMatchesAuthority(
                record.creatorUserRecordID?.recordName,
                authorityRecordName: currentIdentity.recordName,
                currentIdentityRecordName: currentIdentity.recordName,
                permitsUnclaimedRecord: true
            ) else {
                logger.error("Refusing to overwrite a CollectionMembership record claimed by another CloudKit creator")
                throw CloudKitError.invalidRecord
            }
            populateMembershipRecord(record, from: edge)
            do {
                try await authorizeMutation(ownerID: edge.ownerId, context: authorizationContext)
                _ = try await db.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }

                if let serverEdge = try? membershipEdge(from: serverRecord),
                   serverEdge.updatedAt > edge.updatedAt {
                    return
                }

                logger.warning("CollectionMembership save conflict for \(edge.collectionId), retrying \(attempt)/\(self.maxSaveAttempts)")
                record = serverRecord
            } catch {
                throw error
            }
        }

        throw CloudKitError.syncConflict
    }

    func saveMembershipEdges(
        _ edges: [CollectionMembershipEdge],
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        guard !edges.isEmpty else { return }

        let db = try await core.getPublicDatabase()
        for (ownerId, ownerEdges) in Dictionary(grouping: edges, by: \.ownerId) {
            let ownerAuthorizationContext = try await resolvedAuthorizationContext(
                ownerID: ownerId,
                provided: authorizationContext
            )
            try await withPublicationLease(ownerID: ownerId) {
                let currentIdentity = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
                let existingRecords = try await fetchMembershipRecords(forUserId: ownerId, in: db)
                let existingByLogicalKey = Dictionary(grouping: existingRecords) { record in
                    let collectionID = record["collectionId"] as? String ?? ""
                    let recipeID = record["recipeId"] as? String ?? ""
                    return "\(collectionID)|\(recipeID)"
                }
                let records = ownerEdges.compactMap { edge -> CKRecord? in
                    let logicalKey = "\(edge.collectionId.uuidString)|\(edge.recipeId.uuidString)"
                    let candidates = existingByLogicalKey[logicalKey] ?? []
                    let preferredName = Self.preferredCreatorBoundRecordName(
                        candidates.map {
                            CreatorBoundRecordCandidate(
                                recordName: $0.recordID.recordName,
                                creatorRecordName: $0.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                                    ? currentIdentity.recordName
                                    : $0.creatorUserRecordID?.recordName,
                                updatedAt: ($0["updatedAt"] as? Date) ?? .distantPast
                            )
                        },
                        authorityRecordName: currentIdentity.recordName
                    )
                    let record = preferredName.flatMap { name in
                        candidates.first { $0.recordID.recordName == name }
                    } ?? CKRecord(
                        recordType: CloudKitCore.RecordType.collectionMembership,
                        recordID: Self.newMembershipRecordID(
                            collectionId: edge.collectionId,
                            recipeId: edge.recipeId
                        )
                    )
                    if let serverEdge = try? membershipEdge(from: record), serverEdge.updatedAt > edge.updatedAt {
                        return nil
                    }
                    populateMembershipRecord(record, from: edge)
                    return record
                }

                for chunk in Self.chunked(records, size: 200) {
                    do {
                        try await authorizeMutation(ownerID: ownerId, context: ownerAuthorizationContext)
                        try await saveMembershipRecords(chunk, in: db)
                    } catch {
                        // Keep the owner's outer publication lease while resolving
                        // every conflicted edge; account deletion cannot inventory a
                        // partially published batch.
                        for edge in ownerEdges where chunk.contains(where: {
                            ($0["collectionId"] as? String) == edge.collectionId.uuidString &&
                                ($0["recipeId"] as? String) == edge.recipeId.uuidString
                        }) {
                            try await saveMembershipEdge(
                                edge,
                                authorizationContext: ownerAuthorizationContext,
                                publicationLeaseHeld: true
                            )
                        }
                    }
                }
            }
        }
    }

    func membershipRecords(for edges: [CollectionMembershipEdge]) -> [CKRecord] {
        edges.map { edge in
            let record = CKRecord(
                recordType: CloudKitCore.RecordType.collectionMembership,
                recordID: Self.newMembershipRecordID(
                    collectionId: edge.collectionId,
                    recipeId: edge.recipeId
                )
            )
            populateMembershipRecord(record, from: edge)
            return record
        }
    }

    func fetchMembershipEdges(forUserId userId: UUID) async throws -> [CollectionMembershipEdge] {
        let predicate = NSPredicate(format: "ownerId == %@", userId.uuidString)
        return try await fetchMembershipRecords(matching: predicate, expectedOwnerId: userId).map(membershipEdge(from:))
    }

    func deleteMembershipEdges(
        forCollectionId collectionId: UUID,
        ownerId: UUID,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: ownerId,
            provided: authorizationContext
        )
        let db = try await core.getPublicDatabase()
        _ = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ownerId == %@", ownerId.uuidString),
            NSPredicate(format: "collectionId == %@", collectionId.uuidString),
        ])
        let records = try await fetchMembershipRecords(
            matching: predicate,
            expectedOwnerId: ownerId,
            deduplicating: false
        )

        guard !records.isEmpty else {
            logger.info("No collection membership edges found to delete for collection: \(collectionId)")
            return
        }

        let recordIDs = records.map(\.recordID)

        for chunk in Self.chunked(recordIDs, size: 200) {
            try await authorizeMutation(ownerID: ownerId, context: authorizationContext)
            try await deleteRecordIDs(chunk, in: db)
        }

        logger.info("✅ Deleted \(records.count) collection membership edges for collection: \(collectionId)")
    }

    func deleteAllMembershipEdges(
        forOwnerId ownerId: UUID,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: ownerId,
            provided: authorizationContext
        )
        let db = try await core.getPublicDatabase()
        _ = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
        let predicate = NSPredicate(format: "ownerId == %@", ownerId.uuidString)
        let records = try await fetchMembershipRecords(
            matching: predicate,
            expectedOwnerId: ownerId,
            deduplicating: false
        )
        guard !records.isEmpty else { return }
        for chunk in Self.chunked(records.map(\.recordID), size: 200) {
            try await authorizeMutation(ownerID: ownerId, context: authorizationContext)
            try await deleteRecordIDs(chunk, in: db)
        }
        logger.info("✅ Deleted \(records.count) collection membership edges for owner: \(ownerId)")
    }

    private func fetchMembershipRecords(
        matching predicate: NSPredicate,
        expectedOwnerId: UUID,
        deduplicating: Bool = true
    ) async throws -> [CKRecord] {
        let db = try await core.getPublicDatabase()
        let query = CKQuery(recordType: CloudKitCore.RecordType.collectionMembership, predicate: predicate)
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        do {
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                if let cursor {
                    results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
                } else {
                    results = try await db.records(matching: query, resultsLimit: 500)
                }
                for (_, result) in results.matchResults {
                    let record = try result.get()
                    guard let edge = try? membershipEdge(from: record),
                          edge.ownerId == expectedOwnerId,
                          try await isCollectionStateRecordAuthorized(
                              record,
                              collectionId: edge.collectionId,
                              ownerId: expectedOwnerId,
                              in: db
                          ) else {
                        continue
                    }
                    records.append(record)
                }
                cursor = results.queryCursor
            } while cursor != nil
            return deduplicating ? Self.deduplicatedMembershipRecords(records) : records
        } catch let error as CKError {
            if error.code == .unknownItem || error.errorCode == 11 {
                logger.info("CollectionMembership record type not yet in CloudKit schema - returning empty list")
                return []
            }
            throw error
        }
    }

    // MARK: - Cover Image

    /// Upload collection cover image to CloudKit
    func uploadCollectionCoverImage(
        collectionId: UUID,
        ownerId: UUID,
        expectedRecordName: String?,
        imageData: Data,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws -> String {
        logger.info("📤 Uploading collection cover image for collection: \(collectionId)")
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: ownerId,
            provided: authorizationContext
        )

        let optimizedData = try await core.optimizeImageForCloudKit(imageData, maxDimension: 1200, targetSize: 2_000_000)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection_\(collectionId.uuidString)_\(UUID().uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let asset = CKAsset(fileURL: tempURL)

        let db = try await core.getPublicDatabase()

        do {
            let currentIdentity = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
            guard let record = try await preferredCollectionRecord(
                collectionId: collectionId,
                ownerId: ownerId,
                expectedRecordName: expectedRecordName,
                authorityRecordName: currentIdentity.recordName,
                in: db
            ) else { throw CloudKitError.invalidRecord }

            record["coverImageAsset"] = asset
            record["coverImageModifiedAt"] = Date() as CKRecordValue

            let savedRecord = try await withPublicationLease(ownerID: ownerId) {
                try await authorizeMutation(ownerID: ownerId, context: authorizationContext)
                return try await db.save(record)
            }
            logger.info("✅ Uploaded collection cover image asset")
            return savedRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.error("Collection record not found in CloudKit: \(collectionId)")
                throw CloudKitError.invalidRecord
            } else if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload collection cover image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download collection cover image from CloudKit
    func downloadCollectionCoverImage(
        collectionId: UUID,
        ownerId: UUID,
        recordName: String
    ) async throws -> Data? {
        logger.info("📥 Downloading collection cover image for collection: \(collectionId)")

        let db = try await core.getPublicDatabase()

        do {
            let record: CKRecord
            do {
                record = try await db.record(for: CKRecord.ID(recordName: recordName))
            } catch let error as CKError where error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return nil
            }

            guard Self.collectionRecordMatchesIdentity(
                    record,
                    identity: CollectionCloudIdentity(ownerId: ownerId, collectionId: collectionId),
                    expectedRecordName: recordName
                  ),
                  try await collectionRecordIsOwnerAuthenticated(record, in: db) else {
                logger.info("Collection record not found: \(collectionId)")
                return nil
            }

            guard let asset = record["coverImageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.info("No collection cover image asset found for collection: \(collectionId)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            logger.info("✅ Downloaded collection cover image (\(data.count) bytes)")
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return nil
            }
            throw error
        }
    }

    /// Delete collection cover image from CloudKit
    func deleteCollectionCoverImage(
        collectionId: UUID,
        ownerId: UUID,
        expectedRecordName: String,
        authorizationContext: VerifiedAccountMutationContext? = nil
    ) async throws {
        logger.info("🗑️ Deleting collection cover image for collection: \(collectionId)")
        let authorizationContext = try await resolvedAuthorizationContext(
            ownerID: ownerId,
            provided: authorizationContext
        )

        let db = try await core.getPublicDatabase()

        do {
            let currentIdentity = try await validatedCurrentOwnerIdentity(for: ownerId, in: db)
            guard let record = try await preferredCollectionRecord(
                collectionId: collectionId,
                ownerId: ownerId,
                expectedRecordName: expectedRecordName,
                authorityRecordName: currentIdentity.recordName,
                in: db
            ) else {
                logger.info("Collection record not found: \(collectionId)")
                return
            }

            record["coverImageAsset"] = nil
            record["coverImageModifiedAt"] = nil

            _ = try await withPublicationLease(ownerID: ownerId) {
                try await authorizeMutation(ownerID: ownerId, context: authorizationContext)
                try await db.save(record)
            }
            logger.info("✅ Deleted collection cover image asset")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("Collection record not found: \(collectionId)")
                return
            }
            throw error
        }
    }

    // MARK: - Private Helpers

    private func resolvedAuthorizationContext(
        ownerID: UUID,
        provided: VerifiedAccountMutationContext?
    ) async throws -> VerifiedAccountMutationContext {
        if let provided {
            try await authorizeMutation(ownerID: ownerID, context: provided)
            return provided
        }
        guard let context = await MainActor.run(body: {
            CurrentUserSession.shared.verifiedMutationContext(ownerID: ownerID)
        }) else {
            throw UserSessionError.accountChanged
        }
        return context
    }

    private func authorizeMutation(
        ownerID: UUID,
        context: VerifiedAccountMutationContext
    ) async throws {
        try await RecipePublicationAuthorizationPolicy.authorize(
            ownerID: ownerID,
            context: context,
            validator: publicationAuthorizer
        )
    }

#if DEBUG
    func validateMutationAuthorization(
        ownerID: UUID,
        context: VerifiedAccountMutationContext
    ) async throws {
        try await authorizeMutation(ownerID: ownerID, context: context)
    }
#endif

    /// The operation is the publication boundary used by bulk membership
    /// writes and their conflict fallback. Keeping release explicit ensures a
    /// waiting account deletion cannot resume before the final write returns.
    func withPublicationLease<T>(
        ownerID: UUID,
        operation: () async throws -> T
    ) async throws -> T {
        guard let lease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerID) else {
            throw CloudKitError.invalidRecord
        }
        do {
            let value = try await operation()
            await AccountDeletionGate.shared.releasePublicationLease(lease)
            return value
        } catch {
            await AccountDeletionGate.shared.releasePublicationLease(lease)
            throw error
        }
    }

    private func fetchCollectionRecords(
        collectionId: UUID,
        ownerId: UUID? = nil,
        expectedRecordName: String? = nil,
        in db: CKDatabase
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []

        // Physical record names are the only index-independent lookup. Prefer
        // the locally persisted name before falling back to a public query,
        // whose index can lag a successful save.
        if let expectedRecordName, !expectedRecordName.isEmpty {
            guard let ownerId else { throw CloudKitError.invalidRecord }
            do {
                let directRecord = try await db.record(
                    for: CKRecord.ID(recordName: expectedRecordName)
                )
                records.append(try Self.validatedKnownCollectionRecord(
                    directRecord,
                    identity: CollectionCloudIdentity(
                        ownerId: ownerId,
                        collectionId: collectionId
                    ),
                    expectedRecordName: expectedRecordName
                ))
            } catch let error as CKError where error.code == .unknownItem {
                // The physical record may have been removed remotely. Query the
                // logical identity for a replacement or compatibility record.
            }
        }

        var predicates = [NSPredicate(format: "collectionId == %@", collectionId.uuidString)]
        if let ownerId {
            predicates.append(NSPredicate(format: "userId == %@", ownerId.uuidString))
        }
        let query = CKQuery(
            recordType: CloudKitCore.RecordType.collection,
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        )
        do {
            records.append(contentsOf: try await fetchAllRecords(matching: query, in: db))
        } catch let error as CKError where error.code == .unknownItem || error.errorCode == 11 {
            // Keep any directly fetched physical record.
        }

        // Directly read the old UUID-only alias as well. This both preserves
        // older records and avoids a duplicate when the public query index is
        // briefly behind a legacy save.
        let legacyID = Self.collectionRecordID(collectionId: collectionId)
        if !records.contains(where: { $0.recordID == legacyID }),
           let legacy = try? await db.record(for: legacyID) {
            records.append(legacy)
        }

        var unique: [CKRecord.ID: CKRecord] = [:]
        for record in records {
            guard record.recordType == CloudKitCore.RecordType.collection,
                  record["collectionId"] as? String == collectionId.uuidString,
                  ownerId == nil || record["userId"] as? String == ownerId?.uuidString else {
                continue
            }
            unique[record.recordID] = record
        }
        return Array(unique.values)
    }

    nonisolated static func collectionRecordMatchesIdentity(
        _ record: CKRecord,
        identity: CollectionCloudIdentity,
        expectedRecordName: String? = nil
    ) -> Bool {
        record.recordType == CloudKitCore.RecordType.collection &&
            (expectedRecordName == nil || record.recordID.recordName == expectedRecordName) &&
            record["collectionId"] as? String == identity.collectionId.uuidString &&
            record["userId"] as? String == identity.ownerId.uuidString
    }

    nonisolated static func validatedKnownCollectionRecord(
        _ record: CKRecord,
        identity: CollectionCloudIdentity,
        expectedRecordName: String
    ) throws -> CKRecord {
        guard collectionRecordMatchesIdentity(
            record,
            identity: identity,
            expectedRecordName: expectedRecordName
        ) else {
            throw CloudKitError.invalidRecord
        }
        return record
    }

    private func preferredCollectionRecord(
        collectionId: UUID,
        ownerId: UUID,
        expectedRecordName: String?,
        authorityRecordName: String,
        in db: CKDatabase
    ) async throws -> CKRecord? {
        var records: [CKRecord] = []
        for record in try await fetchCollectionRecords(
            collectionId: collectionId,
            ownerId: ownerId,
            expectedRecordName: expectedRecordName,
            in: db
        ) {
            if try await collectionRecordIsOwnerAuthenticated(record, in: db) {
                records.append(record)
            }
        }
        if let expectedRecordName,
           let knownRecord = records.first(where: { $0.recordID.recordName == expectedRecordName }) {
            return knownRecord
        }
        let preferredName = Self.preferredCreatorBoundRecordName(
            records.map {
                CreatorBoundRecordCandidate(
                    recordName: $0.recordID.recordName,
                    creatorRecordName: $0.creatorUserRecordID?.recordName == CKCurrentUserDefaultName
                        ? authorityRecordName
                        : $0.creatorUserRecordID?.recordName,
                    updatedAt: ($0["updatedAt"] as? Date) ?? .distantPast
                )
            },
            authorityRecordName: authorityRecordName
        )
        return preferredName.flatMap { name in records.first { $0.recordID.recordName == name } }
    }

    private func newestCollectionRecord(collectionId: UUID, in db: CKDatabase) async throws -> CKRecord? {
        var authenticatedRecords: [CKRecord] = []
        for record in try await fetchCollectionRecords(collectionId: collectionId, in: db) {
            if try await collectionRecordIsOwnerAuthenticated(record, in: db) {
                authenticatedRecords.append(record)
            }
        }
        return authenticatedRecords.max { lhs, rhs in
            let lhsDate = (lhs["updatedAt"] as? Date) ?? .distantPast
            let rhsDate = (rhs["updatedAt"] as? Date) ?? .distantPast
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return lhs.recordID.recordName > rhs.recordID.recordName
        }
    }

    private func collectionRecordIsOwnerAuthenticated(_ record: CKRecord, in db: CKDatabase) async throws -> Bool {
        guard let ownerIDString = record["userId"] as? String,
              let ownerID = UUID(uuidString: ownerIDString),
              let rawCreatorName = record.creatorUserRecordID?.recordName,
              let creatorName = try await concreteCreatorName(rawCreatorName) else {
            return false
        }
        return try await ownerIdentityIsAuthenticated(creatorName, ownerId: ownerID, in: db)
    }

    private func fetchOrCreateCollectionRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            let record = try await db.record(for: recordID)
            logger.info("Updating existing collection record")
            return record
        } catch let error as CKError where error.code == .unknownItem {
            logger.info("Creating new collection record")
            return CKRecord(recordType: CloudKitCore.RecordType.collection, recordID: recordID)
        }
    }

    private func fetchAllRecords(
        matching query: CKQuery,
        in db: CKDatabase,
        resultsLimit: Int = 500
    ) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: resultsLimit)
            } else {
                results = try await db.records(matching: query, resultsLimit: resultsLimit)
            }

            records += results.matchResults.compactMap { _, result in
                try? result.get()
            }
            cursor = results.queryCursor
        } while cursor != nil

        return records
    }

    private func deleteRecordIDs(_ recordIDs: [CKRecord.ID], in db: CKDatabase) async throws {
        guard !recordIDs.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            operation.database = db
            operation.start()
        }
    }

    private func saveMembershipRecords(_ records: [CKRecord], in db: CKDatabase) async throws {
        guard !records.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            let resultLock = NSLock()
            var firstRecordError: Error?
            operation.savePolicy = .ifServerRecordUnchanged
            operation.isAtomic = false
            operation.perRecordSaveBlock = { _, result in
                guard case .failure(let error) = result else { return }
                resultLock.withLock {
                    if firstRecordError == nil {
                        firstRecordError = error
                    }
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    let recordError = resultLock.withLock { firstRecordError }
                    if let recordError {
                        continuation.resume(throwing: recordError)
                    } else {
                        continuation.resume()
                    }
                }
            }
            operation.database = db
            operation.start()
        }
    }

    private func fetchMembershipRecords(forUserId userId: UUID, in db: CKDatabase) async throws -> [CKRecord] {
        let predicate = NSPredicate(format: "ownerId == %@", userId.uuidString)
        return try await fetchMembershipRecords(matching: predicate, expectedOwnerId: userId)
    }

    private func currentUserAuthorityMatches(
        ownerId: UUID,
        identityRecordName: String,
        in db: CKDatabase
    ) async throws -> Bool {
        let candidateIDs = [
            CKRecord.ID(recordName: "user_\(identityRecordName)"),
            CKRecord.ID(recordName: identityRecordName),
        ]
        for recordID in candidateIDs {
            do {
                let record = try await db.record(for: recordID)
                if Self.canonicalUserAuthorityRecordName(
                    recordType: record.recordType,
                    recordName: record.recordID.recordName,
                    storedUserID: record["userId"] as? String,
                    creatorRecordName: record.creatorUserRecordID?.recordName,
                    expectedUserID: ownerId.uuidString,
                    currentIdentityRecordName: identityRecordName
                ) == identityRecordName {
                    return true
                }
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
        return false
    }

    private func validatedCurrentOwnerIdentity(for ownerId: UUID, in db: CKDatabase) async throws -> CKRecord.ID {
        let currentIdentity = try await core.getCurrentUserRecordID()
        guard try await currentUserAuthorityMatches(
            ownerId: ownerId,
            identityRecordName: currentIdentity.recordName,
            in: db
        ) else {
            logger.error("Refusing collection state write for an owner not bound to the current CloudKit identity")
            throw CloudKitError.invalidRecord
        }
        return currentIdentity
    }

    nonisolated static func preferredCreatorBoundRecordName(
        _ candidates: [CreatorBoundRecordCandidate],
        authorityRecordName: String
    ) -> String? {
        candidates
            .filter { $0.creatorRecordName == authorityRecordName }
            .max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                return lhs.recordName > rhs.recordName
            }?
            .recordName
    }

    /// Collection state follows the creator of the canonical Collection record.
    /// Only when that record has already been deleted may a separately
    /// authenticated owner identity authorize the state record.
    nonisolated static func collectionStateCreatorIsAuthorized(
        recordCreatorName: String?,
        collectionCreatorName: String?,
        fallbackAuthenticatedCreatorName: String?
    ) -> Bool {
        guard let recordCreatorName else { return false }
        if let collectionCreatorName {
            return recordCreatorName == collectionCreatorName
        }
        return recordCreatorName == fallbackAuthenticatedCreatorName
    }

    nonisolated static func deterministicUserID(for identityRecordName: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("cauldron-user:\(identityRecordName)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBufferPointer { buffer in
            NSUUID(uuidBytes: buffer.baseAddress!) as UUID
        }
    }

    private func isCollectionStateRecordAuthorized(
        _ record: CKRecord,
        collectionId: UUID,
        ownerId: UUID,
        in db: CKDatabase
    ) async throws -> Bool {
        guard let rawCreatorName = record.creatorUserRecordID?.recordName,
              let recordCreatorName = try await concreteCreatorName(rawCreatorName) else {
            return false
        }

        switch try await collectionCreatorLookup(
            collectionId: collectionId,
            ownerId: ownerId,
            in: db
        ) {
        case .authorized(let collectionCreatorName):
            return Self.collectionStateCreatorIsAuthorized(
                recordCreatorName: recordCreatorName,
                collectionCreatorName: collectionCreatorName,
                fallbackAuthenticatedCreatorName: nil
            )
        case .invalid:
            return false
        case .absent:
            let fallback = try await ownerIdentityIsAuthenticated(
                recordCreatorName,
                ownerId: ownerId,
                in: db
            ) ? recordCreatorName : nil
            return Self.collectionStateCreatorIsAuthorized(
                recordCreatorName: recordCreatorName,
                collectionCreatorName: nil,
                fallbackAuthenticatedCreatorName: fallback
            )
        }
    }

    private func collectionCreatorLookup(
        collectionId: UUID,
        ownerId: UUID,
        in db: CKDatabase
    ) async throws -> CollectionCreatorLookup {
        let records = try await fetchCollectionRecords(
            collectionId: collectionId,
            ownerId: ownerId,
            in: db
        )
        guard !records.isEmpty else { return .absent }

        var authenticatedCreators = Set<String>()
        for record in records {
            guard let rawCreatorName = record.creatorUserRecordID?.recordName,
                  let creatorName = try await concreteCreatorName(rawCreatorName),
                  try await ownerIdentityIsAuthenticated(creatorName, ownerId: ownerId, in: db) else {
                continue
            }
            authenticatedCreators.insert(creatorName)
        }
        guard authenticatedCreators.count == 1, let creatorName = authenticatedCreators.first else {
            return .invalid
        }
        return .authorized(creatorName)
    }

    private func concreteCreatorName(_ recordName: String) async throws -> String? {
        if recordName != CKCurrentUserDefaultName { return recordName }
        return try await core.getCurrentUserRecordID().recordName
    }

    /// Modern Cauldron user IDs are derived from the CloudKit identity. Legacy
    /// IDs are accepted only through a complete creator-protected
    /// UsernameClaim -> canonical User chain.
    private func ownerIdentityIsAuthenticated(
        _ identityRecordName: String,
        ownerId: UUID,
        in db: CKDatabase
    ) async throws -> Bool {
        if Self.deterministicUserID(for: identityRecordName) == ownerId {
            return true
        }

        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "userId == %@", ownerId.uuidString),
            NSPredicate(format: "identityRecordName == %@", identityRecordName),
        ])
        let query = CKQuery(recordType: CloudKitCore.RecordType.usernameClaim, predicate: predicate)
        let claims: [CKRecord]
        do {
            claims = try await fetchAllRecords(matching: query, in: db)
        } catch let error as CKError where error.code == .unknownItem || error.errorCode == 11 {
            return false
        }

        for claim in claims {
            guard let username = claim["username"] as? String,
                  UserCloudService.usernameClaimBelongsToUser(
                      recordType: claim.recordType,
                      claimedUserID: claim["userId"] as? String,
                      claimedUsername: username,
                      claimedIdentityRecordName: claim["identityRecordName"] as? String,
                      creatorRecordName: claim.creatorUserRecordID?.recordName,
                      expectedUserID: ownerId.uuidString,
                      expectedUsername: username,
                      expectedIdentityRecordName: identityRecordName
                  ) else {
                continue
            }

            for recordID in [
                CKRecord.ID(recordName: "user_\(identityRecordName)"),
                CKRecord.ID(recordName: identityRecordName),
            ] {
                guard let userRecord = try? await db.record(for: recordID),
                      userRecord["username"] as? String == username,
                      Self.canonicalUserAuthorityRecordName(
                          recordType: userRecord.recordType,
                          recordName: userRecord.recordID.recordName,
                          storedUserID: userRecord["userId"] as? String,
                          creatorRecordName: userRecord.creatorUserRecordID?.recordName,
                          expectedUserID: ownerId.uuidString,
                          currentIdentityRecordName: identityRecordName
                      ) == identityRecordName else {
                    continue
                }
                return true
            }
        }
        return false
    }

    private func fetchDeletedCollectionRecords(
        collectionId: UUID,
        ownerId: UUID,
        in db: CKDatabase
    ) async throws -> [CKRecord] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "ownerId == %@", ownerId.uuidString),
            NSPredicate(format: "collectionId == %@", collectionId.uuidString),
        ])
        let query = CKQuery(recordType: CloudKitCore.RecordType.deletedCollection, predicate: predicate)
        var records: [CKRecord]
        do {
            records = try await fetchAllRecords(matching: query, in: db)
        } catch let error as CKError where error.code == .unknownItem || error.errorCode == 11 {
            records = []
        }

        // Query results can lag a just-committed legacy deterministic record.
        let legacyID = Self.deletedCollectionRecordID(collectionId: collectionId)
        if !records.contains(where: { $0.recordID == legacyID }),
           let legacy = try? await db.record(for: legacyID) {
            records.append(legacy)
        }

        var unique: [CKRecord.ID: CKRecord] = [:]
        for record in records {
            guard let tombstone = try? deletedCollectionTombstone(from: record),
                  tombstone.collectionId == collectionId,
                  tombstone.ownerId == ownerId,
                  try await isCollectionStateRecordAuthorized(
                      record,
                      collectionId: collectionId,
                      ownerId: ownerId,
                      in: db
                  ) else {
                continue
            }
            unique[record.recordID] = record
        }
        return Array(unique.values)
    }

    nonisolated static func deduplicatedMembershipRecords(_ records: [CKRecord]) -> [CKRecord] {
        Dictionary(grouping: records) { record in
            let ownerID = record["ownerId"] as? String ?? ""
            let collectionID = record["collectionId"] as? String ?? ""
            let recipeID = record["recipeId"] as? String ?? ""
            return "\(ownerID)|\(collectionID)|\(recipeID)"
        }.compactMap { _, duplicates in
            duplicates.max { lhs, rhs in
                let lhsDate = (lhs["updatedAt"] as? Date) ?? .distantPast
                let rhsDate = (rhs["updatedAt"] as? Date) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.recordID.recordName > rhs.recordID.recordName
            }
        }
    }

    /// Validates the protected User record that anchors all public collection
    /// state for an application owner. Both the current canonical
    /// `user_<identity>` name and the legacy system identity name are accepted.
    nonisolated static func canonicalUserAuthorityRecordName(
        recordType: String,
        recordName: String,
        storedUserID: String?,
        creatorRecordName: String?,
        expectedUserID: String,
        currentIdentityRecordName: String?
    ) -> String? {
        guard recordType == CloudKitCore.RecordType.user,
              storedUserID == expectedUserID,
              let creatorRecordName else {
            return nil
        }

        let authorityRecordName: String
        if creatorRecordName == CKCurrentUserDefaultName {
            guard let currentIdentityRecordName else { return nil }
            authorityRecordName = currentIdentityRecordName
        } else {
            authorityRecordName = creatorRecordName
        }

        guard recordName == authorityRecordName || recordName == "user_\(authorityRecordName)" else {
            return nil
        }
        return authorityRecordName
    }

    /// New records have no creator until CloudKit saves them. Existing records
    /// must already belong to the canonical authority; this closes deterministic
    /// record-name preclaims without preventing the legitimate first save.
    nonisolated static func recordCreatorMatchesAuthority(
        _ creatorRecordName: String?,
        authorityRecordName: String,
        currentIdentityRecordName: String?,
        permitsUnclaimedRecord: Bool = false
    ) -> Bool {
        guard let creatorRecordName else { return permitsUnclaimedRecord }
        if creatorRecordName == authorityRecordName { return true }
        return creatorRecordName == CKCurrentUserDefaultName &&
            authorityRecordName == currentIdentityRecordName
    }

    private func deduplicatedAndSortedCollections(_ collections: [Collection]) -> [Collection] {
        var byIdentity: [CollectionCloudIdentity: Collection] = [:]
        for collection in collections {
            let identity = CollectionCloudIdentity(
                ownerId: collection.userId,
                collectionId: collection.id
            )
            if let existing = byIdentity[identity] {
                if collection.updatedAt > existing.updatedAt {
                    byIdentity[identity] = collection
                }
            } else {
                byIdentity[identity] = collection
            }
        }

        return byIdentity.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func applyMembershipOverlay(to collections: [Collection]) async -> [Collection] {
        guard !collections.isEmpty else { return [] }

        var collections = collections
        do {
            collections = try await filterDeletedCollections(collections)
        } catch {
            logger.warning("Failed to filter deleted collections before membership overlay: \(error.localizedDescription)")
        }

        guard !collections.isEmpty else { return [] }

        var edges: [CollectionMembershipEdge] = []
        for ownerId in Set(collections.map(\.userId)) {
            do {
                edges += try await fetchMembershipEdges(forUserId: ownerId)
            } catch {
                logger.warning("Failed to fetch collection memberships for owner \(ownerId.uuidString): \(error.localizedDescription)")
            }
        }

        guard !edges.isEmpty else { return collections }

        let edgesByCollection = Dictionary(grouping: edges) {
            CollectionCloudIdentity(ownerId: $0.ownerId, collectionId: $0.collectionId)
        }
        return collections.map { collection in
            let identity = CollectionCloudIdentity(
                ownerId: collection.userId,
                collectionId: collection.id
            )
            guard let collectionEdges = edgesByCollection[identity], !collectionEdges.isEmpty else {
                return collection
            }
            return CollectionMembershipProjection.collectionWithRecipeIds(
                collection,
                CollectionMembershipProjection.activeRecipeIds(from: collectionEdges)
            )
        }
    }

    private nonisolated static func chunkedStrings(_ values: [String], size: Int = 100) -> [[String]] {
        chunked(values, size: size)
    }

    private nonisolated static func chunked<Value>(_ values: [Value], size: Int) -> [[Value]] {
        guard size > 0, !values.isEmpty else { return [] }

        return stride(from: 0, to: values.count, by: size).map { startIndex in
            let endIndex = min(startIndex + size, values.count)
            return Array(values[startIndex..<endIndex])
        }
    }

    private func fetchOrCreateDeletedCollectionRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            return try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: CloudKitCore.RecordType.deletedCollection, recordID: recordID)
        }
    }

    private func makeConflictResolvedRecord(serverRecord: CKRecord, localCollection: Collection) -> CKRecord {
        populateCollectionRecord(
            serverRecord,
            from: localCollection,
            clearingMissingOptionalFields: false
        )
        return serverRecord
    }

    func populateCollectionRecord(
        _ record: CKRecord,
        from collection: Collection,
        clearingMissingOptionalFields: Bool = true
    ) {
        // Core fields
        record["collectionId"] = collection.id.uuidString as CKRecordValue
        record["name"] = collection.name as CKRecordValue
        record["userId"] = collection.userId.uuidString as CKRecordValue
        record["visibility"] = collection.visibility.rawValue as CKRecordValue
        record["createdAt"] = collection.createdAt as CKRecordValue
        record["updatedAt"] = collection.updatedAt as CKRecordValue
        record["coverImageType"] = collection.coverImageType.rawValue as CKRecordValue
        record["originalCollectionId"] = collection.originalCollectionId?.uuidString as CKRecordValue?
        record["originalCollectionOwnerId"] = collection.originalCollectionOwnerId?.uuidString as CKRecordValue?
        record["originalCollectionName"] = collection.originalCollectionName as CKRecordValue?
        record["savedAt"] = collection.savedAt as CKRecordValue?
        record["sourceCollectionUpdatedAt"] = collection.sourceCollectionUpdatedAt as CKRecordValue?
        record["followsSourceUpdates"] = (collection.followsSourceUpdates ? 1 : 0) as CKRecordValue

        // Optional fields.
        // On first save attempt, clear missing local fields so explicit user clears persist.
        // During conflict retry, preserve server values when local optionals are absent.
        if let description = collection.description {
            record["description"] = description as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["description"] = nil
        }

        if let emoji = collection.emoji {
            record["emoji"] = emoji as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["emoji"] = nil
        }

        if let symbolName = collection.symbolName {
            record["symbolName"] = symbolName as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["symbolName"] = nil
        }

        if let color = collection.color {
            record["color"] = color as CKRecordValue
        } else if clearingMissingOptionalFields {
            record["color"] = nil
        }

        if collection.coverImageType != .customImage, clearingMissingOptionalFields {
            record["coverImageAsset"] = nil
            record["coverImageModifiedAt"] = nil
        }

        if let recipeIdsJSON = try? JSONEncoder().encode(collection.recipeIds),
           let recipeIdsString = String(data: recipeIdsJSON, encoding: .utf8) {
            record["recipeIds"] = recipeIdsString as CKRecordValue
        } else {
            logger.error("❌ Failed to encode recipe IDs for collection: \(collection.name)")
            record["recipeIds"] = "[]" as CKRecordValue
        }
    }

    func collectionFromRecord(_ record: CKRecord) throws -> Collection {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let name = record["name"] as? String,
              let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let visibilityString = record["visibility"] as? String,
              let visibility = RecipeVisibility(rawValue: visibilityString),
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        // Parse recipe IDs from JSON string
        let recipeIds: [UUID]
        if let recipeIdsString = record["recipeIds"] as? String,
           let recipeIdsData = recipeIdsString.data(using: .utf8),
           let ids = try? JSONDecoder().decode([UUID].self, from: recipeIdsData) {
            recipeIds = ids
        } else {
            recipeIds = []
        }

        let description = record["description"] as? String
        let emoji = record["emoji"] as? String
        let symbolName = record["symbolName"] as? String
        let color = record["color"] as? String
        let coverImageTypeString = record["coverImageType"] as? String
        let coverImageType = coverImageTypeString.flatMap { CoverImageType(rawValue: $0) } ?? .recipeGrid
        let coverImageModifiedAt = record["coverImageModifiedAt"] as? Date
        let hasCloudCoverImage = record["coverImageAsset"] as? CKAsset != nil || coverImageModifiedAt != nil
        let cloudCoverImageRecordName = hasCloudCoverImage ? record.recordID.recordName : nil
        let originalCollectionId = (record["originalCollectionId"] as? String).flatMap(UUID.init(uuidString:))
        let originalCollectionOwnerId = (record["originalCollectionOwnerId"] as? String).flatMap(UUID.init(uuidString:))
        let followsSourceUpdates = Self.boolValue(for: record["followsSourceUpdates"])

        return Collection(
            id: collectionId,
            name: name,
            description: description,
            userId: userId,
            recipeIds: recipeIds,
            visibility: visibility,
            emoji: emoji,
            symbolName: symbolName,
            color: color,
            coverImageType: coverImageType,
            cloudCoverImageRecordName: cloudCoverImageRecordName,
            coverImageModifiedAt: coverImageModifiedAt,
            cloudRecordName: record.recordID.recordName,
            originalCollectionId: originalCollectionId,
            originalCollectionOwnerId: originalCollectionOwnerId,
            originalCollectionName: record["originalCollectionName"] as? String,
            savedAt: record["savedAt"] as? Date,
            sourceCollectionUpdatedAt: record["sourceCollectionUpdatedAt"] as? Date,
            followsSourceUpdates: followsSourceUpdates,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func overlayMembershipEdges(on collections: [Collection]) async throws -> [Collection] {
        let collections = try await filterDeletedCollections(collections)
        guard !collections.isEmpty else { return [] }

        var allEdges: [CollectionMembershipEdge] = []
        for ownerId in Set(collections.map(\.userId)) {
            allEdges.append(contentsOf: try await fetchMembershipEdges(forUserId: ownerId))
        }

        let edgesByCollectionId = Dictionary(grouping: allEdges) {
            CollectionCloudIdentity(ownerId: $0.ownerId, collectionId: $0.collectionId)
        }
        guard !edgesByCollectionId.isEmpty else { return collections }

        return collections.map { collection in
            let identity = CollectionCloudIdentity(
                ownerId: collection.userId,
                collectionId: collection.id
            )
            guard let edges = edgesByCollectionId[identity] else {
                return collection
            }
            return collectionWithRecipeIds(collection, activeRecipeIds(from: edges))
        }
    }

    private func filterDeletedCollections(_ collections: [Collection]) async throws -> [Collection] {
        guard !collections.isEmpty else { return [] }

        var deletedCollections = Set<CollectionCloudIdentity>()
        for ownerId in Set(collections.map(\.userId)) {
            let tombstones = try await fetchDeletedCollectionTombstones(ownerId: ownerId)
            deletedCollections.formUnion(tombstones.map {
                CollectionCloudIdentity(ownerId: $0.ownerId, collectionId: $0.collectionId)
            })
        }

        guard !deletedCollections.isEmpty else { return collections }

        for identity in deletedCollections where collections.contains(where: {
            $0.id == identity.collectionId && $0.userId == identity.ownerId
        }) {
            try? await deleteCollection(identity.collectionId, ownerId: identity.ownerId)
        }

        return collections.filter {
            !deletedCollections.contains(
                CollectionCloudIdentity(ownerId: $0.userId, collectionId: $0.id)
            )
        }
    }

    private func isSuppressedByDeletedCollectionTombstone(_ collection: Collection, in db: CKDatabase) async throws -> Bool {
        do {
            let tombstones = try await fetchDeletedCollectionRecords(
                collectionId: collection.id,
                ownerId: collection.userId,
                in: db
            )
            return !tombstones.isEmpty
        } catch let error as CKError where error.code == .unknownItem ||
                error.errorCode == 11 || error.code == .invalidArguments {
            return false
        }
    }

    private func activeRecipeIds(from edges: [CollectionMembershipEdge]) -> [UUID] {
        edges
            .filter { $0.status == .active }
            .sorted(by: { (lhs: CollectionMembershipEdge, rhs: CollectionMembershipEdge) in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.updatedAt < rhs.updatedAt
            })
            .map(\.recipeId)
    }

    private func collectionWithRecipeIds(_ collection: Collection, _ recipeIds: [UUID]) -> Collection {
        Collection(
            id: collection.id,
            name: collection.name,
            description: collection.description,
            userId: collection.userId,
            recipeIds: recipeIds,
            visibility: collection.visibility,
            emoji: collection.emoji,
            symbolName: collection.symbolName,
            color: collection.color,
            coverImageType: collection.coverImageType,
            coverImageURL: collection.coverImageURL,
            cloudCoverImageRecordName: collection.cloudCoverImageRecordName,
            coverImageModifiedAt: collection.coverImageModifiedAt,
            cloudRecordName: collection.cloudRecordName,
            originalCollectionId: collection.originalCollectionId,
            originalCollectionOwnerId: collection.originalCollectionOwnerId,
            originalCollectionName: collection.originalCollectionName,
            savedAt: collection.savedAt,
            sourceCollectionUpdatedAt: collection.sourceCollectionUpdatedAt,
            followsSourceUpdates: collection.followsSourceUpdates,
            createdAt: collection.createdAt,
            updatedAt: collection.updatedAt
        )
    }

    private func fetchOrCreateMembershipRecord(recordID: CKRecord.ID, in db: CKDatabase) async throws -> CKRecord {
        do {
            return try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: CloudKitCore.RecordType.collectionMembership, recordID: recordID)
        }
    }

    func populateMembershipRecord(_ record: CKRecord, from edge: CollectionMembershipEdge) {
        record["collectionId"] = edge.collectionId.uuidString as CKRecordValue
        record["recipeId"] = edge.recipeId.uuidString as CKRecordValue
        record["ownerId"] = edge.ownerId.uuidString as CKRecordValue
        record["status"] = edge.status.rawValue as CKRecordValue
        record["updatedAt"] = edge.updatedAt as CKRecordValue
        record["sortOrder"] = edge.sortOrder as NSNumber
        record["sourceDeviceId"] = edge.sourceDeviceId as CKRecordValue?
        record["schemaVersion"] = edge.schemaVersion as NSNumber
    }

    func membershipEdge(from record: CKRecord) throws -> CollectionMembershipEdge {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let recipeIdString = record["recipeId"] as? String,
              let recipeId = UUID(uuidString: recipeIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let statusString = record["status"] as? String,
              let status = CollectionMembershipStatus(rawValue: statusString),
              let updatedAt = record["updatedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        let sortOrder = (record["sortOrder"] as? NSNumber)?.intValue ?? 0
        let schemaVersion = (record["schemaVersion"] as? NSNumber)?.intValue ?? CollectionMembershipEdge.currentSchemaVersion
        return CollectionMembershipEdge(
            collectionId: collectionId,
            recipeId: recipeId,
            ownerId: ownerId,
            status: status,
            updatedAt: updatedAt,
            sortOrder: sortOrder,
            sourceDeviceId: record["sourceDeviceId"] as? String,
            schemaVersion: schemaVersion
        )
    }

    func populateDeletedCollectionRecord(_ record: CKRecord, from tombstone: DeletedCollectionTombstone) {
        record["collectionId"] = tombstone.collectionId.uuidString as CKRecordValue
        record["ownerId"] = tombstone.ownerId.uuidString as CKRecordValue
        record["deletedAt"] = tombstone.deletedAt as CKRecordValue
        record["cloudRecordName"] = tombstone.cloudRecordName as CKRecordValue?
        record["sourceDeviceId"] = tombstone.sourceDeviceId as CKRecordValue?
        record["schemaVersion"] = tombstone.schemaVersion as NSNumber
    }

    func deletedCollectionTombstone(from record: CKRecord) throws -> DeletedCollectionTombstone {
        guard let collectionIdString = record["collectionId"] as? String,
              let collectionId = UUID(uuidString: collectionIdString),
              let ownerIdString = record["ownerId"] as? String,
              let ownerId = UUID(uuidString: ownerIdString),
              let deletedAt = record["deletedAt"] as? Date else {
            throw CloudKitError.invalidRecord
        }

        return DeletedCollectionTombstone(
            collectionId: collectionId,
            ownerId: ownerId,
            deletedAt: deletedAt,
            cloudRecordName: record["cloudRecordName"] as? String,
            sourceDeviceId: record["sourceDeviceId"] as? String,
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue ?? DeletedCollectionTombstone.currentSchemaVersion
        )
    }

    private nonisolated static func boolValue(for value: CKRecordValue?) -> Bool {
        if let bool = value as? Bool {
            return bool
        }

        if let number = value as? NSNumber {
            return number.boolValue
        }

        return false
    }
}
