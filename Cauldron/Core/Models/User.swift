//
//  User.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

/// Represents a user who can share recipes
struct User: Sendable, Hashable, Identifiable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case email
        case cloudRecordName
        case referralCode
        case createdAt
        case profileEmoji
        case profileColor
        case profileImageURL
        case cloudProfileImageRecordName
        case profileImageModifiedAt
    }

    nonisolated init(
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
    nonisolated var initials: String {
        let words = displayName.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        } else if !displayName.isEmpty {
            return String(displayName.prefix(2)).uppercased()
        }
        return "?"
    }

    /// Create a copy with updated profile fields
    nonisolated func updatedProfile(
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
    nonisolated func needsProfileImageUpload(localImageModified: Date?) -> Bool {
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

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        self.email = try container.decodeIfPresent(String.self, forKey: .email)
        self.cloudRecordName = try container.decodeIfPresent(String.self, forKey: .cloudRecordName)
        self.referralCode = try container.decodeIfPresent(String.self, forKey: .referralCode)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.profileEmoji = try container.decodeIfPresent(String.self, forKey: .profileEmoji)
        self.profileColor = try container.decodeIfPresent(String.self, forKey: .profileColor)
        self.profileImageURL = try container.decodeIfPresent(URL.self, forKey: .profileImageURL)
        self.cloudProfileImageRecordName = try container.decodeIfPresent(String.self, forKey: .cloudProfileImageRecordName)
        self.profileImageModifiedAt = try container.decodeIfPresent(Date.self, forKey: .profileImageModifiedAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(displayName, forKey: .displayName)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(cloudRecordName, forKey: .cloudRecordName)
        try container.encodeIfPresent(referralCode, forKey: .referralCode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(profileEmoji, forKey: .profileEmoji)
        try container.encodeIfPresent(profileColor, forKey: .profileColor)
        try container.encodeIfPresent(profileImageURL, forKey: .profileImageURL)
        try container.encodeIfPresent(cloudProfileImageRecordName, forKey: .cloudProfileImageRecordName)
        try container.encodeIfPresent(profileImageModifiedAt, forKey: .profileImageModifiedAt)
    }
}

extension User: Codable {}
