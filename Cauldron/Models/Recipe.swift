import SwiftUI

struct Recipe: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var ingredients: [Ingredient]
    var instructions: [String]
    var prepTime: Int // in minutes
    var cookTime: Int // in minutes
    var servings: Int
    var imageData: Data? // Stores the actual image data
    var tags: Set<String> // Stores RecipeTag IDs
    // Add more properties as needed, e.g., difficulty, cuisine
    
    static func == (lhs: Recipe, rhs: Recipe) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.ingredients == rhs.ingredients &&
        lhs.instructions == rhs.instructions &&
        lhs.prepTime == rhs.prepTime &&
        lhs.cookTime == rhs.cookTime &&
        lhs.servings == rhs.servings &&
        lhs.imageData == rhs.imageData &&
        lhs.tags == rhs.tags
    }
}

enum MeasurementUnit: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    // Volume units
    case cups = "cups"
    case tbsp = "tbsp"
    case tsp = "tsp"
    case ml = "ml"
    case liters = "L"
    
    // Weight units
    case grams = "g"
    case kg = "kg"
    case ounce = "oz"
    case pound = "lb"
    case mg = "mg"
    
    // Count units
    case pieces = "piece(s)"
    case pinch = "pinch"
    case dash = "dash"
    
    // Display name with proper pluralization
    func displayName(for quantity: Double) -> String {
        switch self {
        case .cups:
            return quantity == 1 ? "cup" : "cups"
        case .pieces:
            return quantity == 1 ? "piece" : "pieces"
        case .ounce:
            return quantity == 1 ? "oz" : "oz"
        case .pound:
            return quantity == 1 ? "lb" : "lbs"
        default:
            return self.rawValue
        }
    }
}

struct Ingredient: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var quantity: Double
    var unit: MeasurementUnit
    
    static func == (lhs: Ingredient, rhs: Ingredient) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.quantity == rhs.quantity &&
        lhs.unit == rhs.unit
    }
} 