//
//  CategoryInferrer.swift
//  Cauldron
//
//  Created on January 25, 2026.
//

import Foundation

/// Infers recipe categories/tags from recipe content
///
/// Uses multiple strategies:
/// - Title keyword analysis
/// - Ingredient analysis (vegan, vegetarian detection)
/// - Cooking method detection (baking, air fryer, etc.)
/// - Time-based categories (quick & easy)
struct CategoryInferrer {

    /// Infer tags from recipe content
    ///
    /// - Parameters:
    ///   - title: Recipe title
    ///   - ingredients: Recipe ingredients
    ///   - steps: Recipe cooking steps
    ///   - totalMinutes: Total cooking time in minutes
    /// - Returns: Array of inferred tags
    ///
    /// Examples:
    /// ```swift
    /// CategoryInferrer.inferCategories(
    ///     title: "Vegan Pad Thai",
    ///     ingredients: [...],
    ///     steps: [...],
    ///     totalMinutes: 25
    /// )
    /// // [Tag(name: "Vegan"), Tag(name: "Thai"), Tag(name: "Quick & Easy")]
    /// ```
    static func inferCategories(
        title: String,
        ingredients: [Ingredient],
        steps: [CookStep],
        totalMinutes: Int?
    ) -> [Tag] {
        var tags: [Tag] = []
        var addedCategories: Set<String> = []

        // Helper to add a tag only if not already added
        func addTag(_ category: RecipeCategory) {
            guard !addedCategories.contains(category.displayName) else { return }
            addedCategories.insert(category.displayName)
            tags.append(Tag(name: category.displayName))
        }

        // 1. Analyze title for categories
        let titleCategories = inferFromTitle(title)
        for category in titleCategories {
            addTag(category)
        }

        // 2. Analyze ingredients for dietary categories
        let dietaryCategories = inferDietaryFromIngredients(ingredients)
        for category in dietaryCategories {
            addTag(category)
        }

        // 3. Analyze steps for cooking method categories
        let methodCategories = inferFromCookingMethod(steps)
        for category in methodCategories {
            addTag(category)
        }

        // 4. Time-based categories
        if let minutes = totalMinutes, minutes <= 30 {
            addTag(.quickEasy)
        }

        // 5. Infer meal type from title if not already determined
        let mealTypeCategories = inferMealType(title: title, steps: steps)
        for category in mealTypeCategories {
            addTag(category)
        }

        return tags
    }

    /// Infer categories from recipe title
    private static func inferFromTitle(_ title: String) -> [RecipeCategory] {
        var categories: [RecipeCategory] = []
        let lowercased = title.lowercased()

        // Split title into words for matching
        let words = lowercased.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }

        // Check each word against RecipeCategory.match()
        for word in words {
            if let category = RecipeCategory.match(string: word) {
                categories.append(category)
            }
        }

        // Also check common phrases in title
        let phrases: [(pattern: String, category: RecipeCategory)] = [
            ("pad thai", .thai),
            ("stir fry", .asian),
            ("stir-fry", .asian),
            ("fried rice", .asian),
            ("curry", .indian),
            ("tikka masala", .indian),
            ("butter chicken", .indian),
            ("tacos", .mexican),
            ("burrito", .mexican),
            ("enchilada", .mexican),
            ("pasta", .italian),
            ("pizza", .italian),
            ("risotto", .italian),
            ("lasagna", .italian),
            ("sushi", .japanese),
            ("ramen", .japanese),
            ("teriyaki", .japanese),
            ("falafel", .middleEastern),
            ("hummus", .middleEastern),
            ("shakshuka", .middleEastern),
            ("brisket", .jewish),
            ("challah", .jewish),
            ("matzo", .jewish),
            ("kugel", .jewish),
            ("gyro", .greek),
            ("tzatziki", .greek),
            ("souvlaki", .greek),
            ("croissant", .french),
            ("quiche", .french),
            ("crème brûlée", .french),
            ("burger", .american),
            ("mac and cheese", .american),
            ("bbq", .american),
            ("air fryer", .airFryer),
            ("air-fryer", .airFryer),
            ("instant pot", .onePot),
            ("slow cooker", .onePot),
            ("one pot", .onePot),
            ("one-pot", .onePot),
            ("keto", .keto),
            ("low carb", .lowCarb),
            ("low-carb", .lowCarb),
            ("high protein", .highProtein),
            ("gluten free", .glutenFree),
            ("gluten-free", .glutenFree),
            ("vegan", .vegan),
            ("vegetarian", .vegetarian),
            ("healthy", .healthy),
            ("breakfast", .breakfast),
            ("brunch", .breakfast),
            ("lunch", .lunch),
            ("dinner", .dinner),
            ("dessert", .dessert),
            ("cake", .dessert),
            ("cookie", .dessert),
            ("brownie", .dessert),
            ("pie", .dessert),
            ("snack", .snack),
            ("appetizer", .appetizer),
            ("starter", .appetizer),
            ("side dish", .sideDish),
            ("salad", .sideDish),
            ("smoothie", .drink),
            ("cocktail", .drink),
            ("lemonade", .drink)
        ]

        for (pattern, category) in phrases {
            if lowercased.contains(pattern) && !categories.contains(category) {
                categories.append(category)
            }
        }

        return categories
    }

    /// Infer dietary categories from ingredients
    private static func inferDietaryFromIngredients(_ ingredients: [Ingredient]) -> [RecipeCategory] {
        var categories: [RecipeCategory] = []

        let ingredientNames = ingredients.map { $0.name.lowercased() }
        let allIngredientText = ingredientNames.joined(separator: " ")

        // Meat indicators
        let meatKeywords = [
            "chicken", "beef", "pork", "lamb", "turkey", "bacon", "ham",
            "sausage", "steak", "ground meat", "mince", "prosciutto",
            "salami", "pepperoni", "chorizo", "duck", "veal", "venison"
        ]

        // Seafood indicators
        let seafoodKeywords = [
            "fish", "salmon", "tuna", "shrimp", "prawn", "crab", "lobster",
            "cod", "halibut", "tilapia", "anchovy", "anchovies", "clam",
            "mussel", "oyster", "scallop", "squid", "calamari", "octopus"
        ]

        // Dairy indicators
        let dairyKeywords = [
            "milk", "cream", "cheese", "butter", "yogurt", "yoghurt",
            "sour cream", "cream cheese", "parmesan", "mozzarella",
            "cheddar", "ricotta", "feta", "brie", "gouda", "whey"
        ]

        // Egg indicators
        let eggKeywords = ["egg", "eggs", "yolk", "yolks", "egg white"]

        // Gluten indicators
        let glutenKeywords = [
            "flour", "bread", "pasta", "noodle", "wheat", "barley",
            "rye", "couscous", "cracker", "breadcrumb", "panko",
            "soy sauce"  // Often contains wheat
        ]

        // Check for ingredients
        let hasMeat = meatKeywords.contains { allIngredientText.contains($0) }
        let hasSeafood = seafoodKeywords.contains { allIngredientText.contains($0) }
        let hasDairy = dairyKeywords.contains { allIngredientText.contains($0) }
        let hasEggs = eggKeywords.contains { allIngredientText.contains($0) }
        let hasGluten = glutenKeywords.contains { allIngredientText.contains($0) }

        // Vegetarian: no meat or seafood
        if !hasMeat && !hasSeafood {
            categories.append(.vegetarian)

            // Vegan: vegetarian + no dairy + no eggs
            if !hasDairy && !hasEggs {
                categories.append(.vegan)
            }
        }

        // Gluten-free: no gluten-containing ingredients
        // Only add if we don't see obvious gluten ingredients
        // (Be conservative - don't falsely label as GF)
        if !hasGluten && !allIngredientText.contains("flour") {
            // Only suggest GF if there's positive evidence (e.g., uses rice flour, almond flour)
            let gfIndicators = ["almond flour", "coconut flour", "rice flour", "gluten-free", "gf "]
            if gfIndicators.contains(where: { allIngredientText.contains($0) }) {
                categories.append(.glutenFree)
            }
        }

        // High protein: lots of protein-rich ingredients
        let proteinKeywords = [
            "chicken", "beef", "pork", "fish", "salmon", "tuna", "shrimp",
            "egg", "tofu", "tempeh", "lentils", "beans", "chickpea",
            "greek yogurt", "cottage cheese", "protein"
        ]
        let proteinCount = proteinKeywords.filter { allIngredientText.contains($0) }.count
        if proteinCount >= 2 {
            categories.append(.highProtein)
        }

        return categories
    }

    /// Infer categories from cooking methods in steps
    private static func inferFromCookingMethod(_ steps: [CookStep]) -> [RecipeCategory] {
        var categories: [RecipeCategory] = []

        let allStepsText = steps.map { $0.text.lowercased() }.joined(separator: " ")

        // Baking detection
        let bakingKeywords = ["bake", "baking", "oven", "preheat", "degrees", "°f", "°c"]
        let bakingCount = bakingKeywords.filter { allStepsText.contains($0) }.count
        if bakingCount >= 2 {
            categories.append(.baking)
        }

        // Air fryer detection
        if allStepsText.contains("air fryer") || allStepsText.contains("air fry") ||
           allStepsText.contains("airfryer") {
            categories.append(.airFryer)
        }

        // One pot detection
        if allStepsText.contains("one pot") || allStepsText.contains("instant pot") ||
           allStepsText.contains("slow cooker") || allStepsText.contains("crockpot") ||
           allStepsText.contains("pressure cooker") {
            categories.append(.onePot)
        }

        return categories
    }

    /// Infer meal type from title and steps
    private static func inferMealType(title: String, steps: [CookStep]) -> [RecipeCategory] {
        var categories: [RecipeCategory] = []

        let lowercasedTitle = title.lowercased()
        let allText = lowercasedTitle + " " + steps.map { $0.text.lowercased() }.joined(separator: " ")

        // Breakfast indicators
        let breakfastKeywords = [
            "breakfast", "brunch", "pancake", "waffle", "omelet", "omelette",
            "scrambled egg", "french toast", "cereal", "oatmeal", "muffin",
            "morning", "bacon and egg"
        ]
        if breakfastKeywords.contains(where: { allText.contains($0) }) {
            categories.append(.breakfast)
        }

        // Dessert indicators (from steps)
        let dessertKeywords = [
            "dessert", "sweet", "sugar", "frosting", "icing", "chocolate chip",
            "whipped cream", "caramel", "vanilla extract", "brown sugar"
        ]
        let dessertCount = dessertKeywords.filter { allText.contains($0) }.count
        if dessertCount >= 2 && !categories.contains(.breakfast) {
            categories.append(.dessert)
        }

        return categories
    }
}
