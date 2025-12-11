//
//  Ingredient.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Represents an ingredient in a recipe
struct Ingredient: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let quantity: Quantity?
    let note: String?
    let section: String? // e.g. "Dough", "Filling"
    
    init(
        id: UUID = UUID(),
        name: String,
        quantity: Quantity? = nil,
        note: String? = nil,
        section: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.note = note
        self.section = section
    }
    
    var displayString: String {
        var result = ""
        if let quantity = quantity {
            result += "\(quantity.displayString) "
        }
        result += name
        if let note = note {
            result += " (\(note))"
        }
        return result
    }
    
    /// Scale the ingredient by a factor
    func scaled(by factor: Double) -> Ingredient {
        Ingredient(
            id: id,
            name: name,
            quantity: quantity?.scaled(by: factor),
            note: note,
            section: section
        )
    }
}
