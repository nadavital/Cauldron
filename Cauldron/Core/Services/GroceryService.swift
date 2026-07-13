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
        var mergedItems: [String: [GroceryItem]] = [:]
        
        for list in lists {
            for item in list {
                let normalizedName = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                var bucket = mergedItems[normalizedName] ?? []
                var didMerge = false

                for index in bucket.indices {
                    let existing = bucket[index]
                    switch (existing.quantity, item.quantity) {
                    case (.none, .none):
                        didMerge = true
                    case (.some(let existingQuantity), .some(let incomingQuantity)):
                        if let converted = await unitsService.convert(
                            incomingQuantity,
                            to: existingQuantity.unit
                        ) {
                            bucket[index] = GroceryItem(
                                name: existing.name,
                                quantity: Quantity(
                                    value: existingQuantity.value + converted.value,
                                    upperValue: existingQuantity.upperValue == nil && converted.upperValue == nil
                                        ? nil
                                        : (existingQuantity.upperValue ?? existingQuantity.value)
                                            + (converted.upperValue ?? converted.value),
                                    unit: existingQuantity.unit
                                )
                            )
                            didMerge = true
                        }
                    default:
                        break
                    }
                    if didMerge { break }
                }

                // Never silently discard an incompatible or differently
                // specified quantity. Keep it as a separate attributed line.
                if !didMerge { bucket.append(item) }
                mergedItems[normalizedName] = bucket
            }
        }
        
        return mergedItems.values.flatMap { $0 }.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            if $0.name != $1.name { return $0.name < $1.name }
            let lhsUnit = $0.quantity?.unit.rawValue ?? ""
            let rhsUnit = $1.quantity?.unit.rawValue ?? ""
            if lhsUnit != rhsUnit { return lhsUnit < rhsUnit }
            let lhsValue = $0.quantity?.value ?? -.infinity
            let rhsValue = $1.quantity?.value ?? -.infinity
            return lhsValue < rhsValue
        }
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
