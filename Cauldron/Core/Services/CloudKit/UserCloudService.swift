//
//  UserCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for user profile operations.
//

import Foundation
import CloudKit
import CryptoKit
import os

/// CloudKit service for user-related operations.
///
/// Handles:
/// - User profile CRUD operations
/// - Profile image upload/download
/// - User search and discovery
/// - Referral system
actor UserCloudService {
    struct WebShareCredential: Sendable, Equatable {
        let capability: String
        let generation: Int64
    }

    private let core: CloudKitCore
    private let logger = Logger(subsystem: "com.cauldron", category: "UserCloudService")

    init(core: CloudKitCore) {
        self.core = core
    }

    // MARK: - Account Status (delegated to core)

    func checkAccountStatus() async -> CloudKitAccountStatus {
        await core.checkAccountStatus()
    }

    func isAvailable() async -> Bool {
        await core.isAvailable()
    }

    // MARK: - User Lifecycle

    /// Fetch existing user profile from CloudKit (returns nil if not found)
    func fetchCurrentUserProfile() async throws -> User? {
        let accountStatus = await core.checkAccountStatus()
        guard accountStatus.isAvailable else {
            logger.warning("CloudKit account not available: \(accountStatus)")
            return nil
        }

        let db = try await core.getPublicDatabase()
        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"
        let customRecordID = CKRecord.ID(recordName: customRecordName)

        // 1. Try fetching from PUBLIC database with custom record name
        do {
            let record = try await db.record(for: customRecordID)
            if record["userId"] != nil {
                let user = try userFromRecord(record)
                let updatedUser = try await ensureReferralCodeIfNeeded(for: user)
                logger.info("✅ Found user profile in CloudKit PUBLIC database: \(updatedUser.username)")
                return updatedUser
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found in public DB, try migration
            if let migratedUser = try await migrateUserFromPrivateToPublic() {
                return migratedUser
            }
        } catch {
            logger.warning("Error fetching user by custom ID: \(error.localizedDescription)")
            throw error
        }

        // Fallback: Try the old system record ID
        do {
            let record = try await db.record(for: systemUserRecordID)
            if record["userId"] != nil {
                let user = try userFromRecord(record)
                let updatedUser = try await ensureReferralCodeIfNeeded(for: user)
                logger.info("✅ Found user profile (legacy) in CloudKit PUBLIC database")
                return updatedUser
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found
        } catch {
            logger.warning("Error fetching user by system ID: \(error.localizedDescription)")
            throw error
        }

        logger.info("No existing user profile found in CloudKit PUBLIC database")
        return nil
    }

    /// Migrate user from PRIVATE database to PUBLIC database
    private func migrateUserFromPrivateToPublic() async throws -> User? {
        logger.info("Checking for user in PRIVATE database (migration)...")

        let privateDB = try await core.getPrivateDatabase()
        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"
        let customRecordID = CKRecord.ID(recordName: customRecordName)

        // Try custom name in PRIVATE first
        do {
            let record = try await privateDB.record(for: customRecordID)
            if record["userId"] != nil, let user = try? userFromRecord(record) {
                logger.info("Found user in PRIVATE database via custom ID. Migrating to PUBLIC...")

                let updatedUser = try await ensureReferralCodeIfNeeded(for: user)
                try await saveUser(updatedUser)
                logger.info("✅ Migration complete for \(user.username)")

                return updatedUser
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found with custom name, try system ID
        }

        // Try system record ID
        do {
            let record = try await privateDB.record(for: systemUserRecordID)
            if record["userId"] != nil, let user = try? userFromRecord(record) {
                logger.info("Found user in PRIVATE database via system ID. Migrating to PUBLIC...")

                let updatedUser = try await ensureReferralCodeIfNeeded(for: user)
                try await saveUser(updatedUser)
                logger.info("✅ Migration complete for \(user.username)")
                return updatedUser
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found in private database
        }

        logger.info("No user found in PRIVATE database to migrate")
        return nil
    }

    /// Fetch or create current user profile
    func fetchOrCreateCurrentUser(
        username: String,
        displayName: String,
        profileEmoji: String? = nil,
        profileColor: String? = nil
    ) async throws -> User {
        let accountStatus = await core.checkAccountStatus()
        guard accountStatus.isAvailable else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        if let existingUser = try await fetchCurrentUserProfile() {
            return existingUser
        }

        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"

        let normalizedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespaces)
        let stableUserID = deterministicUserID(for: systemUserRecordID.recordName)

        let provisionalUser = User(
            id: stableUserID,
            username: normalizedUsername,
            displayName: normalizedDisplayName,
            cloudRecordName: customRecordName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
        let referralCode = try await generateUniqueReferralCode(preferred: deriveReferralCodeFromRecordName(for: provisionalUser))

        let user = User(
            id: stableUserID,
            username: normalizedUsername,
            displayName: normalizedDisplayName,
            cloudRecordName: customRecordName,
            referralCode: referralCode,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
        try await saveUser(user)
        return user
    }

    // MARK: - User CRUD

    /// Save user to CloudKit
    func saveUser(_ user: User) async throws {
        let normalizedUsername = user.username.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUsername.range(of: #"^[a-z0-9_]{3,20}$"#, options: .regularExpression) != nil else {
            throw CloudKitError.invalidRecord
        }

        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let recordName: String
        if let cloudRecordName = user.cloudRecordName {
            recordName = cloudRecordName
        } else {
            recordName = "user_\(systemUserRecordID.recordName)"
        }
        guard recordName == systemUserRecordID.recordName ||
                recordName == "user_\(systemUserRecordID.recordName)" else {
            throw CloudKitError.invalidRecord
        }

        let recordID = CKRecord.ID(recordName: recordName)
        let db = try await core.getPublicDatabase()

        let record = try await fetchOrCreateRecord(
            in: db,
            recordID: recordID,
            recordType: CloudKitCore.RecordType.user
        )
        populateUserRecord(record, from: user)
        guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: user.id) else {
            throw CancellationError()
        }
        defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }

        // The public default zone does not support atomic multi-record saves.
        // Claim first so an unavailable username is never exposed on User.
        // An interruption can at worst reserve the name for this same stable
        // account identity, which safely reconciles it on retry.
        _ = try await ensureUsernameClaim(
            normalizedUsername,
            userId: user.id,
            identityRecordID: systemUserRecordID,
            in: db,
            allowDuringAccountDeletion: true
        )
        do {
            _ = try await db.save(record)
        } catch let saveError {
            // CloudKit save failures can be delivery-ambiguous. Never release
            // the claim on an error: onboarding retries derive the same user
            // UUID from the iCloud identity and safely reconcile it. If the
            // server committed before the response was lost, accept that
            // exact durable profile as success.
            if let confirmed = try? await db.record(for: recordID),
               confirmed["userId"] as? String == user.id.uuidString,
               confirmed["username"] as? String == normalizedUsername {
                logger.info("Confirmed user publication after ambiguous save response")
            } else {
                throw saveError
            }
        }
        try await releaseOtherUsernameClaims(
            keeping: normalizedUsername,
            userId: user.id,
            identityRecordID: systemUserRecordID,
            in: db
        )
        logger.info("Saved user: \(normalizedUsername) to PUBLIC database")
    }

    private func usernameClaimRecordID(_ username: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "username_\(username)")
    }

    /// Checks a username before an optimistic profile edit without reserving
    /// it. Definitive ownership is established only after the corresponding
    /// User record has been durably published.
    func prepareUsernameChange(_ username: String, for userId: UUID) async throws {
        let normalizedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard normalizedUsername.range(of: #"^[a-z0-9_]{3,20}$"#, options: .regularExpression) != nil else {
            throw CloudKitError.invalidRecord
        }
        let identity = try await core.getCurrentUserRecordID()
        let db = try await core.getPublicDatabase()
        do {
            let existing = try await db.record(for: usernameClaimRecordID(normalizedUsername))
            guard Self.usernameClaimBelongsToUser(
                recordType: existing.recordType,
                claimedUserID: existing["userId"] as? String,
                claimedUsername: existing["username"] as? String,
                claimedIdentityRecordName: existing["identityRecordName"] as? String,
                creatorRecordName: existing.creatorUserRecordID?.recordName,
                expectedUserID: userId.uuidString,
                expectedUsername: normalizedUsername,
                expectedIdentityRecordName: identity.recordName
            ) else {
                throw CloudKitError.usernameUnavailable
            }
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    /// UsernameClaim uses a deterministic record name, so CloudKit's atomic
    /// create and creator-write protection are the uniqueness authority shared
    /// by every client and the web backend.
    private func ensureUsernameClaim(
        _ username: String,
        userId: UUID,
        identityRecordID: CKRecord.ID,
        in db: CKDatabase,
        allowDuringAccountDeletion: Bool = false
    ) async throws -> Bool {
        let recordID = usernameClaimRecordID(username)
        do {
            let existing = try await db.record(for: recordID)
            guard Self.usernameClaimBelongsToUser(
                recordType: existing.recordType,
                claimedUserID: existing["userId"] as? String,
                claimedUsername: existing["username"] as? String,
                claimedIdentityRecordName: existing["identityRecordName"] as? String,
                creatorRecordName: existing.creatorUserRecordID?.recordName,
                expectedUserID: userId.uuidString,
                expectedUsername: username,
                expectedIdentityRecordName: identityRecordID.recordName
            ) else {
                throw CloudKitError.usernameUnavailable
            }
            return false
        } catch let error as CKError where error.code == .unknownItem {
            let claim = CKRecord(recordType: CloudKitCore.RecordType.usernameClaim, recordID: recordID)
            claim["userId"] = userId.uuidString as CKRecordValue
            claim["username"] = username as CKRecordValue
            claim["identityRecordName"] = identityRecordID.recordName as CKRecordValue
            do {
                if !allowDuringAccountDeletion {
                    guard await AccountDeletionGate.shared.permitsWrite(ownerID: userId) else {
                        throw CancellationError()
                    }
                }
                _ = try await db.save(claim)
                return true
            } catch let saveError as CKError where saveError.code == .serverRecordChanged {
                let winner = try await db.record(for: recordID)
                guard Self.usernameClaimBelongsToUser(
                    recordType: winner.recordType,
                    claimedUserID: winner["userId"] as? String,
                    claimedUsername: winner["username"] as? String,
                    claimedIdentityRecordName: winner["identityRecordName"] as? String,
                    creatorRecordName: winner.creatorUserRecordID?.recordName,
                    expectedUserID: userId.uuidString,
                    expectedUsername: username,
                    expectedIdentityRecordName: identityRecordID.recordName
                ) else {
                    throw CloudKitError.usernameUnavailable
                }
                return false
            }
        }
    }

    /// Compares the trusted creator record name rather than the full record ID,
    /// whose zone can differ across CloudKit responses for the same identity.
    /// CloudKit may redact the creator of the current user's record to its
    /// system alias; accept that alias only when the stored concrete identity,
    /// user ID, and username all match the signed-in account.
    static func usernameClaimBelongsToUser(
        recordType: String,
        claimedUserID: String?,
        claimedUsername: String?,
        claimedIdentityRecordName: String?,
        creatorRecordName: String?,
        expectedUserID: String,
        expectedUsername: String,
        expectedIdentityRecordName: String
    ) -> Bool {
        guard recordType == CloudKitCore.RecordType.usernameClaim,
              claimedUserID == expectedUserID,
              claimedUsername == expectedUsername,
              claimedIdentityRecordName == expectedIdentityRecordName else {
            return false
        }
        return creatorRecordName == expectedIdentityRecordName ||
            creatorRecordName == CKCurrentUserDefaultName
    }

    private func releaseOtherUsernameClaims(
        keeping retainedUsername: String?,
        userId: UUID,
        identityRecordID: CKRecord.ID,
        in db: CKDatabase
    ) async throws {
        let records = try await fetchRecords(
            in: db,
            recordType: CloudKitCore.RecordType.usernameClaim,
            predicate: NSPredicate(format: "userId == %@", userId.uuidString)
        )
        for record in records where Self.usernameClaimBelongsToUser(
            recordType: record.recordType,
            claimedUserID: record["userId"] as? String,
            claimedUsername: record["username"] as? String,
            claimedIdentityRecordName: record["identityRecordName"] as? String,
            creatorRecordName: record.creatorUserRecordID?.recordName,
            expectedUserID: userId.uuidString,
            expectedUsername: record["username"] as? String ?? "",
            expectedIdentityRecordName: identityRecordID.recordName
        ) {
            let username = record["username"] as? String
            guard username != retainedUsername else { continue }
            do {
                _ = try await db.deleteRecord(withID: record.recordID)
            } catch let error as CKError where error.code == .unknownItem {
                continue
            }
        }
    }

    private func deterministicUserID(for identityRecordName: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("cauldron-user:\(identityRecordName)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBufferPointer { buffer in
            NSUUID(uuidBytes: buffer.baseAddress!) as UUID
        }
    }

    enum CapabilityRegistrationDecision: Equatable {
        case accept
        case alreadyRegistered
        case stale
        case conflict
    }

    static func capabilityRegistrationDecision(
        registeredGeneration: Int64,
        registeredHash: String?,
        incomingGeneration: Int64,
        incomingHash: String
    ) -> CapabilityRegistrationDecision {
        if registeredGeneration > incomingGeneration { return .stale }
        if registeredGeneration < incomingGeneration { return .accept }
        guard let registeredHash else { return .accept }
        return registeredHash == incomingHash ? .alreadyRegistered : .conflict
    }

    /// Registers the hash that authorizes Firebase web-share mutations. The
    /// record-name check binds registration to the signed-in iCloud account;
    /// CloudKit's creator-write protection then prevents another account from
    /// replacing this value on someone else's public profile.
    func registerWebShareCapabilityHash(
        _ credential: WebShareCredential,
        for user: User,
        allowDuringAccountDeletion: Bool = false
    ) async throws -> Bool {
        let hash = SHA256.hash(data: Data(credential.capability.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        guard hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw CloudKitError.invalidRecord
        }

        let systemRecordID = try await core.getCurrentUserRecordID()
        let allowedRecordNames = [
            systemRecordID.recordName,
            "user_\(systemRecordID.recordName)",
        ]
        guard let recordName = user.cloudRecordName,
              allowedRecordNames.contains(recordName) else {
            throw CloudKitError.invalidRecord
        }

        let publicationLease = try await acquirePublicationLease(
            ownerID: user.id,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )
        defer { releasePublicationLease(publicationLease) }

        let db = try await core.getPublicDatabase()
        _ = try await ensureUsernameClaim(
            user.username.lowercased(),
            userId: user.id,
            identityRecordID: systemRecordID,
            in: db,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )
        try await releaseOtherUsernameClaims(
            keeping: user.username.lowercased(),
            userId: user.id,
            identityRecordID: systemRecordID,
            in: db
        )
        let recordID = CKRecord.ID(recordName: recordName)
        for attempt in 1...3 {
            let record = try await db.record(for: recordID)
            guard record["userId"] as? String == user.id.uuidString else {
                throw CloudKitError.invalidRecord
            }
            let registeredGeneration = record["webShareCapabilityGeneration"] as? Int64 ?? 0
            switch Self.capabilityRegistrationDecision(
                registeredGeneration: registeredGeneration,
                registeredHash: record["webShareCapabilityHash"] as? String,
                incomingGeneration: credential.generation,
                incomingHash: hash
            ) {
            case .stale:
                return false
            case .alreadyRegistered:
                return true
            case .conflict:
                throw CloudKitError.webShareCapabilityConflict
            case .accept:
                break
            }
            record["webShareCapabilityHash"] = hash as CKRecordValue
            record["webShareCapabilityGeneration"] = credential.generation as CKRecordValue
            do {
                _ = try await db.save(record)
                return true
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                continue
            }
        }
        throw CloudKitError.syncConflict
    }

    /// Resolves one account-wide capability from the user's private custom zone.
    /// A deterministic record ID makes first creation atomic across devices;
    /// Keychain is only a local cache, never the consistency authority.
    func resolveWebShareCapability(
        for user: User,
        allowDuringAccountDeletion: Bool = false
    ) async throws -> WebShareCredential {
        let publicationLease = try await acquirePublicationLease(
            ownerID: user.id,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )
        defer { releasePublicationLease(publicationLease) }

        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: "webShareCapability_\(user.id.uuidString)",
            zoneID: zoneID
        )

        do {
            let record = try await db.record(for: recordID)
            guard record.recordType == CloudKitCore.RecordType.webShareCapability,
                  record["userId"] as? String == user.id.uuidString,
                  let capability = record["capability"] as? String,
                  !capability.isEmpty else {
                throw CloudKitError.invalidRecord
            }
            let generation = record["generation"] as? Int64 ?? 1
            try await MainActor.run {
                try ShareCapabilityStore.shared.cacheCapability(capability, for: user.id)
            }
            return WebShareCredential(capability: capability, generation: generation)
        } catch let error as CKError where error.code == .unknownItem {
            let candidate = try await MainActor.run {
                try ShareCapabilityStore.shared.capability(for: user.id)
            }
            let record = CKRecord(
                recordType: CloudKitCore.RecordType.webShareCapability,
                recordID: recordID
            )
            record["userId"] = user.id.uuidString as CKRecordValue
            record["capability"] = candidate as CKRecordValue
            record["generation"] = Int64(1) as CKRecordValue
            do {
                _ = try await db.save(record)
                return WebShareCredential(capability: candidate, generation: 1)
            } catch let saveError as CKError where saveError.code == .serverRecordChanged {
                let winner = try await db.record(for: recordID)
                guard let capability = winner["capability"] as? String,
                      winner["userId"] as? String == user.id.uuidString else {
                    throw CloudKitError.invalidRecord
                }
                let generation = winner["generation"] as? Int64 ?? 1
                try await MainActor.run {
                    try ShareCapabilityStore.shared.cacheCapability(capability, for: user.id)
                }
                return WebShareCredential(capability: capability, generation: generation)
            }
        }
    }

    /// Replaces the account-wide web management credential after a sensitive
    /// lifecycle event. CloudKit remains the cross-device authority and the
    /// Keychain value is updated only after the private record is durable.
    func rotateWebShareCapability(
        for user: User,
        allowDuringAccountDeletion: Bool = false
    ) async throws -> WebShareCredential {
        let publicationLease = try await acquirePublicationLease(
            ownerID: user.id,
            allowDuringAccountDeletion: allowDuringAccountDeletion
        )
        defer { releasePublicationLease(publicationLease) }

        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: "webShareCapability_\(user.id.uuidString)",
            zoneID: zoneID
        )
        let replacement = try await MainActor.run {
            try ShareCapabilityStore.shared.generateCapability()
        }

        for attempt in 1...3 {
            var record: CKRecord
            let nextGeneration: Int64
            do {
                record = try await db.record(for: recordID)
                guard record.recordType == CloudKitCore.RecordType.webShareCapability,
                      record["userId"] as? String == user.id.uuidString else {
                    throw CloudKitError.invalidRecord
                }
                nextGeneration = (record["generation"] as? Int64 ?? 1) + 1
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(
                    recordType: CloudKitCore.RecordType.webShareCapability,
                    recordID: recordID
                )
                record["userId"] = user.id.uuidString as CKRecordValue
                nextGeneration = 1
            }
            record["capability"] = replacement as CKRecordValue
            record["generation"] = nextGeneration as CKRecordValue
            do {
                _ = try await db.save(record)
                try await MainActor.run {
                    try ShareCapabilityStore.shared.cacheCapability(replacement, for: user.id)
                }
                return WebShareCredential(capability: replacement, generation: nextGeneration)
            } catch let error as CKError where error.code == .serverRecordChanged && attempt < 3 {
                continue
            }
        }
        throw CloudKitError.syncConflict
    }

    func deleteWebShareCapability(for userId: UUID) async throws {
        let db = try await core.getPrivateDatabase()
        let zoneID = try await core.getCustomZoneID()
        let recordID = CKRecord.ID(
            recordName: "webShareCapability_\(userId.uuidString)",
            zoneID: zoneID
        )
        do {
            _ = try await db.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    /// Search for users by username
    func searchUsers(query: String) async throws -> [User] {
        let db = try await core.getPublicDatabase()
        let lowercaseQuery = query.lowercased()

        let usernamePredicate = NSPredicate(format: "username BEGINSWITH %@", lowercaseQuery)
        let usernameQuery = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: usernamePredicate)

        let displayNamePredicate = NSPredicate(format: "displayName BEGINSWITH %@", query)
        let displayNameQuery = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: displayNamePredicate)

        var users: [User] = []
        var userIds = Set<UUID>()

        let usernameResults = try await db.records(matching: usernameQuery)
        for (_, result) in usernameResults.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record),
               !userIds.contains(user.id) {
                users.append(user)
                userIds.insert(user.id)
            }
        }

        let displayNameResults = try await db.records(matching: displayNameQuery)
        for (_, result) in displayNameResults.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record),
               !userIds.contains(user.id) {
                users.append(user)
                userIds.insert(user.id)
            }
        }

        return users
    }

    /// Fetch all users from CloudKit PUBLIC database
    func fetchAllUsers() async throws -> [User] {
        try await fetchAllUsers(limit: 200)
    }

    func fetchAllUsers(limit: Int) async throws -> [User] {
        let db = try await core.getPublicDatabase()

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "username", ascending: true)]

        let results = try await db.records(matching: query, resultsLimit: limit)

        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record) {
                users.append(user)
            }
        }

        logger.info("Fetched \(users.count) total users from PUBLIC database")
        return users
    }

    func fetchSuggestedUsers(limit: Int) async throws -> [User] {
        let db = try await core.getPublicDatabase()

        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let results = try await db.records(matching: query, resultsLimit: limit)

        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record) {
                users.append(user)
            }
        }

        return users
    }

    /// Fetch user by record name
    func fetchUser(cloudRecordName: String) async throws -> User? {
        let recordID = CKRecord.ID(recordName: cloudRecordName)
        do {
            let db = try await core.getPublicDatabase()
            let record = try await db.record(for: recordID)
            return try userFromRecord(record)
        } catch {
            logger.error("Failed to fetch user: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch user by their userId (UUID)
    func fetchUser(byUserId userId: UUID) async throws -> User? {
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)

        let results = try await db.records(matching: query, resultsLimit: 1)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                return try? userFromRecord(record)
            }
        }

        logger.debug("No user found with userId: \(userId)")
        return nil
    }

    /// Fetch multiple users by their userIds
    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }

        var users: [User] = []
        var seenUserIds = Set<UUID>()
        let db = try await core.getPublicDatabase()

        for userIdChunk in Self.chunked(userIds.map(\.uuidString), size: 100) {
            let predicate = NSPredicate(format: "userId IN %@", userIdChunk)
            let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)
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
                          let user = try? userFromRecord(record),
                          seenUserIds.insert(user.id).inserted else {
                        continue
                    }
                    users.append(user)
                }

                cursor = results.queryCursor
            } while cursor != nil
        }

        return users
    }

    /// Delete user profile from CloudKit
    func deleteUserProfile(userId: UUID) async throws {
        logger.info("🗑️ Deleting user profile from CloudKit: \(userId)")

        let db = try await core.getPublicDatabase()
        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let ownedProfileRecordNames = Set([
            systemUserRecordID.recordName,
            "user_\(systemUserRecordID.recordName)",
        ])
        var profileRecordIDs = Set<CKRecord.ID>()
        var profileImageRecordIDs: Set<CKRecord.ID> = [
            CKRecord.ID(recordName: "profileImage_\(userId.uuidString)")
        ]

        let userRecords = try await fetchRecords(
            in: db,
            recordType: CloudKitCore.RecordType.user,
            predicate: NSPredicate(format: "userId == %@", userId.uuidString)
        )

        for record in userRecords {
            guard record.creatorUserRecordID == systemUserRecordID,
                  ownedProfileRecordNames.contains(record.recordID.recordName) else {
                logger.warning("Ignoring non-owned or non-canonical User record during account deletion: \(record.recordID.recordName)")
                continue
            }
            profileRecordIDs.insert(record.recordID)
            if let imageRecordName = record["cloudProfileImageRecordName"] as? String {
                profileImageRecordIDs.insert(CKRecord.ID(recordName: imageRecordName))
            }
        }

        let referralRecordIDs = try await fetchReferralRecordIDs(
            for: userId,
            createdBy: systemUserRecordID,
            in: db
        )

        try await deleteRecordsIgnoringMissing(profileImageRecordIDs, in: db, label: "profile image")
        try await deleteRecordsIgnoringMissing(referralRecordIDs, in: db, label: "referral")
        try await releaseOtherUsernameClaims(
            keeping: nil,
            userId: userId,
            identityRecordID: systemUserRecordID,
            in: db
        )
        try await deleteRecordsIgnoringMissing(profileRecordIDs, in: db, label: "user profile")

        logger.info("✅ Deleted \(profileRecordIDs.count) user profile record(s), \(profileImageRecordIDs.count) profile image record(s), and \(referralRecordIDs.count) referral record(s) from CloudKit")
    }

    // MARK: - Profile Image

    /// Upload user profile image to CloudKit
    func uploadUserProfileImage(userId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading profile image for user: \(userId)")

        let optimizedData = try await core.optimizeImageForCloudKit(imageData, maxDimension: 800, targetSize: 1_000_000)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile_\(userId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let asset = CKAsset(fileURL: tempURL)
        let db = try await core.getPublicDatabase()

        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            let imageRecord = try await fetchOrCreateRecord(
                in: db,
                recordID: imageRecordID,
                recordType: CloudKitCore.RecordType.profileImage
            )

            imageRecord["imageAsset"] = asset
            imageRecord["userId"] = userId.uuidString as CKRecordValue
            imageRecord["modifiedAt"] = Date() as CKRecordValue

            guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: userId) else {
                throw CancellationError()
            }
            defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
            let savedImageRecord = try await db.save(imageRecord)
            logger.info("✅ Uploaded profile image to separate record")

            return savedImageRecord.recordID.recordName

        } catch let error as CKError {
            if error.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded - cannot upload profile image")
                throw CloudKitError.quotaExceeded
            }
            throw error
        }
    }

    /// Download user profile image from CloudKit
    func downloadUserProfileImage(userId: UUID) async throws -> Data? {
        logger.info("📥 Downloading profile image for user: \(userId)")

        let db = try await core.getPublicDatabase()

        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            let imageRecord = try await db.record(for: imageRecordID)

            guard let asset = imageRecord["imageAsset"] as? CKAsset,
                  let fileURL = asset.fileURL else {
                logger.info("No profile image asset found for user: \(userId)")
                return nil
            }

            let data = try Data(contentsOf: fileURL)
            logger.info("✅ Downloaded profile image (\(data.count) bytes)")
            return data

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("No profile image record found for user: \(userId)")
                return nil
            }
            throw error
        }
    }

    /// Delete user profile image from CloudKit
    func deleteUserProfileImage(userId: UUID) async throws {
        logger.info("🗑️ Deleting profile image for user: \(userId)")

        let db = try await core.getPublicDatabase()

        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            try await db.deleteRecord(withID: imageRecordID)
            logger.info("✅ Deleted profile image record")

        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("No profile image record found to delete for user: \(userId)")
                return
            }
            throw error
        }
    }

    private func fetchRecords(
        in db: CKDatabase,
        recordType: String,
        predicate: NSPredicate,
        resultsLimit: Int = 500
    ) async throws -> [CKRecord] {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var cursor: CKQueryOperation.Cursor?
        var records: [CKRecord] = []

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: resultsLimit)
            } else {
                results = try await db.records(matching: query, resultsLimit: resultsLimit)
            }

            for (_, result) in results.matchResults {
                records.append(try result.get())
            }

            cursor = results.queryCursor
        } while cursor != nil

        return records
    }

    private func fetchReferralRecordIDs(
        for userId: UUID,
        createdBy systemUserRecordID: CKRecord.ID,
        in db: CKDatabase
    ) async throws -> Set<CKRecord.ID> {
        let userIdString = userId.uuidString
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "newUserId == %@", userIdString),
            NSPredicate(format: "referrerId == %@", userIdString)
        ])

        let records = try await fetchRecords(
            in: db,
            recordType: CloudKitCore.RecordType.referralSignup,
            predicate: predicate
        )

        return Set(records.compactMap { record in
            guard record.creatorUserRecordID == systemUserRecordID else {
                logger.info("Leaving foreign-created referral record for server-side retention cleanup: \(record.recordID.recordName)")
                return nil
            }
            return record.recordID
        })
    }

    private func deleteRecordsIgnoringMissing(
        _ recordIDs: Set<CKRecord.ID>,
        in db: CKDatabase,
        label: String
    ) async throws {
        for recordID in recordIDs {
            do {
                try await db.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                logger.info("\(label) record already absent: \(recordID.recordName)")
            } catch {
                logger.error("Failed to delete \(label) record \(recordID.recordName): \(error.localizedDescription)")
                throw error
            }
        }
    }

    // MARK: - Referral System

    /// Look up a user by their referral code
    func lookupUserByReferralCode(_ code: String) async throws -> User? {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
        guard normalizedCode.count == 6 else {
            logger.warning("Invalid referral code format: \(code)")
            return nil
        }

        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "referralCode == %@", normalizedCode)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)

        do {
            let results = try await db.records(matching: query, resultsLimit: 1)

            for (_, result) in results.matchResults {
                if let record = try? result.get() {
                    let user = try userFromRecord(record)
                    logger.info("Found user for referral code: \(user.displayName)")
                    return user
                }
            }
        } catch {
            if !isReferralSchemaQueryError(error) {
                throw error
            }

            logger.warning("Referral code index query unavailable (\(error.localizedDescription)); falling back to full scan")
        }

        if let fallbackUser = try await lookupUserByReferralCodeViaScan(normalizedCode) {
            return fallbackUser
        }

        logger.info("No user found for referral code: \(normalizedCode)")
        return nil
    }

    /// Record a referral signup in CloudKit
    func recordReferralSignup(referrerId: UUID, newUserId: UUID) async throws {
        let db = try await core.getPublicDatabase()

        let recordName = "referral_\(newUserId.uuidString)"
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            _ = try await db.record(for: recordID)
            logger.info("Referral signup already exists for user: \(newUserId)")
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Good - no existing record
        }

        let record = CKRecord(recordType: CloudKitCore.RecordType.referralSignup, recordID: recordID)
        record["referrerId"] = referrerId.uuidString as CKRecordValue
        record["newUserId"] = newUserId.uuidString as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue

        guard let publicationLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: newUserId) else {
            throw CancellationError()
        }
        defer { Task { await AccountDeletionGate.shared.releasePublicationLease(publicationLease) } }
        _ = try await db.save(record)
        logger.info("✅ Recorded referral signup: \(newUserId) referred by \(referrerId)")
    }

    private func acquirePublicationLease(
        ownerID: UUID,
        allowDuringAccountDeletion: Bool
    ) async throws -> AccountDeletionGate.PublicationLease? {
        guard !allowDuringAccountDeletion else { return nil }
        guard let lease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerID) else {
            throw CancellationError()
        }
        return lease
    }

    private func releasePublicationLease(_ lease: AccountDeletionGate.PublicationLease?) {
        guard let lease else { return }
        Task { await AccountDeletionGate.shared.releasePublicationLease(lease) }
    }

    /// Fetch a user's referral count from CloudKit
    func fetchReferralCount(for userId: UUID) async throws -> Int {
        let db = try await core.getPublicDatabase()

        let predicate = NSPredicate(format: "referrerId == %@", userId.uuidString)
        let query = CKQuery(recordType: CloudKitCore.RecordType.referralSignup, predicate: predicate)

        do {
            let results = try await db.records(matching: query, resultsLimit: 200)
            let count = results.matchResults.count
            logger.info("Fetched referral count for \(userId): \(count)")
            return count
        } catch {
            if isReferralSchemaQueryError(error) {
                logger.warning("Referral count index query unavailable (\(error.localizedDescription)); falling back to full scan")
                let count = try await fetchReferralCountViaScan(for: userId)
                logger.info("Fetched referral count via full scan for \(userId): \(count)")
                return count
            }
            throw error
        }
    }

    /// Fetch users who joined using a referrer's code.
    /// Ordered by most recent signup first.
    func fetchReferredUsers(for userId: UUID, limit: Int = 50) async throws -> [User] {
        let db = try await core.getPublicDatabase()
        let userIdString = userId.uuidString

        let orderedUserIds: [UUID]
        do {
            let predicate = NSPredicate(format: "referrerId == %@", userIdString)
            let query = CKQuery(recordType: CloudKitCore.RecordType.referralSignup, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

            let results = try await db.records(matching: query, resultsLimit: limit)
            orderedUserIds = results.matchResults.compactMap { _, result in
                guard let record = try? result.get(),
                      let newUserIdString = record["newUserId"] as? String else {
                    return nil
                }
                return UUID(uuidString: newUserIdString)
            }
        } catch {
            if isReferralSchemaQueryError(error) {
                logger.warning("Referral list query unavailable (\(error.localizedDescription)); falling back to full scan")
                orderedUserIds = try await fetchReferredUserIDsViaScan(for: userId, limit: limit)
            } else {
                throw error
            }
        }

        guard !orderedUserIds.isEmpty else { return [] }

        var seen = Set<UUID>()
        let dedupedOrderedIds = orderedUserIds.filter { seen.insert($0).inserted }
        let fetchedUsers = try await fetchUsers(byUserIds: dedupedOrderedIds)
        let usersById = Dictionary(fetchedUsers.map { ($0.id, $0) }, uniquingKeysWith: { current, candidate in
            candidate.createdAt > current.createdAt ? candidate : current
        })

        return dedupedOrderedIds.compactMap { usersById[$0] }
    }

    // MARK: - Private Helpers

    private func deriveReferralCodeFromRecordName(for user: User) -> String {
        let baseId: String
        if let cloudRecordName = user.cloudRecordName {
            baseId = cloudRecordName.replacingOccurrences(of: "user_", with: "")
        } else {
            baseId = user.id.uuidString
        }

        let cleanId = baseId.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        let prefix = String(cleanId.prefix(6)).uppercased()
        return prefix.padding(toLength: 6, withPad: "X", startingAt: 0)
    }

    private func normalizeReferralCode(_ code: String) -> String {
        code.uppercased().trimmingCharacters(in: .whitespaces)
    }

    private func isReferralCodeAvailable(_ code: String) async throws -> Bool {
        let normalizedCode = normalizeReferralCode(code)
        let db = try await core.getPublicDatabase()
        let predicate = NSPredicate(format: "referralCode == %@", normalizedCode)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)

        do {
            let results = try await db.records(matching: query, resultsLimit: 1)
            return results.matchResults.isEmpty
        } catch {
            if isReferralSchemaQueryError(error) {
                logger.warning("Referral code availability query unavailable (\(error.localizedDescription)); using full scan fallback")
                return try await isReferralCodeAvailableViaScan(normalizedCode)
            }
            throw error
        }
    }

    private func lookupUserByReferralCodeViaScan(_ normalizedCode: String) async throws -> User? {
        let db = try await core.getPublicDatabase()
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: NSPredicate(value: true))
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor = cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
            } else {
                results = try await db.records(matching: query, resultsLimit: 500)
            }

            for (_, result) in results.matchResults {
                guard let record = try? result.get(),
                      let user = try? userFromRecord(record) else {
                    continue
                }

                let storedCode = normalizeReferralCode(user.referralCode ?? "")
                let legacyCode = deriveReferralCodeFromRecordName(for: user)
                if storedCode == normalizedCode || legacyCode == normalizedCode {
                    logger.info("Found user for referral code via full scan: \(user.displayName)")
                    return user
                }
            }

            cursor = results.queryCursor
        } while cursor != nil

        return nil
    }

    private func fetchReferralCountViaScan(for userId: UUID) async throws -> Int {
        let db = try await core.getPublicDatabase()
        let query = CKQuery(recordType: CloudKitCore.RecordType.referralSignup, predicate: NSPredicate(value: true))
        let userIdString = userId.uuidString
        var cursor: CKQueryOperation.Cursor?
        var count = 0

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor = cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
            } else {
                results = try await db.records(matching: query, resultsLimit: 500)
            }

            for (_, result) in results.matchResults {
                guard let record = try? result.get(),
                      let referrerId = record["referrerId"] as? String else {
                    continue
                }

                if referrerId == userIdString {
                    count += 1
                }
            }

            cursor = results.queryCursor
        } while cursor != nil

        return count
    }

    private func fetchReferredUserIDsViaScan(for userId: UUID, limit: Int) async throws -> [UUID] {
        let db = try await core.getPublicDatabase()
        let query = CKQuery(recordType: CloudKitCore.RecordType.referralSignup, predicate: NSPredicate(value: true))
        let userIdString = userId.uuidString

        var cursor: CKQueryOperation.Cursor?
        var matches: [(id: UUID, createdAt: Date)] = []

        repeat {
            let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor = cursor {
                results = try await db.records(continuingMatchFrom: cursor, resultsLimit: 500)
            } else {
                results = try await db.records(matching: query, resultsLimit: 500)
            }

            for (_, result) in results.matchResults {
                guard let record = try? result.get(),
                      let referrerId = record["referrerId"] as? String,
                      referrerId == userIdString,
                      let newUserIdString = record["newUserId"] as? String,
                      let newUserId = UUID(uuidString: newUserIdString) else {
                    continue
                }

                let createdAt = record["createdAt"] as? Date ?? .distantPast
                matches.append((id: newUserId, createdAt: createdAt))
            }

            cursor = results.queryCursor
        } while cursor != nil

        let sorted = matches.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<UUID>()
        var orderedIds: [UUID] = []

        for match in sorted where seen.insert(match.id).inserted {
            orderedIds.append(match.id)
            if orderedIds.count >= limit {
                break
            }
        }

        return orderedIds
    }

    private func isReferralCodeAvailableViaScan(_ normalizedCode: String) async throws -> Bool {
        let user = try await lookupUserByReferralCodeViaScan(normalizedCode)
        if case nil = user {
            return true
        }
        return false
    }

    private func isReferralSchemaQueryError(_ error: Error) -> Bool {
        if let ckError = error as? CKError {
            switch ckError.code {
            case .invalidArguments, .unknownItem:
                return true
            default:
                break
            }
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("unknown field")
            || message.contains("didn't match")
            || message.contains("not marked queryable")
            || message.contains("queryable")
            || message.contains("unknown record type")
    }

    private func generateUniqueReferralCode(preferred: String? = nil) async throws -> String {
        if let preferred = preferred {
            let normalizedPreferred = normalizeReferralCode(preferred)
            if normalizedPreferred.count == 6, try await isReferralCodeAvailable(normalizedPreferred) {
                return normalizedPreferred
            }
        }

        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        for _ in 0..<32 {
            let code = String((0..<6).compactMap { _ in characters.randomElement() })
            if try await isReferralCodeAvailable(code) {
                return code
            }
        }

        let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
        return String(fallback)
    }

    private func ensureReferralCodeIfNeeded(for user: User) async throws -> User {
        if let referralCode = user.referralCode,
           !referralCode.isEmpty,
           normalizeReferralCode(referralCode).count == 6 {
            return user
        }

        let preferred = deriveReferralCodeFromRecordName(for: user)
        let uniqueCode = try await generateUniqueReferralCode(preferred: preferred)
        let updatedUser = User(
            id: user.id,
            username: user.username,
            displayName: user.displayName,
            email: user.email,
            cloudRecordName: user.cloudRecordName,
            referralCode: uniqueCode,
            createdAt: user.createdAt,
            profileEmoji: user.profileEmoji,
            profileColor: user.profileColor,
            profileImageURL: user.profileImageURL,
            cloudProfileImageRecordName: user.cloudProfileImageRecordName,
            profileImageModifiedAt: user.profileImageModifiedAt
        )

        try await saveUser(updatedUser)
        return updatedUser
    }

    private func fetchOrCreateRecord(
        in database: CKDatabase,
        recordID: CKRecord.ID,
        recordType: String
    ) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    func populateUserRecord(_ record: CKRecord, from user: User) {
        let normalizedUsername = user.username.trimmingCharacters(in: .whitespaces).lowercased()
        let normalizedDisplayName = user.displayName.trimmingCharacters(in: .whitespaces)

        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = normalizedUsername as CKRecordValue
        record["displayName"] = normalizedDisplayName as CKRecordValue
        record["createdAt"] = user.createdAt as CKRecordValue

        if let referralCode = user.referralCode, !referralCode.isEmpty {
            record["referralCode"] = normalizeReferralCode(referralCode) as CKRecordValue
        } else {
            record["referralCode"] = nil
        }

        if let email = user.email {
            record["email"] = email as CKRecordValue
        } else {
            record["email"] = nil
        }

        if let emoji = user.profileEmoji {
            record["profileEmoji"] = emoji as CKRecordValue
        } else {
            record["profileEmoji"] = nil
        }

        if let color = user.profileColor {
            record["profileColor"] = color as CKRecordValue
        } else {
            record["profileColor"] = nil
        }

        if let cloudImageRecordName = user.cloudProfileImageRecordName {
            record["cloudProfileImageRecordName"] = cloudImageRecordName as CKRecordValue
        } else {
            record["cloudProfileImageRecordName"] = nil
        }

        if let imageModifiedAt = user.profileImageModifiedAt {
            record["profileImageModifiedAt"] = imageModifiedAt as CKRecordValue
        } else {
            record["profileImageModifiedAt"] = nil
        }
    }

    func userFromRecord(_ record: CKRecord) throws -> User {
        guard let userIdString = record["userId"] as? String,
              let userId = UUID(uuidString: userIdString),
              let username = record["username"] as? String,
              let displayName = record["displayName"] as? String else {
            logger.error("Invalid user record - missing required fields. Record: \(record)")
            throw CloudKitError.invalidRecord
        }

        let email = record["email"] as? String
        let createdAt = record["createdAt"] as? Date ?? Date()
        let referralCode = record["referralCode"] as? String
        let profileEmoji = record["profileEmoji"] as? String
        let profileColor = record["profileColor"] as? String
        let cloudProfileImageRecordName = record["cloudProfileImageRecordName"] as? String
        let profileImageModifiedAt = record["profileImageModifiedAt"] as? Date

        return User(
            id: userId,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: record.recordID.recordName,
            referralCode: referralCode,
            createdAt: createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: nil,
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt
        )
    }

    private nonisolated static func chunked<Value>(_ values: [Value], size: Int) -> [[Value]] {
        guard size > 0, !values.isEmpty else { return [] }

        return stride(from: 0, to: values.count, by: size).map { startIndex in
            let endIndex = min(startIndex + size, values.count)
            return Array(values[startIndex..<endIndex])
        }
    }
}
