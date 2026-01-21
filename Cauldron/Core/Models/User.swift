//
//  User.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Represents a user who can share recipes
struct User: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let username: String
    let displayName: String
    let email: String?
    let cloudRecordName: String?  // CloudKit record name
    let referralCode: String?  // Unique referral code
    let createdAt: Date
    let profileEmoji: String?  // Emoji for profile avatar (mutually exclusive with profileImageURL)
    let profileColor: String?  // Hex color string for profile avatar
    let profileImageURL: URL?  // Local file URL for profile image
    let cloudProfileImageRecordName: String?  // CloudKit record name for profile image asset
    let profileImageModifiedAt: Date?  // Last modified date for sync tracking

    init(
        id: UUID = UUID(),
        username: String,
        displayName: String,
        email: String? = nil,
        cloudRecordName: String? = nil,
        referralCode: String? = nil,
        createdAt: Date = Date(),
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        profileImageURL: URL? = nil,
        cloudProfileImageRecordName: String? = nil,
        profileImageModifiedAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.cloudRecordName = cloudRecordName
        self.referralCode = referralCode
        self.createdAt = createdAt
        self.profileEmoji = profileEmoji
        self.profileColor = profileColor
        self.profileImageURL = profileImageURL
        self.cloudProfileImageRecordName = cloudProfileImageRecordName
        self.profileImageModifiedAt = profileImageModifiedAt
    }

    /// Get user's initials from display name
    var initials: String {
        let words = displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if !displayName.isEmpty {
            return String(displayName.prefix(2)).uppercased()
        }
        return "?"
    }

    /// Create a copy with updated profile fields
    func updatedProfile(
        profileEmoji: String? = nil,
        profileColor: String? = nil,
        profileImageURL: URL? = nil,
        cloudProfileImageRecordName: String? = nil,
        profileImageModifiedAt: Date? = nil
    ) -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: cloudRecordName,
            referralCode: referralCode,
            createdAt: createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: profileImageURL,
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt
        )
    }

    /// Check if the profile image needs to be uploaded to CloudKit
    /// - Parameter localImageModified: The modification date of the local image file
    /// - Returns: True if local image is newer than cloud or no cloud image exists
    func needsProfileImageUpload(localImageModified: Date?) -> Bool {
        // If no local image, no upload needed
        guard let localModified = localImageModified else {
            return false
        }

        // If no cloud image record, upload needed
        guard cloudProfileImageRecordName != nil else {
            return true
        }

        // If no cloud modification date, upload needed
        guard let cloudModified = profileImageModifiedAt else {
            return true
        }

        // Upload if local is newer than cloud
        return localModified > cloudModified
    }
}
