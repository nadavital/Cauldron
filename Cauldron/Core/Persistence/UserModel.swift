//
//  UserModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import Foundation
import SwiftData

/// SwiftData model for persisting user data
@Model
final class UserModel {
    var id: UUID = UUID()
    var username: String = ""
    var displayName: String = ""
    var email: String? = nil
    var cloudRecordName: String? = nil
    var createdAt: Date = Date()
    var profileEmoji: String? = nil
    var profileColor: String? = nil
    var profileImagePath: String? = nil  // Store URL path as string for SwiftData
    var cloudProfileImageRecordName: String? = nil
    var profileImageModifiedAt: Date? = nil

    init(id: UUID, username: String, displayName: String, email: String? = nil, cloudRecordName: String? = nil, createdAt: Date, profileEmoji: String? = nil, profileColor: String? = nil, profileImagePath: String? = nil, cloudProfileImageRecordName: String? = nil, profileImageModifiedAt: Date? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
        self.profileEmoji = profileEmoji
        self.profileColor = profileColor
        self.profileImagePath = profileImagePath
        self.cloudProfileImageRecordName = cloudProfileImageRecordName
        self.profileImageModifiedAt = profileImageModifiedAt
    }

    /// Convert to domain model
    func toDomain() -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt,
            profileEmoji: profileEmoji,
            profileColor: profileColor,
            profileImageURL: profileImagePath.flatMap { URL(string: $0) },
            cloudProfileImageRecordName: cloudProfileImageRecordName,
            profileImageModifiedAt: profileImageModifiedAt
        )
    }

    /// Create from domain model
    static func from(_ user: User) -> UserModel {
        UserModel(
            id: user.id,
            username: user.username,
            displayName: user.displayName,
            email: user.email,
            cloudRecordName: user.cloudRecordName,
            createdAt: user.createdAt,
            profileEmoji: user.profileEmoji,
            profileColor: user.profileColor,
            profileImagePath: user.profileImageURL?.absoluteString,
            cloudProfileImageRecordName: user.cloudProfileImageRecordName,
            profileImageModifiedAt: user.profileImageModifiedAt
        )
    }
}
