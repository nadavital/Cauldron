//
//  TestFixtures.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import Foundation
@testable import Cauldron

enum TestFixtures {
    // MARK: - Sample Recipes

    static let sampleRecipe = Recipe(
        title: "Chocolate Chip Cookies",
        ingredients: [],
        steps: [],
        yields: "24 cookies",
        totalMinutes: 27,
        tags: [],
        nutrition: nil,
        sourceURL: nil,
        sourceTitle: nil,
        notes: "Classic homemade chocolate chip cookies with a crispy edge and soft center",
        imageURL: nil,
        isFavorite: false,
        visibility: .privateRecipe
    )

    static let sampleRecipeWithIngredients = Recipe(
        title: "Chocolate Chip Cookies",
        ingredients: [
            Ingredient(id: UUID(), name: "all-purpose flour", quantity: Quantity(value: 2.25, unit: .cup)),
            Ingredient(id: UUID(), name: "butter, softened", quantity: Quantity(value: 1, unit: .cup)),
            Ingredient(id: UUID(), name: "granulated sugar", quantity: Quantity(value: 0.75, unit: .cup)),
            Ingredient(id: UUID(), name: "brown sugar", quantity: Quantity(value: 0.75, unit: .cup)),
            Ingredient(id: UUID(), name: "large eggs", quantity: Quantity(value: 2, unit: .whole)),
            Ingredient(id: UUID(), name: "vanilla extract", quantity: Quantity(value: 2, unit: .teaspoon)),
            Ingredient(id: UUID(), name: "baking soda", quantity: Quantity(value: 1, unit: .teaspoon)),
            Ingredient(id: UUID(), name: "salt", quantity: Quantity(value: 0.5, unit: .teaspoon)),
            Ingredient(id: UUID(), name: "chocolate chips", quantity: Quantity(value: 2, unit: .cup))
        ],
        steps: [
            CookStep(id: UUID(), index: 0, text: "Preheat oven to 375°F (190°C).", timers: []),
            CookStep(id: UUID(), index: 1, text: "Mix butter and sugars until creamy.", timers: []),
            CookStep(id: UUID(), index: 2, text: "Beat in eggs and vanilla.", timers: []),
            CookStep(id: UUID(), index: 3, text: "In separate bowl, combine flour, baking soda, and salt.", timers: []),
            CookStep(id: UUID(), index: 4, text: "Gradually blend dry ingredients into butter mixture.", timers: []),
            CookStep(id: UUID(), index: 5, text: "Stir in chocolate chips.", timers: []),
            CookStep(id: UUID(), index: 6, text: "Drop rounded tablespoons onto ungreased cookie sheets.", timers: []),
            CookStep(id: UUID(), index: 7, text: "Bake for 9-11 minutes or until golden brown.", timers: [])
        ],
        yields: "24 cookies",
        totalMinutes: 27,
        tags: [],
        nutrition: nil,
        sourceURL: nil,
        sourceTitle: nil,
        notes: "Classic homemade cookies",
        imageURL: nil,
        isFavorite: false,
        visibility: .privateRecipe
    )

    // MARK: - Sample Users

    static let sampleUser1 = User(
        username: "alicebaker",
        displayName: "Alice Baker",
        email: "alice@example.com"
    )

    static let sampleUser2 = User(
        username: "bobchef",
        displayName: "Bob Chef",
        email: "bob@example.com"
    )

    // MARK: - Sample Collections

    static let sampleCollection = Collection(
        name: "Desserts",
        description: "My favorite dessert recipes",
        userId: UUID(),
        visibility: .privateRecipe
    )

    // MARK: - YouTube HTML Samples

    static let youtubeHTMLWithStructuredDescription = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Chocolate Chip Cookies Recipe - YouTube</title>
        <meta name="description" content="Learn how to make the best chocolate chip cookies!">
    </head>
    <body>
        <script>
        var ytInitialData = {
            "engagementPanels": [
                {
                    "engagementPanelSectionListRenderer": {
                        "content": {
                            "structuredDescriptionContentRenderer": {
                                "items": [
                                    {
                                        "videoDescriptionHeaderRenderer": {
                                            "title": {"runs": [{"text": "Ingredients:"}]}
                                        }
                                    },
                                    {
                                        "expandableVideoDescriptionBodyRenderer": {
                                            "descriptionBodyText": {
                                                "runs": [
                                                    {"text": "2 1/4 cups all-purpose flour\\n1 cup butter, softened\\n3/4 cup granulated sugar\\n3/4 cup brown sugar\\n2 large eggs\\n2 tsp vanilla extract\\n1 tsp baking soda\\n1/2 tsp salt\\n2 cups chocolate chips\\n\\nInstructions:\\n1. Preheat oven to 375°F\\n2. Mix butter and sugars until creamy\\n3. Beat in eggs and vanilla\\n4. Combine dry ingredients in separate bowl\\n5. Gradually blend into butter mixture\\n6. Stir in chocolate chips\\n7. Drop tablespoons onto cookie sheet\\n8. Bake 9-11 minutes\\n\\nBake for 9-11 minutes or until golden brown. Let cool on pan for 2 minutes before transferring."}
                                                ]
                                            }
                                        }
                                    }
                                ]
                            }
                        }
                    }
                }
            ]
        };
        </script>
    </body>
    </html>
    """

    static let youtubeHTMLWithMetaOnly = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Simple Recipe - YouTube</title>
        <meta name="description" content="Ingredients: 1/2 cup flour, 1 egg, 1 cup milk. Instructions: Mix all ingredients. Cook for 5 minutes.">
    </head>
    <body>
        <script>
        var ytInitialData = {};
        </script>
    </body>
    </html>
    """

    static let youtubeHTMLWithFractions = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="description" content="Test recipe with various fraction formats">
    </head>
    <body>
        <script>
        var ytInitialData = {
            "engagementPanels": [{
                "engagementPanelSectionListRenderer": {
                    "content": {
                        "structuredDescriptionContentRenderer": {
                            "items": [{
                                "expandableVideoDescriptionBodyRenderer": {
                                    "descriptionBodyText": {
                                        "runs": [{
                                            "text": "Ingredients:\\n½ cup flour\\n1/4 tsp salt\\n1 1/2 cups sugar\\n2/3 cup milk\\n1-2 eggs"
                                        }]
                                    }
                                }
                            }]
                        }
                    }
                }
            }]
        };
        </script>
    </body>
    </html>
    """

    static let youtubeHTMLWithTimers = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="description" content="Recipe with cooking timers">
    </head>
    <body>
        <script>
        var ytInitialData = {
            "engagementPanels": [{
                "engagementPanelSectionListRenderer": {
                    "content": {
                        "structuredDescriptionContentRenderer": {
                            "items": [{
                                "expandableVideoDescriptionBodyRenderer": {
                                    "descriptionBodyText": {
                                        "runs": [{
                                            "text": "Instructions:\\n1. Preheat oven for 10 minutes\\n2. Mix ingredients for 5 mins\\n3. Bake for 25-30 minutes\\n4. Let cool for 1 hour\\n5. Refrigerate overnight (8 hours)"
                                        }]
                                    }
                                }
                            }]
                        }
                    }
                }
            }]
        };
        </script>
    </body>
    </html>
    """

    // MARK: - Platform Detection URLs

    static let youtubeURLs = [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtube.com/watch?v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
        "https://www.youtube.com/shorts/abcd1234"
        // Note: URLs without protocol (e.g., "youtube.com/...") cannot be parsed and return .unknown
    ]

    static let tiktokURLs = [
        "https://www.tiktok.com/@user/video/1234567890",
        "https://vm.tiktok.com/abcd1234/",
        "https://tiktok.com/@user/video/1234567890"
    ]

    static let instagramURLs = [
        "https://www.instagram.com/reel/abcd1234/",
        "https://instagram.com/p/abcd1234/",
        "https://www.instagram.com/p/abcd1234/"
    ]

    // MARK: - Ingredient Parsing Test Cases

    static let ingredientTestCases: [(input: String, expected: (quantity: Double?, unit: String?, item: String))] = [
        // Standard format
        ("2 cups flour", (2.0, "cups", "flour")),
        ("1 cup butter", (1.0, "cup", "butter")),
        ("3 large eggs", (3.0, nil, "large eggs")),

        // Fractions
        ("1/2 cup sugar", (0.5, "cup", "sugar")),
        ("1/4 tsp salt", (0.25, "tsp", "salt")),
        ("1 1/2 cups milk", (1.5, "cups", "milk")),
        ("2 1/4 cups flour", (2.25, "cups", "flour")),

        // Unicode fractions
        ("½ cup water", (0.5, "cup", "water")),
        ("¼ tsp vanilla", (0.25, "tsp", "vanilla")),
        ("⅓ cup oil", (0.333, "cup", "oil")),
        ("¾ cup yogurt", (0.75, "cup", "yogurt")),

        // Ranges
        ("1-2 eggs", (1.0, nil, "eggs")),
        ("2-3 cups water", (2.0, "cups", "water")),

        // No quantity
        ("Salt to taste", (nil, nil, "Salt to taste")),
        ("Pinch of pepper", (nil, nil, "Pinch of pepper")),

        // Complex descriptions
        ("2 cups all-purpose flour, sifted", (2.0, "cups", "all-purpose flour, sifted")),
        ("1/2 cup butter, melted and cooled", (0.5, "cup", "butter, melted and cooled"))
    ]

    // MARK: - Timer Extraction Test Cases

    static let timerTestCases: [(input: String, expected: Int?)] = [
        ("Bake for 25 minutes", 1500),
        ("Cook for 1 hour", 3600),
        ("Let rest for 30 mins", 1800),
        ("Simmer for 45 min", 2700),
        ("Refrigerate for 2 hours", 7200),
        ("Wait 5 seconds", 5),
        ("Bake 20-25 minutes", 1200), // Should take minimum
        ("No timer here", nil)
    ]

    // MARK: - Unit Conversion Test Data

    static let unitConversions: [(from: String, to: String, value: Double, expected: Double)] = [
        // Volume
        ("cups", "ml", 1.0, 236.588),
        ("tbsp", "ml", 1.0, 14.787),
        ("tsp", "ml", 1.0, 4.929),
        ("ml", "cups", 236.588, 1.0),

        // Weight
        ("lbs", "g", 1.0, 453.592),
        ("oz", "g", 1.0, 28.35),

        // Temperature
        ("fahrenheit", "celsius", 375.0, 190.56),
        ("celsius", "fahrenheit", 180.0, 356.0)
    ]

    // MARK: - Scaling Test Data

    static let scalingTestCases: [(original: Double, factor: Double, expected: Double)] = [
        (2.0, 2.0, 4.0),
        (1.5, 2.0, 3.0),
        (0.5, 3.0, 1.5),
        (2.25, 0.5, 1.125),
        (1.0, 1.5, 1.5)
    ]
}
