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
    let createdAt: Date
    let profileEmoji: String?  // Emoji for profile avatar
    let profileColor: String?  // Hex color string for profile avatar

    init(
        id: UUID = UUID(),
        username: String,
        displayName: String,
        email: String? = nil,
        cloudRecordName: String? = nil,
        createdAt: Date = Date(),
        profileEmoji: String? = nil,
        profileColor: String? = nil
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
        self.profileEmoji = profileEmoji
        self.profileColor = profileColor
    }
}
