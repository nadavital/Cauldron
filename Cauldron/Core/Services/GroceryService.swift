//
//  GroceryService.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation

/// Service for grocery list generation and management
actor GroceryService {
    private let unitsService: UnitsService

    init(unitsService: UnitsService) {
        self.unitsService = unitsService
    }

    /// Generate grocery list from recipe
    func generateGroceryList(from recipe: Recipe) async throws -> [GroceryItem] {
        var groceryItems: [GroceryItem] = []

        for ingredient in recipe.ingredients {
            groceryItems.append(GroceryItem(
                name: ingredient.name,
                quantity: ingredient.quantity
            ))
        }

        return groceryItems
    }
    
    /// Merge multiple grocery lists, deduping and combining quantities
    func mergeGroceryLists(_ lists: [[GroceryItem]]) async -> [GroceryItem] {
        var mergedItems: [String: GroceryItem] = [:]
        
        for list in lists {
            for item in list {
                let normalizedName = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let existing = mergedItems[normalizedName] {
                    // Try to combine quantities if same unit
                    if let existingQty = existing.quantity,
                       let newQty = item.quantity,
                       existingQty.unit == newQty.unit {
                        mergedItems[normalizedName] = GroceryItem(
                            name: existing.name,
                            quantity: Quantity(
                                value: existingQty.value + newQty.value,
                                unit: existingQty.unit
                            )
                        )
                    }
                    // Otherwise keep existing (could be improved with unit conversion)
                } else {
                    mergedItems[normalizedName] = item
                }
            }
        }
        
        return Array(mergedItems.values).sorted { $0.name < $1.name }
    }
    
    /// Generate shopping list text for export
    func exportToText(_ items: [GroceryItem]) -> String {
        items.map { item in
            if let quantity = item.quantity {
                return "☐ \(quantity.displayString) \(item.name)"
            } else {
                return "☐ \(item.name)"
            }
        }.joined(separator: "\n")
    }
}

struct GroceryItem {
    let name: String
    let quantity: Quantity?
}
