//
//  Nutrition.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents nutritional information
struct Nutrition: Sendable, Hashable {
    let calories: Double?
    let protein: Double? // grams
    let fat: Double? // grams
    let carbohydrates: Double? // grams
    let fiber: Double? // grams
    let sugar: Double? // grams
    let sodium: Double? // milligrams

    private enum CodingKeys: String, CodingKey {
        case calories
        case protein
        case fat
        case carbohydrates
        case fiber
        case sugar
        case sodium
    }
    
    nonisolated init(
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
    
    nonisolated var hasData: Bool {
        calories != nil || protein != nil || fat != nil || carbohydrates != nil
    }
    
    /// Scale nutrition info by a factor
    nonisolated func scaled(by factor: Double) -> Nutrition {
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

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.calories = try container.decodeIfPresent(Double.self, forKey: .calories)
        self.protein = try container.decodeIfPresent(Double.self, forKey: .protein)
        self.fat = try container.decodeIfPresent(Double.self, forKey: .fat)
        self.carbohydrates = try container.decodeIfPresent(Double.self, forKey: .carbohydrates)
        self.fiber = try container.decodeIfPresent(Double.self, forKey: .fiber)
        self.sugar = try container.decodeIfPresent(Double.self, forKey: .sugar)
        self.sodium = try container.decodeIfPresent(Double.self, forKey: .sodium)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(protein, forKey: .protein)
        try container.encodeIfPresent(fat, forKey: .fat)
        try container.encodeIfPresent(carbohydrates, forKey: .carbohydrates)
        try container.encodeIfPresent(fiber, forKey: .fiber)
        try container.encodeIfPresent(sugar, forKey: .sugar)
        try container.encodeIfPresent(sodium, forKey: .sodium)
    }
}

extension Nutrition: Codable {}
