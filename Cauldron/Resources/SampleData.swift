//
//  SampleData.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import os

/// Sample recipes for demo and preview purposes
struct SampleData {
    
    static let pancakesRecipe = Recipe(
        title: "Classic Buttermilk Pancakes",
        ingredients: [
            Ingredient(name: "all-purpose flour", quantity: Quantity(value: 2, unit: .cup)),
            Ingredient(name: "sugar", quantity: Quantity(value: 2, unit: .tablespoon)),
            Ingredient(name: "baking powder", quantity: Quantity(value: 2, unit: .teaspoon)),
            Ingredient(name: "salt", quantity: Quantity(value: 0.5, unit: .teaspoon)),
            Ingredient(name: "buttermilk", quantity: Quantity(value: 2, unit: .cup)),
            Ingredient(name: "eggs", quantity: Quantity(value: 2, unit: .whole)),
            Ingredient(name: "butter, melted", quantity: Quantity(value: 4, unit: .tablespoon))
        ],
        steps: [
            CookStep(index: 0, text: "In a large bowl, whisk together flour, sugar, baking powder, and salt."),
            CookStep(index: 1, text: "In another bowl, whisk together buttermilk, eggs, and melted butter."),
            CookStep(index: 2, text: "Pour wet ingredients into dry ingredients and stir until just combined. Don't overmix - lumps are okay!"),
            CookStep(index: 3, text: "Heat a griddle or non-stick pan over medium heat. Lightly grease with butter.", timers: [TimerSpec(seconds: 30, label: "Preheat")]),
            CookStep(index: 4, text: "Pour 1/4 cup batter for each pancake. Cook until bubbles form on surface, about 2-3 minutes.", timers: [.minutes(2, label: "First side")]),
            CookStep(index: 5, text: "Flip and cook until golden brown on the other side, about 1-2 minutes.", timers: [.minutes(1, label: "Second side")]),
            CookStep(index: 6, text: "Serve hot with butter and maple syrup. Enjoy!")
        ],
        yields: "12 pancakes",
        totalMinutes: 20,
        tags: [Tag(name: "Breakfast"), Tag(name: "Easy"), Tag(name: "Vegetarian")],
        nutrition: Nutrition(calories: 180, protein: 6, fat: 7, carbohydrates: 24)
    )
    
    static let pastaRecipe = Recipe(
        title: "Simple Tomato Basil Pasta",
        ingredients: [
            Ingredient(name: "pasta", quantity: Quantity(value: 1, unit: .pound)),
            Ingredient(name: "olive oil", quantity: Quantity(value: 3, unit: .tablespoon)),
            Ingredient(name: "garlic cloves, minced", quantity: Quantity(value: 4, unit: .clove)),
            Ingredient(name: "canned crushed tomatoes", quantity: Quantity(value: 28, unit: .ounce)),
            Ingredient(name: "fresh basil leaves", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(name: "salt", quantity: Quantity(value: 1, unit: .teaspoon)),
            Ingredient(name: "black pepper", quantity: Quantity(value: 0.5, unit: .teaspoon)),
            Ingredient(name: "parmesan cheese, grated", quantity: Quantity(value: 0.5, unit: .cup), note: "optional")
        ],
        steps: [
            CookStep(index: 0, text: "Bring a large pot of salted water to a boil.", timers: [.minutes(5, label: "Water boiling")]),
            CookStep(index: 1, text: "Cook pasta according to package directions until al dente, about 10 minutes.", timers: [.minutes(10, label: "Pasta cooking")]),
            CookStep(index: 2, text: "Meanwhile, heat olive oil in a large skillet over medium heat."),
            CookStep(index: 3, text: "Add garlic and sauté until fragrant, about 1 minute.", timers: [TimerSpec(seconds: 60, label: "Garlic")]),
            CookStep(index: 4, text: "Add crushed tomatoes, salt, and pepper. Simmer for 10 minutes.", timers: [.minutes(10, label: "Simmer sauce")]),
            CookStep(index: 5, text: "Tear basil leaves and stir into sauce."),
            CookStep(index: 6, text: "Drain pasta and toss with sauce. Top with parmesan if desired."),
            CookStep(index: 7, text: "Serve immediately and enjoy!")
        ],
        yields: "4 servings",
        totalMinutes: 25,
        tags: [Tag(name: "Italian"), Tag(name: "Dinner"), Tag(name: "Vegetarian")],
        nutrition: Nutrition(calories: 420, protein: 14, fat: 12, carbohydrates: 68)
    )
    
    static let chickenRecipe = Recipe(
        title: "Herb Roasted Chicken",
        ingredients: [
            Ingredient(name: "whole chicken", quantity: Quantity(value: 1, unit: .whole), note: "4-5 lbs"),
            Ingredient(name: "olive oil", quantity: Quantity(value: 2, unit: .tablespoon)),
            Ingredient(name: "fresh rosemary", quantity: Quantity(value: 2, unit: .tablespoon)),
            Ingredient(name: "fresh thyme", quantity: Quantity(value: 2, unit: .tablespoon)),
            Ingredient(name: "garlic cloves", quantity: Quantity(value: 6, unit: .clove)),
            Ingredient(name: "lemon", quantity: Quantity(value: 1, unit: .whole)),
            Ingredient(name: "salt", quantity: Quantity(value: 2, unit: .teaspoon)),
            Ingredient(name: "black pepper", quantity: Quantity(value: 1, unit: .teaspoon))
        ],
        steps: [
            CookStep(index: 0, text: "Preheat oven to 425°F (220°C).", timers: [.minutes(10, label: "Oven preheat")]),
            CookStep(index: 1, text: "Pat chicken dry with paper towels. Place in roasting pan."),
            CookStep(index: 2, text: "Mix olive oil, herbs, salt, and pepper. Rub all over chicken, inside and out."),
            CookStep(index: 3, text: "Stuff cavity with lemon halves and garlic cloves."),
            CookStep(index: 4, text: "Roast for 60-75 minutes until internal temperature reaches 165°F.", timers: [.minutes(70, label: "Roasting")]),
            CookStep(index: 5, text: "Let rest for 10 minutes before carving.", timers: [.minutes(10, label: "Resting")]),
            CookStep(index: 6, text: "Carve and serve with your favorite sides.")
        ],
        yields: "6 servings",
        totalMinutes: 90,
        tags: [Tag(name: "Dinner"), Tag(name: "Roasted"), Tag(name: "Main Course")],
        nutrition: Nutrition(calories: 380, protein: 42, fat: 22, carbohydrates: 2)
    )
    
    static let allRecipes = [pancakesRecipe, pastaRecipe, chickenRecipe]
    
    /// Load sample recipes into a container (for demo purposes)
    static func loadSamples(into dependencies: DependencyContainer) async {
        do {
            for recipe in allRecipes {
                try await dependencies.recipeRepository.create(recipe)
            }

            AppLogger.general.info("Sample data loaded successfully")
        } catch {
            AppLogger.general.error("Failed to load sample data: \(error.localizedDescription)")
        }
    }
}
