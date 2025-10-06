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
    var createdAt: Date = Date()
    
    init(id: UUID, username: String, displayName: String, createdAt: Date) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.createdAt = createdAt
    }
    
    /// Convert to domain model
    func toDomain() -> User {
        User(
            id: id,
            username: username,
            displayName: displayName,
            createdAt: createdAt
        )
    }
    
    /// Create from domain model
    static func from(_ user: User) -> UserModel {
        UserModel(
            id: user.id,
            username: user.username,
            displayName: user.displayName,
            createdAt: user.createdAt
        )
    }
}
