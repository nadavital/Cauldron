//
//  DeletedRecipeModel.swift
//  Cauldron
//
//  Created by Claude on 10/14/25.
//

import Foundation
import SwiftData

/// Tracks recipes that have been deleted to prevent re-downloading from CloudKit
/// This is a "tombstone" record for sync conflict resolution
/// Note: All attributes are optional to support CloudKit integration
@Model
final class DeletedRecipeModel {
    // CloudKit requires all attributes to be optional or have default values
    // Unique constraint removed as CloudKit doesn't support it
    var recipeId: UUID?
    var deletedAt: Date?
    var cloudRecordName: String?

    init(recipeId: UUID, deletedAt: Date, cloudRecordName: String?) {
        self.recipeId = recipeId
        self.deletedAt = deletedAt
        self.cloudRecordName = cloudRecordName
    }
}
