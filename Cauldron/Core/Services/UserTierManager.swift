//
//  UserTierManager.swift
//  Cauldron
//
//  Manages user tiers based on recipe count for profile badges and search boost
//

import Foundation
import SwiftUI
import Combine

/// User tier levels based on number of recipes added
enum UserTier: Int, CaseIterable, Comparable {
    case apprentice = 0      // 0-4 recipes
    case potionMaker = 5     // 5-14 recipes
    case spellCaster = 15    // 15-29 recipes
    case grandWizard = 30    // 30-49 recipes
    case legendarySorcerer = 50  // 50+ recipes

    var displayName: String {
        switch self {
        case .apprentice: return "Prep Cook"
        case .potionMaker: return "Line Cook"
        case .spellCaster: return "Sous Chef"
        case .grandWizard: return "Head Chef"
        case .legendarySorcerer: return "Master Chef"
        }
    }

    var icon: String {
        switch self {
        case .apprentice: return "leaf"
        case .potionMaker: return "fork.knife"
        case .spellCaster: return "flame"
        case .grandWizard: return "trophy"
        case .legendarySorcerer: return "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .apprentice: return Color(hex: "#8E8E93") ?? .gray         // Gray
        case .potionMaker: return Color(hex: "#CD7F32") ?? .orange      // Bronze
        case .spellCaster: return Color(hex: "#FF3B30") ?? .red         // Red
        case .grandWizard: return Color(hex: "#FFD700") ?? .yellow      // Gold
        case .legendarySorcerer: return Color(hex: "#AF52DE") ?? .purple // Purple
        }
    }

    /// Search result boost multiplier for this tier
    var searchBoost: Double {
        switch self {
        case .apprentice: return 1.0
        case .potionMaker: return 1.1
        case .spellCaster: return 1.25
        case .grandWizard: return 1.5
        case .legendarySorcerer: return 2.0
        }
    }

    /// Recipes required for this tier
    var requiredRecipes: Int {
        return self.rawValue
    }

    /// Next tier, or nil if at max
    var nextTier: UserTier? {
        switch self {
        case .apprentice: return .potionMaker
        case .potionMaker: return .spellCaster
        case .spellCaster: return .grandWizard
        case .grandWizard: return .legendarySorcerer
        case .legendarySorcerer: return nil
        }
    }

    static func tier(for recipeCount: Int) -> UserTier {
        if recipeCount >= UserTier.legendarySorcerer.rawValue {
            return .legendarySorcerer
        } else if recipeCount >= UserTier.grandWizard.rawValue {
            return .grandWizard
        } else if recipeCount >= UserTier.spellCaster.rawValue {
            return .spellCaster
        } else if recipeCount >= UserTier.potionMaker.rawValue {
            return .potionMaker
        } else {
            return .apprentice
        }
    }

    static func < (lhs: UserTier, rhs: UserTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Manages user tier calculation and caching
@MainActor
final class UserTierManager: ObservableObject {
    static let shared = UserTierManager()

    @Published private(set) var recipeCount: Int = 0
    @Published private(set) var currentTier: UserTier = .apprentice

    private init() {}

    /// Update the recipe count and recalculate tier
    func updateRecipeCount(_ count: Int) {
        recipeCount = count
        currentTier = UserTier.tier(for: count)
    }

    /// Recipes needed to reach the next tier
    var recipesToNextTier: Int? {
        guard let next = currentTier.nextTier else { return nil }
        return next.requiredRecipes - recipeCount
    }

    /// Progress towards next tier (0.0 to 1.0)
    var progress: Double {
        guard let next = currentTier.nextTier else { return 1.0 }
        let currentRequired = currentTier.requiredRecipes
        let nextRequired = next.requiredRecipes
        let range = nextRequired - currentRequired
        let progress = recipeCount - currentRequired
        return Double(progress) / Double(range)
    }
}
