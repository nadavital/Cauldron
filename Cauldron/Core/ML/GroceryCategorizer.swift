//
//  GroceryCategorizer.swift
//  Cauldron
//
//  AI-powered grocery item categorization using Apple Intelligence
//

import Foundation
import FoundationModels

/// Service for categorizing grocery items using Apple Intelligence
actor GroceryCategorizer {
    private let foundationModelsService: FoundationModelsService

    /// Standard grocery store categories in typical shopping order
    enum GroceryCategory: String, CaseIterable {
        case produce = "Produce"
        case meatSeafood = "Meat & Seafood"
        case deli = "Deli"
        case dairy = "Dairy & Eggs"
        case cheese = "Cheese"
        case bakery = "Bakery"
        case frozen = "Frozen"
        case canned = "Canned & Jarred"
        case pasta = "Pasta & Grains"
        case baking = "Baking"
        case spices = "Spices & Seasonings"
        case condiments = "Condiments & Sauces"
        case oilsVinegars = "Oils & Vinegars"
        case international = "International"
        case beverages = "Beverages"
        case snacks = "Snacks"
        case breakfast = "Breakfast & Cereal"
        case healthBeauty = "Health & Beauty"
        case household = "Household & Cleaning"
        case petSupplies = "Pet Supplies"

        var displayName: String { rawValue }
    }

    init(foundationModelsService: FoundationModelsService) {
        self.foundationModelsService = foundationModelsService
    }

    /// Check if categorization is available
    var isAvailable: Bool {
        get async {
            await foundationModelsService.isAvailable
        }
    }

    /// Categorize a single grocery item using Apple Intelligence
    /// - Parameter itemName: Name of the grocery item
    /// - Returns: Category name, or nil if categorization failed
    func categorize(itemName: String) async throws -> String? {
        guard await isAvailable else {
            return nil
        }

        // Create a session for categorization
        let session = LanguageModelSession(
            instructions: {
                """
                Categorize grocery items into one of these categories:
                - Produce (fresh fruits, vegetables, fresh herbs, salad greens)
                - Meat & Seafood (fresh or packaged meat, poultry, fish, seafood)
                - Deli (deli meats, prepared foods, rotisserie chicken)
                - Dairy & Eggs (milk, yogurt, butter, cream, eggs)
                - Cheese (all types of cheese)
                - Bakery (bread, bagels, pastries, tortillas, rolls)
                - Frozen (frozen vegetables, frozen meals, ice cream, frozen pizza)
                - Canned & Jarred (canned vegetables, canned beans, pickles, olives, jams)
                - Pasta & Grains (pasta, rice, quinoa, couscous, noodles)
                - Baking (flour, sugar, baking powder, baking soda, chocolate chips, vanilla extract)
                - Spices & Seasonings (dried herbs, spices, salt, pepper, seasoning blends)
                - Condiments & Sauces (ketchup, mustard, mayo, hot sauce, soy sauce, salad dressing, barbecue sauce)
                - Oils & Vinegars (olive oil, vegetable oil, vinegar, cooking spray)
                - International (ethnic ingredients, specialty items from specific cuisines)
                - Beverages (drinks, coffee, tea, juice, soda, water)
                - Snacks (chips, crackers, cookies, candy, nuts, popcorn)
                - Breakfast & Cereal (cereal, oatmeal, granola, pancake mix, syrup)
                - Health & Beauty (vitamins, supplements, personal care items)
                - Household & Cleaning (cleaning supplies, paper towels, trash bags, detergent)
                - Pet Supplies (pet food, pet treats, pet care items)

                Respond with ONLY the category name, nothing else.
                """
            }
        )

        do {
            let result = try await session.respond(
                to: "Categorize this grocery item: \(itemName)",
                options: GenerationOptions(temperature: 0.1)
            )

            let category = result.content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate category is one of our known categories
            let validCategories = GroceryCategory.allCases.map { $0.displayName }
            if validCategories.contains(category) {
                return category
            }

            // If AI returned something unexpected, fall back to nil
            return nil
        } catch {
            // If categorization fails, return nil
            return nil
        }
    }

    /// Batch categorize multiple grocery items
    /// - Parameter items: Array of (itemId, itemName) tuples
    /// - Returns: Dictionary mapping item IDs to category names
    func categorizeItems(_ items: [(id: UUID, name: String)]) async throws -> [UUID: String] {
        guard await isAvailable else {
            return [:]
        }

        var results: [UUID: String] = [:]

        // Process items sequentially to avoid overwhelming the model
        for item in items {
            if let category = try await categorize(itemName: item.name) {
                results[item.id] = category
            }
        }

        return results
    }
}
