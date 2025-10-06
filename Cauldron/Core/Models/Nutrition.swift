//
//  Nutrition.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents nutritional information
struct Nutrition: Codable, Sendable, Hashable {
    let calories: Double?
    let protein: Double? // grams
    let fat: Double? // grams
    let carbohydrates: Double? // grams
    let fiber: Double? // grams
    let sugar: Double? // grams
    let sodium: Double? // milligrams
    
    init(
        calories: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbohydrates: Double? = nil,
        fiber: Double? = nil,
        sugar: Double? = nil,
        sodium: Double? = nil
    ) {
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbohydrates = carbohydrates
        self.fiber = fiber
        self.sugar = sugar
        self.sodium = sodium
    }
    
    var hasData: Bool {
        calories != nil || protein != nil || fat != nil || carbohydrates != nil
    }
    
    /// Scale nutrition info by a factor
    func scaled(by factor: Double) -> Nutrition {
        Nutrition(
            calories: calories.map { $0 * factor },
            protein: protein.map { $0 * factor },
            fat: fat.map { $0 * factor },
            carbohydrates: carbohydrates.map { $0 * factor },
            fiber: fiber.map { $0 * factor },
            sugar: sugar.map { $0 * factor },
            sodium: sodium.map { $0 * factor }
        )
    }
}
