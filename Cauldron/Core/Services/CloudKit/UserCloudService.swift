//
//  UserCloudService.swift
//  Cauldron
//
//  Domain-specific CloudKit service for user profile operations.
//

import Foundation
import CloudKit
import os

/// CloudKit service for user-related operations.
///
/// Handles:
/// - User profile CRUD operations
/// - Profile image upload/download
/// - User search and discovery
/// - Referral system
actor UserCloudService {
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

        let provisionalUser = User(
            username: normalizedUsername,
            displayName: normalizedDisplayName,
            cloudRecordName: customRecordName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
        let referralCode = try await generateUniqueReferralCode(preferred: deriveReferralCodeFromRecordName(for: provisionalUser))

        let user = User(
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
        let normalizedDisplayName = user.displayName.trimmingCharacters(in: .whitespaces)

        let recordName: String
        if let cloudRecordName = user.cloudRecordName {
            recordName = cloudRecordName
        } else {
            let systemUserRecordID = try await core.getCurrentUserRecordID()
            recordName = "user_\(systemUserRecordID.recordName)"
        }

        let recordID = CKRecord.ID(recordName: recordName)
        let db = try await core.getPublicDatabase()

        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing user record in CloudKit: \(normalizedUsername)")
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: CloudKitCore.RecordType.user, recordID: recordID)
            logger.info("Creating new user record in CloudKit: \(normalizedUsername)")
        } catch {
            logger.error("Error fetching existing user record: \(error.localizedDescription)")
            throw error
        }

        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = normalizedUsername as CKRecordValue
        record["displayName"] = normalizedDisplayName as CKRecordValue
        if let referralCode = user.referralCode, !referralCode.isEmpty {
            record["referralCode"] = normalizeReferralCode(referralCode) as CKRecordValue
        }
        if let email = user.email {
            record["email"] = email as CKRecordValue
        }
        if let emoji = user.profileEmoji {
            record["profileEmoji"] = emoji as CKRecordValue
        }
        if let color = user.profileColor {
            record["profileColor"] = color as CKRecordValue
        }
        if let cloudImageRecordName = user.cloudProfileImageRecordName {
            record["cloudProfileImageRecordName"] = cloudImageRecordName as CKRecordValue
        }
        if let imageModifiedAt = user.profileImageModifiedAt {
            record["profileImageModifiedAt"] = imageModifiedAt as CKRecordValue
        }
        record["createdAt"] = user.createdAt as CKRecordValue

        _ = try await db.save(record)
        logger.info("Saved user: \(normalizedUsername) to PUBLIC database")
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
        let db = try await core.getPublicDatabase()

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "username", ascending: true)]

        let results = try await db.records(matching: query, resultsLimit: 200)

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

        logger.warning("No user found with userId: \(userId)")
        return nil
    }

    /// Fetch multiple users by their userIds
    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }

        let db = try await core.getPublicDatabase()
        let userIdStrings = userIds.map { $0.uuidString }

        let predicate = NSPredicate(format: "userId IN %@", userIdStrings)
        let query = CKQuery(recordType: CloudKitCore.RecordType.user, predicate: predicate)

        let results = try await db.records(matching: query, resultsLimit: userIds.count)

        var users: [User] = []
        for (_, result) in results.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record) {
                users.append(user)
            }
        }

        return users
    }

    /// Delete user profile from CloudKit
    func deleteUserProfile(userId: UUID) async throws {
        logger.info("🗑️ Deleting user profile from CloudKit: \(userId)")

        let db = try await core.getPublicDatabase()
        let systemUserRecordID = try await core.getCurrentUserRecordID()
        let recordName = "user_\(systemUserRecordID.recordName)"
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            try await deleteUserProfileImage(userId: userId)

            _ = try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted user profile from CloudKit")
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("User record not found: \(userId)")
                return
            }
            logger.error("Failed to delete user profile: \(error.localizedDescription)")
            throw error
        }
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
            let imageRecord: CKRecord
            do {
                imageRecord = try await db.record(for: imageRecordID)
                logger.info("Updating existing profile image record")
            } catch let error as CKError where error.code == .unknownItem {
                imageRecord = CKRecord(recordType: CloudKitCore.RecordType.profileImage, recordID: imageRecordID)
                logger.info("Creating new profile image record")
            }

            imageRecord["imageAsset"] = asset
            imageRecord["userId"] = userId.uuidString as CKRecordValue
            imageRecord["modifiedAt"] = Date() as CKRecordValue

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
        let results = try await db.records(matching: query, resultsLimit: 1)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                let user = try userFromRecord(record)
                logger.info("Found user for referral code: \(user.displayName)")
                return user
            }
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

        _ = try await db.save(record)
        logger.info("✅ Recorded referral signup: \(newUserId) referred by \(referrerId)")
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
            if error.localizedDescription.contains("Unknown field") ||
               error.localizedDescription.contains("didn't match") {
                logger.info("ReferralSignup records not found for user: \(userId) (may not exist yet)")
                return 0
            }
            throw error
        }
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
            if error.localizedDescription.contains("Unknown field") {
                logger.info("referralCode field not in schema yet - assuming code is available")
                return true
            }
            throw error
        }
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
}
