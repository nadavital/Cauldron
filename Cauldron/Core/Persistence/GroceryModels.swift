//
//  GroceryItemModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// SwiftData persistence model for Grocery items
@Model
final class GroceryItemModel {
    var id: UUID = UUID()
    var name: String = ""
    var quantityBlob: Data?
    var isChecked: Bool = false
    
    // Relationship to grocery list
    var list: GroceryListModel?
    
    init(
        id: UUID = UUID(),
        name: String,
        quantityBlob: Data? = nil,
        isChecked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.quantityBlob = quantityBlob
        self.isChecked = isChecked
    }
    
    /// Create from name and optional quantity
    static func create(name: String, quantity: Quantity? = nil) throws -> GroceryItemModel {
        let quantityData: Data?
        if let quantity = quantity {
            quantityData = try JSONEncoder().encode(quantity)
        } else {
            quantityData = nil
        }
        
        return GroceryItemModel(
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

/// SwiftData persistence model for Grocery lists
@Model
final class GroceryListModel {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    
    // Relationship to items (optional for CloudKit)
    @Relationship(deleteRule: .cascade, inverse: \GroceryItemModel.list)
    var items: [GroceryItemModel]?
    
    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        items: [GroceryItemModel] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.items = items
    }
}
