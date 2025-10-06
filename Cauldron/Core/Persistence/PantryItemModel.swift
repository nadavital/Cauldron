//
//  PantryItemModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// SwiftData persistence model for Pantry items
@Model
final class PantryItemModel {
    var id: UUID = UUID()
    var name: String = ""
    var quantityBlob: Data?
    var updatedAt: Date = Date()
    
    init(
        id: UUID = UUID(),
        name: String,
        quantityBlob: Data? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.quantityBlob = quantityBlob
        self.updatedAt = updatedAt
    }
    
    /// Create from name and optional quantity
    static func create(name: String, quantity: Quantity? = nil) throws -> PantryItemModel {
        let quantityData: Data?
        if let quantity = quantity {
            quantityData = try JSONEncoder().encode(quantity)
        } else {
            quantityData = nil
        }
        
        return PantryItemModel(
            name: name,
            quantityBlob: quantityData
        )
    }
    
    /// Get the quantity if available
    func getQuantity() throws -> Quantity? {
        guard let data = quantityBlob else { return nil }
        return try JSONDecoder().decode(Quantity.self, from: data)
    }
}
