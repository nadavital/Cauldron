//
//  RecipeCategory.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/5/25.
//

import SwiftUI

/// Represents a rich category for recipes (Cuisine, Meal Type, etc.)
/// These map to underlying tags but provide a richer UI experience.
enum RecipeCategory: String, CaseIterable, Identifiable, Sendable {
    // Meal Types
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
    case dessert = "Dessert"
    case snack = "Snack"
    case drink = "Drink"
    case appetizer = "Appetizer"
    case sideDish = "Side Dish"
    
    // Dietary
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case glutenFree = "Gluten-Free"
    case keto = "Keto"
    case paleo = "Paleo"
    case healthy = "Healthy"
    case lowCarb = "Low Carb"
    case highProtein = "High Protein"
    
    // Cuisines
    case italian = "Italian"
    case mexican = "Mexican"
    case asian = "Asian"
    case chinese = "Chinese"
    case japanese = "Japanese"
    case jewish = "Jewish"
    case thai = "Thai"
    case indian = "Indian"
    case greek = "Greek"
    case middleEastern = "Middle Eastern"
    case american = "American"
    case french = "French"
    
    // Other
    case quickEasy = "Quick & Easy"
    case comfortFood = "Comfort Food"
    case baking = "Baking"
    case onePot = "One Pot"
    case airFryer = "Air Fryer"
    case budgetFriendly = "Budget Friendly"
    
    var id: String { rawValue }
    
    var displayName: String { rawValue }
    
    var tagValue: String { rawValue }
    
    var emoji: String {
        switch self {
        case .breakfast: return "🍳"
        case .lunch: return "🥪"
        case .dinner: return "🍽️"
        case .dessert: return "🍰"
        case .snack: return "🍿"
        case .drink: return "🍹"
        case .appetizer: return "🥣"
        case .sideDish: return "🥗"
        
        case .vegetarian: return "🥕"
        case .vegan: return "🌱"
        case .glutenFree: return "🌾"
        case .keto: return "🥑"
        case .paleo: return "🍖"
        case .healthy: return "💪"
        case .lowCarb: return "🥬"
        case .highProtein: return "🍗"
        
        case .italian: return "🍝"
        case .mexican: return "🌮"
        case .asian: return "🥢"
        case .chinese: return "🥡"
        case .japanese: return "🍣"
        case .jewish: return "🥯"
        case .thai: return "🍜"
        case .indian: return "🍛"
        case .greek: return "🥙"
        case .middleEastern: return "🧆"
        case .american: return "🍔"
        case .french: return "🥐"
        
        case .quickEasy: return "⚡️"
        case .comfortFood: return "🍲"
        case .baking: return "🥧"
        case .onePot: return "🥘"
        case .airFryer: return "♨️"
        case .budgetFriendly: return "💰"
        }
    }
    
    var color: Color {
        switch self {
        case .breakfast: return Color.orange
        case .lunch: return Color.blue
        case .dinner: return Color.purple
        case .dessert: return Color.pink
        case .snack: return Color.yellow
        case .drink: return Color.indigo
        case .appetizer: return Color.orange
        case .sideDish: return Color.green
            
        case .vegetarian: return Color.green
        case .vegan: return Color(red: 0.4, green: 0.8, blue: 0.4)
        case .glutenFree: return Color.brown
        case .keto: return Color.red
        case .paleo: return Color.orange
        case .healthy: return Color.mint
        case .lowCarb: return Color.green
        case .highProtein: return Color.red
            
        case .italian: return Color(red: 0.8, green: 0.2, blue: 0.2)
        case .mexican: return Color(red: 0.9, green: 0.5, blue: 0.1)
        case .asian: return Color.red
        case .chinese: return Color.red
        case .japanese: return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .jewish: return Color.blue
        case .thai: return Color.green
        case .indian: return Color.orange
        case .greek: return Color.blue
        case .middleEastern: return Color.orange
        case .american: return Color.blue
        case .french: return Color.indigo
            
        case .quickEasy: return Color.yellow
        case .comfortFood: return Color.brown
        case .baking: return Color.pink
        case .onePot: return Color.orange
        case .airFryer: return Color.gray
        case .budgetFriendly: return Color.green
        }
    }
    
    enum Section: String, CaseIterable {
        case mealType = "Meal Type"
        case dietary = "Dietary"
        case cuisine = "Cuisine"
        case other = "Other"
    }
    
    var section: Section {
        switch self {
        case .breakfast, .lunch, .dinner, .dessert, .snack, .drink, .appetizer, .sideDish:
            return .mealType
        case .vegetarian, .vegan, .glutenFree, .keto, .paleo, .healthy, .lowCarb, .highProtein:
            return .dietary
        case .italian, .mexican, .asian, .chinese, .japanese, .jewish, .thai, .indian, .greek, .middleEastern, .american, .french:
            return .cuisine
        case .quickEasy, .comfortFood, .baking, .onePot, .airFryer, .budgetFriendly:
            return .other
        }
    }
    
    /// Try to match a raw string to a canonical category
    static func match(string: String) -> RecipeCategory? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Direct match
        if let match = RecipeCategory.allCases.first(where: { $0.displayName.lowercased() == normalized }) {
            return match
        }
        
        // Fuzzy/Alias matching
        switch normalized {
        case "veg", "veggie": return .vegetarian
        case "gf", "gluten-free": return .glutenFree
        case "low carb": return .lowCarb
        case "high protein": return .highProtein
        case "bbq", "barbecue": return .american
        case "airfryer", "air-fryer": return .airFryer
        case "one-pot", "onepot": return .onePot
        case "cheap", "budget": return .budgetFriendly
        case "fast", "quick", "easy": return .quickEasy
        case "bake", "baked": return .baking
        case "chinese food": return .chinese
        case "italian food": return .italian
        case "mexican food": return .mexican
        case "indian food": return .indian
        case "thai food": return .thai
        case "japanese food": return .japanese
        case "jewish food", "matzah", "bagel": return .jewish
        case "greek food": return .greek
        case "starter", "apps", "soup": return .appetizer
        case "side", "salad": return .sideDish
        default: return nil
        }
    }
    
    /// Helper string for AI prompt listing all available tags
    static var allTagsString: String {
        RecipeCategory.allCases.map { $0.displayName }.joined(separator: ", ")
    }
    
    static func all(in section: Section) -> [RecipeCategory] {
        allCases.filter { $0.section == section }
    }
}
