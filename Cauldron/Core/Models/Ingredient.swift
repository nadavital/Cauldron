//
//  Ingredient.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents an ingredient in a recipe
struct Ingredient: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let quantity: Quantity?
    let additionalQuantities: [Quantity]
    let note: String?
    let section: String? // e.g. "Dough", "Filling"
    
    nonisolated init(
        id: UUID = UUID(),
        name: String,
        quantity: Quantity? = nil,
        additionalQuantities: [Quantity] = [],
        note: String? = nil,
        section: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.additionalQuantities = additionalQuantities
        self.note = note
        self.section = section
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case quantity
        case additionalQuantities
        case note
        case section
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.quantity = try container.decodeIfPresent(Quantity.self, forKey: .quantity)
        self.additionalQuantities = try container.decodeIfPresent([Quantity].self, forKey: .additionalQuantities) ?? []
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.section = try container.decodeIfPresent(String.self, forKey: .section)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(quantity, forKey: .quantity)
        if !additionalQuantities.isEmpty {
            try container.encode(additionalQuantities, forKey: .additionalQuantities)
        }
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(section, forKey: .section)
    }

    nonisolated var allQuantities: [Quantity] {
        var result: [Quantity] = []
        if let quantity {
            result.append(quantity)
        }
        result.append(contentsOf: additionalQuantities)
        return result
    }
    
    nonisolated var displayString: String {
        var result = ""
        let quantityText = allQuantities.map(\.displayString).joined(separator: " + ")
        if !quantityText.isEmpty {
            result += "\(quantityText) "
        }
        result += name
        if let note = note {
            result += " (\(note))"
        }
        return result
    }
    
    /// Scale the ingredient by a factor
    nonisolated func scaled(by factor: Double) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity?.scaled(by: factor),
            additionalQuantities: additionalQuantities.map { $0.scaled(by: factor) },
            note: note,
            section: section
        )
    }
}

extension Ingredient: Codable {}
