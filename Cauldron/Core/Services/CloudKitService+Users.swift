//
//  CloudKitService+Users.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import CloudKit
import os

extension CloudKitService {
    // MARK: - User Lifecycle

    /// Fetch existing user profile from CloudKit (returns nil if not found)
    /// Checks:
    /// 1. Custom record name (user_<SystemID>) in PUBLIC database
    /// 2. If not found, checks PRIVATE database (legacy) and migrates if found
    /// 3. If not found, checks system record ID in PUBLIC (backward compatibility)
    func fetchCurrentUserProfile() async throws -> User? {
        // First check account status
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            logger.warning("CloudKit account not available: \(accountStatus)")
            return nil
        }

        let db = try getPublicDatabase()
        
        // precise logic for getting system ID is needed here, checking previous file content...
        // Ah, `container.userRecordID()` is used. I'll need to make sure I have access to container.
        
        guard let container = container else {
             throw CloudKitError.notEnabled
        }
        let systemUserRecordID = try await container.userRecordID()
        
        let customRecordName = "user_\(systemUserRecordID.recordName)"
        let customRecordID = CKRecord.ID(recordName: customRecordName)

        // 1. Try fetching from PUBLIC database with custom record name
        do {
            let record = try await db.record(for: customRecordID)
            if record["userId"] != nil {
                let user = try userFromRecord(record)
                logger.info("✅ Found user profile in CloudKit PUBLIC database: \(user.username)")
                return user
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found in public DB, try migration
            if let migratedUser = try await migrateUserFromPrivateToPublic() {
                return migratedUser
            }
            // Continue to fallback
        } catch {
            logger.warning("Error fetching user by custom ID: \(error.localizedDescription)")
        }

        // Fallback: Try the old system record ID (for backwards compatibility)
        do {
            let record = try await db.record(for: systemUserRecordID)
            // Check if this record has valid User fields
            if record["userId"] != nil {
                let user = try userFromRecord(record)
                logger.info("✅ Found user profile (legacy) in CloudKit PUBLIC database")
                return user
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found
        } catch {
            logger.warning("Error fetching user by system ID: \(error.localizedDescription)")
        }

        // No valid user profile found
        logger.info("No existing user profile found in CloudKit PUBLIC database")
        return nil
    }

    /// Migrate user from PRIVATE database to PUBLIC database (backward compatibility)
    func migrateUserFromPrivateToPublic() async throws -> User? {
        logger.info("Checking for user in PRIVATE database (migration)...")

        let privateDB = try getPrivateDatabase()
        // We need system record ID to check private DB default zone
         guard let container = container else { return nil }
        let systemUserRecordID = try await container.userRecordID()
        
        let customRecordName = "user_\(systemUserRecordID.recordName)"
        let customRecordID = CKRecord.ID(recordName: customRecordName)

        // Try custom name in PRIVATE first
        do {
            let record = try await privateDB.record(for: customRecordID)
            if record["userId"] != nil, let user = try? userFromRecord(record) {
                logger.info("Found user in PRIVATE database via custom ID. Migrating to PUBLIC...")
                
                // Save to PUBLIC
                try await saveUser(user)
                logger.info("✅ Migration complete for \(user.username)")
                
                // Optionally delete from private, but keeping as backup is safer for now
                return user
            }
        } catch let error as CKError where error.code == .unknownItem {
            // Not found with custom name, try system ID
        }

        // Try system record ID
        do {
            let record = try await privateDB.record(for: systemUserRecordID)
            if record["userId"] != nil, let user = try? userFromRecord(record) {
                logger.info("Found user in PRIVATE database via system ID. Migrating to PUBLIC...")
                
                // Save to PUBLIC
                try await saveUser(user)
                logger.info("✅ Migration complete for \(user.username)")
                return user
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
        // First check account status
        let accountStatus = await checkAccountStatus()
        guard accountStatus.isAvailable else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        if let existingUser = try await fetchCurrentUserProfile() {
            return existingUser
        }

        // Create new user
         guard let container = container else { throw CloudKitError.notEnabled }
        let systemUserRecordID = try await container.userRecordID()
        let customRecordName = "user_\(systemUserRecordID.recordName)"
        
        let user = User(
            username: username,
            displayName: displayName,
            cloudRecordName: customRecordName,
            profileEmoji: profileEmoji,
            profileColor: profileColor
        )
        try await saveUser(user)
        return user
    }
    
    // MARK: - Users
    
    /// Save user to CloudKit
    func saveUser(_ user: User) async throws {
        // Use custom record name if provided, otherwise create one
        let recordName: String
        if let cloudRecordName = user.cloudRecordName {
            recordName = cloudRecordName
        } else {
            // Create a custom record name to avoid conflicts with system records
             guard let container = container else { throw CloudKitError.notEnabled }
            let systemUserRecordID = try await container.userRecordID()
            recordName = "user_\(systemUserRecordID.recordName)"
        }

        let recordID = CKRecord.ID(recordName: recordName)
        let db = try getPublicDatabase()

        // Try to fetch existing record first to update it, otherwise create new one
        let record: CKRecord
        do {
            record = try await db.record(for: recordID)
            logger.info("Updating existing user record in CloudKit: \(user.username)")
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist, create new one
            record = CKRecord(recordType: userRecordType, recordID: recordID)
            logger.info("Creating new user record in CloudKit: \(user.username)")
        } catch {
            // Other error, rethrow
            logger.error("Error fetching existing user record: \(error.localizedDescription)")
            throw error
        }

        // Update/set all fields
        record["userId"] = user.id.uuidString as CKRecordValue
        record["username"] = user.username as CKRecordValue
        record["displayName"] = user.displayName as CKRecordValue
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

        // Save to PUBLIC database so other users can discover this user
        _ = try await db.save(record)
        logger.info("Saved user: \(user.username) to PUBLIC database")
    }
    
    /// Search for users by username (public search)
    /// Note: CloudKit has limited predicate support. We use BEGINSWITH for prefix matching.
    /// For better UX, we search both fields separately and combine results.
    func searchUsers(query: String) async throws -> [User] {
        let db = try getPublicDatabase()
        let lowercaseQuery = query.lowercased()

        // CloudKit doesn't support CONTAINS, so we use BEGINSWITH on both fields
        // We need to search both username and displayName separately
        let usernamePredicate = NSPredicate(format: "username BEGINSWITH %@", lowercaseQuery)
        let usernameQuery = CKQuery(recordType: userRecordType, predicate: usernamePredicate)

        let displayNamePredicate = NSPredicate(format: "displayName BEGINSWITH %@", query)
        let displayNameQuery = CKQuery(recordType: userRecordType, predicate: displayNamePredicate)

        var users: [User] = []
        var userIds = Set<UUID>() // To avoid duplicates

        // Search by username
        let usernameResults = try await db.records(matching: usernameQuery)
        for (_, result) in usernameResults.matchResults {
            if let record = try? result.get(),
               let user = try? userFromRecord(record),
               !userIds.contains(user.id) {
                users.append(user)
                userIds.insert(user.id)
            }
        }

        // Search by displayName
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
        let db = try getPublicDatabase()

        // Query all users (no predicate = fetch all)
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
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
            let db = try getPublicDatabase()
            let record = try await db.record(for: recordID)
            return try userFromRecord(record)
        } catch {
            logger.error("Failed to fetch user: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetch user by their userId (UUID)
    /// This queries the PUBLIC database for a user with the given userId field
    func fetchUser(byUserId userId: UUID) async throws -> User? {
        let db = try getPublicDatabase()
        let predicate = NSPredicate(format: "userId == %@", userId.uuidString)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)

        let results = try await db.records(matching: query, resultsLimit: 1)

        for (_, result) in results.matchResults {
            if let record = try? result.get() {
                return try? userFromRecord(record)
            }
        }

        logger.warning("No user found with userId: \(userId)")
        return nil
    }

    /// Fetch multiple users by their userIds (UUID)
    func fetchUsers(byUserIds userIds: [UUID]) async throws -> [User] {
        guard !userIds.isEmpty else { return [] }
        
        let db = try getPublicDatabase()
        let userIdStrings = userIds.map { $0.uuidString }
        
        // Use IN predicate to fetch all users at once
        let predicate = NSPredicate(format: "userId IN %@", userIdStrings)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)
        
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
    
    /// Helper to assist finding current user record ID
    /// This was implicitly used in fetchOrCreateCurrentUser.
    func getCurrentUserRecordID() async throws -> CKRecord.ID {
        guard let container = container else {
             throw CloudKitError.notEnabled
        }
        return try await container.userRecordID()
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
            createdAt: createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: nil,  // Will be set after downloading image
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt
        )
    }
    
    // MARK: - User Profile Image Methods
    
    /// Upload user profile image to CloudKit
    /// - Parameters:
    ///   - userId: The user ID this image belongs to
    ///   - imageData: The image data to upload
    /// - Returns: The CloudKit record name for the uploaded asset
    func uploadUserProfileImage(userId: UUID, imageData: Data) async throws -> String {
        logger.info("📤 Uploading profile image for user: \(userId)")

        // Optimize image before upload
        let optimizedData = try await optimizeImageForCloudKit(imageData)

        // Create temporary file for CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile_\(userId.uuidString)")
            .appendingPathExtension("jpg")

        try optimizedData.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Create CKAsset
        let asset = CKAsset(fileURL: tempURL)

        // Get public database
        let db = try getPublicDatabase()

        // Create a separate ProfileImage record instead of storing in User record
        // This avoids schema issues and is cleaner architecture
        let imageRecordName = "profileImage_\(userId.uuidString)"
        let imageRecordID = CKRecord.ID(recordName: imageRecordName)

        do {
            // Try to fetch existing image record first
            let imageRecord: CKRecord
            do {
                imageRecord = try await db.record(for: imageRecordID)
                logger.info("Updating existing profile image record")
            } catch let error as CKError where error.code == .unknownItem {
                // Create new image record
                imageRecord = CKRecord(recordType: "ProfileImage", recordID: imageRecordID)
                logger.info("Creating new profile image record")
            }

            // Set the asset and metadata
            imageRecord["imageAsset"] = asset
            imageRecord["userId"] = userId.uuidString as CKRecordValue
            imageRecord["modifiedAt"] = Date() as CKRecordValue

            // Save the image record
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
    /// - Parameter userId: The user ID to download image for
    /// - Returns: The image data, or nil if no image exists
    func downloadUserProfileImage(userId: UUID) async throws -> Data? {
        logger.info("📥 Downloading profile image for user: \(userId)")

        let db = try getPublicDatabase()

        // Look for ProfileImage record using the userId-based naming convention
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
    /// - Parameter userId: The user ID to delete image for
    func deleteUserProfileImage(userId: UUID) async throws {
        logger.info("🗑️ Deleting profile image for user: \(userId)")

        let db = try getPublicDatabase()

        // Delete the separate ProfileImage record
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

    /// Delete user profile from CloudKit (for account deletion)
    /// - Parameter userId: The user ID to delete
    func deleteUserProfile(userId: UUID) async throws {
        logger.info("🗑️ Deleting user profile from CloudKit: \(userId)")

        let db = try getPublicDatabase()

        // Get user's CloudKit record
        let systemUserRecordID = try await getCurrentUserRecordID()
        let recordName = "user_\(systemUserRecordID.recordName)"
        let recordID = CKRecord.ID(recordName: recordName)

        do {
            // Delete user profile image first if exists
            try await deleteUserProfileImage(userId: userId)

            // Delete the user record itself
            _ = try await db.deleteRecord(withID: recordID)
            logger.info("✅ Deleted user profile from CloudKit")
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("User record not found: \(userId)")
                // Not an error - already deleted
                return
            }
            logger.error("Failed to delete user profile: \(error.localizedDescription)")
            throw error
        }
    }
}
