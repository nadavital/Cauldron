//
//  CookingHistoryModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/3/25.
//

import Foundation
import SwiftData

/// SwiftData model for tracking cooking history
@Model
final class CookingHistoryModel {
    var id: UUID = UUID()
    var recipeId: UUID = UUID()
    var recipeTitle: String = ""
    var cookedAt: Date = Date()
    
    init(id: UUID = UUID(), recipeId: UUID, recipeTitle: String, cookedAt: Date = Date()) {
        self.id = id
        self.recipeId = recipeId
        self.recipeTitle = recipeTitle
        self.cookedAt = cookedAt
    }
}
