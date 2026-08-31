//
//  User.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation

enum ProfileAvatarRepresentation: Hashable, Sendable {
    struct PhotoIdentity: Hashable, Sendable {
        let ownerID: UUID
        let localURL: URL?
        let cloudRecordName: String?
        let modifiedAt: Date?
        let localRevision: UUID?

        nonisolated var cacheIdentity: String {
            if let cloudRecordName {
                return [
                    ownerID.uuidString,
                    cloudRecordName,
                    modifiedAt.map { String($0.timeIntervalSinceReferenceDate) } ?? "no-modified-date"
                ].joined(separator: "|")
            }
            return [
                ownerID.uuidString,
                localRevision?.uuidString ?? "no-local-revision",
                localURL?.absoluteString ?? "no-local-url"
            ].joined(separator: "|")
        }
    }

    case photo(PhotoIdentity)
    case emoji(value: String, colorHex: String?)
    case initials(value: String, colorHex: String?)

    nonisolated var isPhoto: Bool {
        if case .photo = self { return true }
        return false
    }
}

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
    let profileImageLocalRevision: UUID?  // Local-only revision for same-path image refreshes

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
        case profileImageLocalRevision
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
        profileImageModifiedAt: Date? = nil,
        profileImageLocalRevision: UUID? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.cloudRecordName = cloudRecordName
        self.referralCode = referralCode
        self.createdAt = createdAt
        let normalizedEmoji = profileEmoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedEmoji, !normalizedEmoji.isEmpty {
            // Legacy records can contain both emoji and photo metadata after an
            // interrupted avatar transition. Every valid photo commit clears the
            // emoji, so a remaining explicit emoji deterministically wins.
            self.profileEmoji = normalizedEmoji
            self.profileColor = profileColor
            self.profileImageURL = nil
            self.cloudProfileImageRecordName = nil
            self.profileImageModifiedAt = nil
            self.profileImageLocalRevision = nil
        } else if profileImageURL != nil || cloudProfileImageRecordName != nil {
            self.profileEmoji = nil
            self.profileColor = nil
            self.profileImageURL = profileImageURL
            self.cloudProfileImageRecordName = cloudProfileImageRecordName
            self.profileImageModifiedAt = profileImageModifiedAt
            self.profileImageLocalRevision = profileImageLocalRevision
        } else {
            self.profileEmoji = nil
            self.profileColor = profileColor
            self.profileImageURL = nil
            self.cloudProfileImageRecordName = nil
            self.profileImageModifiedAt = nil
            self.profileImageLocalRevision = nil
        }
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

    nonisolated var avatarRepresentation: ProfileAvatarRepresentation {
        if let profileEmoji, !profileEmoji.isEmpty {
            return .emoji(value: profileEmoji, colorHex: profileColor)
        }
        if profileImageURL != nil || cloudProfileImageRecordName != nil {
            return .photo(.init(
                ownerID: id,
                localURL: profileImageURL,
                cloudRecordName: cloudProfileImageRecordName,
                modifiedAt: profileImageModifiedAt,
                localRevision: profileImageLocalRevision
            ))
        }
        return .initials(value: initials, colorHex: profileColor)
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
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision
        )
    }

    nonisolated func updatedProfile(
        profileEmoji: String?,
        profileColor: String?,
        profileImageURL: URL?,
        cloudProfileImageRecordName: String?,
        profileImageModifiedAt: Date?,
        profileImageLocalRevision: UUID?
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
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision
        )
    }

    nonisolated func updatedBasicInfo(username: String, displayName: String) -> User {
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
            profileImageModifiedAt: profileImageModifiedAt,
            profileImageLocalRevision: profileImageLocalRevision
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
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            username: try container.decode(String.self, forKey: .username),
            displayName: try container.decode(String.self, forKey: .displayName),
            email: try container.decodeIfPresent(String.self, forKey: .email),
            cloudRecordName: try container.decodeIfPresent(String.self, forKey: .cloudRecordName),
            referralCode: try container.decodeIfPresent(String.self, forKey: .referralCode),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            profileEmoji: try container.decodeIfPresent(String.self, forKey: .profileEmoji),
            profileColor: try container.decodeIfPresent(String.self, forKey: .profileColor),
            profileImageURL: try container.decodeIfPresent(URL.self, forKey: .profileImageURL),
            cloudProfileImageRecordName: try container.decodeIfPresent(String.self, forKey: .cloudProfileImageRecordName),
            profileImageModifiedAt: try container.decodeIfPresent(Date.self, forKey: .profileImageModifiedAt),
            profileImageLocalRevision: try container.decodeIfPresent(UUID.self, forKey: .profileImageLocalRevision)
        )
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
        try container.encodeIfPresent(profileImageLocalRevision, forKey: .profileImageLocalRevision)
    }
}

extension User: Codable {}
