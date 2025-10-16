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

    init(id: UUID, username: String, displayName: String, email: String? = nil, cloudRecordName: String? = nil, createdAt: Date) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.email = email
        self.cloudRecordName = cloudRecordName
        self.createdAt = createdAt
    }
    
    /// Convert to domain model
    func toDomain() -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            email: email,
            cloudRecordName: cloudRecordName,
            createdAt: createdAt
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
            createdAt: user.createdAt
        )
    }
}
