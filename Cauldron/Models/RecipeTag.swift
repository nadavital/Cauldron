import SwiftUI

// MARK: - Tag Categories
enum TagCategory: String, CaseIterable, Identifiable, Codable {
    var id: String { self.rawValue }
    case cuisine = "Cuisine"
    case dietary = "Dietary Needs"
    case mealType = "Meal Type"
    case cookingMethod = "Cooking Method"
    case occasion = "Occasion"
    case attributes = "Attributes" // e.g., kid-friendly, spicy
}

// MARK: - Recipe Tag Structure
struct RecipeTag: Identifiable, Hashable, Codable {
    let id: String // Unique identifier, e.g., "cuisine_italian"
    let name: String
    let iconName: String 
    let category: TagCategory
}

// MARK: - Available Tags
class AllRecipeTags {
    static let shared = AllRecipeTags()

    let allTags: [RecipeTag]
    let tagsByCategory: [TagCategory: [RecipeTag]]

    private init() {
        // Define all tags here
        let cuisineTags = [
            RecipeTag(id: "cuisine_italian", name: "Italian", iconName: "cuisine_italian", category: .cuisine),
            RecipeTag(id: "cuisine_mexican", name: "Mexican", iconName: "cuisine_mexican", category: .cuisine),
            RecipeTag(id: "cuisine_chinese", name: "Chinese", iconName: "cuisine_chinese", category: .cuisine),
            RecipeTag(id: "cuisine_indian", name: "Indian", iconName: "cuisine_indian", category: .cuisine),
            RecipeTag(id: "cuisine_american", name: "American", iconName: "cuisine_american", category: .cuisine),
            RecipeTag(id: "cuisine_mediterranean", name: "Mediterranean", iconName: "cuisine_mediterranean", category: .cuisine),
            RecipeTag(id: "cuisine_japanese", name: "Japanese", iconName: "cuisine_japanese", category: .cuisine),
            RecipeTag(id: "cuisine_thai", name: "Thai", iconName: "cuisine_thai", category: .cuisine),
            RecipeTag(id: "cuisine_french", name: "French", iconName: "cuisine_french", category: .cuisine),
        ]

        let dietaryTags = [
            RecipeTag(id: "dietary_vegan", name: "Vegan", iconName: "dietary_vegan", category: .dietary),
            RecipeTag(id: "dietary_vegetarian", name: "Vegetarian", iconName: "dietary_vegetarian", category: .dietary),
            RecipeTag(id: "dietary_gluten_free", name: "Gluten-Free", iconName: "dietary_gluten_free", category: .dietary),
            RecipeTag(id: "dietary_dairy_free", name: "Dairy-Free", iconName: "dietary_dairy_free", category: .dietary),
            RecipeTag(id: "dietary_low_carb", name: "Low Carb", iconName: "dietary_low_carb", category: .dietary),
            RecipeTag(id: "dietary_high_protein", name: "High Protein", iconName: "dietary_high_protein", category: .dietary),
        ]

        let mealTypeTags = [
            RecipeTag(id: "meal_breakfast", name: "Breakfast", iconName: "meal_breakfast", category: .mealType),
            RecipeTag(id: "meal_lunch", name: "Lunch", iconName: "meal_lunch", category: .mealType),
            RecipeTag(id: "meal_dinner", name: "Dinner", iconName: "meal_dinner", category: .mealType),
            RecipeTag(id: "meal_snack", name: "Snack", iconName: "meal_snack", category: .mealType),
            RecipeTag(id: "meal_dessert", name: "Dessert", iconName: "meal_dessert", category: .mealType),
            RecipeTag(id: "meal_drink", name: "Drink", iconName: "meal_drink", category: .mealType),
            RecipeTag(id: "meal_appetizer", name: "Appetizer", iconName: "meal_appetizer", category: .mealType),
            RecipeTag(id: "meal_side_dish", name: "Side Dish", iconName: "meal_side_dish", category: .mealType),
            RecipeTag(id: "meal_bread", name: "Bread", iconName: "meal_bread", category: .mealType),
        ]
        
        let cookingMethodTags = [
            RecipeTag(id: "method_baking", name: "Baking", iconName: "method_baking", category: .cookingMethod),
            RecipeTag(id: "method_grilling", name: "Grilling", iconName: "method_grilling", category: .cookingMethod),
            RecipeTag(id: "method_stovetop", name: "Stovetop", iconName: "method_stovetop", category: .cookingMethod),
            RecipeTag(id: "method_frying", name: "Frying", iconName: "method_frying", category: .cookingMethod),
            RecipeTag(id: "method_slow_cooking", name: "Slow Cooking", iconName: "method_slow_cooking", category: .cookingMethod),
            RecipeTag(id: "method_quick_easy", name: "Quick & Easy", iconName: "method_quick_easy", category: .cookingMethod),
        ]

        let occasionTags = [
            RecipeTag(id: "occasion_holiday", name: "Holiday", iconName: "occasion_holiday", category: .occasion),
            RecipeTag(id: "occasion_party", name: "Party", iconName: "occasion_party", category: .occasion),
            RecipeTag(id: "occasion_weeknight", name: "Weeknight", iconName: "occasion_weeknight", category: .occasion),
        ]

        let attributesTags = [
            RecipeTag(id: "attr_kid_friendly", name: "Kid-Friendly", iconName: "attr_kid_friendly", category: .attributes),
            RecipeTag(id: "attr_spicy", name: "Spicy", iconName: "attr_spicy", category: .attributes),
            RecipeTag(id: "attr_comfort_food", name: "Comfort Food", iconName: "attr_comfort_food", category: .attributes),
            RecipeTag(id: "attr_healthy", name: "Healthy", iconName: "attr_healthy", category: .attributes),
            RecipeTag(id: "attr_make_ahead", name: "Make-Ahead", iconName: "attr_make_ahead", category: .attributes),
            RecipeTag(id: "attr_beginner", name: "Beginner", iconName: "attr_beginner", category: .attributes)
        ]

        allTags = cuisineTags + dietaryTags + mealTypeTags + cookingMethodTags + occasionTags + attributesTags
        tagsByCategory = Dictionary(grouping: allTags, by: { $0.category })
    }

    // Helper to get a tag by its ID
    func getTag(byId id: String) -> RecipeTag? {
        return allTags.first(where: { $0.id == id })
    }
    
    // Helper to get tags by multiple IDs
    func getTags(byIds ids: Set<String>) -> [RecipeTag] {
        return allTags.filter { ids.contains($0.id) }
    }
}
