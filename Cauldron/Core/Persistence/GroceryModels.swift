//
//  GroceryItemModel.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

// MARK: - Grouping Infrastructure

/// Types of grouping available for grocery items
enum GroceryGroupingType: String, CaseIterable {
    case recipe = "Recipe"
    case aisle = "Aisle"      // For future implementation
    case none = "None"         // Ungrouped view
}

/// Represents a group of grocery items
struct GroceryGroup: Identifiable {
    let id: String              // Group identifier (recipe ID, aisle name, etc.)
    let name: String            // Display name for the group
    var items: [GroceryItemDisplay]
    var isChecked: Bool         // True if all items in group are checked

    /// Check if all items in this group are checked
    var allItemsChecked: Bool {
        !items.isEmpty && items.allSatisfy { $0.isChecked }
    }

    /// Check if at least one item in this group is checked
    var someItemsChecked: Bool {
        items.contains { $0.isChecked }
    }
}

/// Display model for a grocery item (used in views)
struct GroceryItemDisplay: Identifiable {
    let id: UUID
    let name: String
    let quantity: Quantity?
    var isChecked: Bool
    let recipeID: String?
    let recipeName: String?
    let addedOrder: Int
}

/// SwiftData persistence model for Grocery items
@Model
final class GroceryItemModel {
    var id: UUID = UUID()
    var name: String = ""
    var quantityBlob: Data?
    var isChecked: Bool = false

    // Recipe association fields
    var recipeID: String?       // UUID string of the recipe this item came from
    var recipeName: String?     // Display name of the recipe
    var addedOrder: Int = 0     // Order in which items were added (for sorting)

    // Relationship to grocery list
    var list: GroceryListModel?

    init(
        id: UUID = UUID(),
        name: String,
        quantityBlob: Data? = nil,
        isChecked: Bool = false,
        recipeID: String? = nil,
        recipeName: String? = nil,
        addedOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.quantityBlob = quantityBlob
        self.isChecked = isChecked
        self.recipeID = recipeID
        self.recipeName = recipeName
        self.addedOrder = addedOrder
    }
    
    /// Create from name and optional quantity
    static func create(
        name: String,
        quantity: Quantity? = nil,
        recipeID: String? = nil,
        recipeName: String? = nil,
        addedOrder: Int = 0
    ) throws -> GroceryItemModel {
        let quantityData: Data?
        if let quantity = quantity {
            quantityData = try JSONEncoder().encode(quantity)
        } else {
            quantityData = nil
        }

        return GroceryItemModel(
            name: name,
            quantityBlob: quantityData,
            recipeID: recipeID,
            recipeName: recipeName,
            addedOrder: addedOrder
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

// MARK: - Grouping Helper Extensions

extension Array where Element == GroceryItemDisplay {
    /// Group items by recipe
    func groupByRecipe() -> [GroceryGroup] {
        var groups: [String: [GroceryItemDisplay]] = [:]

        for item in self {
            let key = item.recipeID ?? "other"
            groups[key, default: []].append(item)
        }

        return groups.map { key, items in
            // Sort items: unchecked first, then by addedOrder within each section
            let sortedItems = items.sorted { item1, item2 in
                // Unchecked items first
                if item1.isChecked != item2.isChecked {
                    return !item1.isChecked
                }
                // Within same checked state, sort by addedOrder
                return item1.addedOrder < item2.addedOrder
            }
            let name = items.first?.recipeName ?? "Other Items"
            let allChecked = !sortedItems.isEmpty && sortedItems.allSatisfy { $0.isChecked }

            return GroceryGroup(
                id: key,
                name: name,
                items: sortedItems,
                isChecked: allChecked
            )
        }.sorted { group1, group2 in
            // Fully checked groups go to bottom
            if group1.allItemsChecked != group2.allItemsChecked {
                return !group1.allItemsChecked
            }
            // "Other Items" group goes last within its checked state
            if group1.id == "other" { return false }
            if group2.id == "other" { return true }
            // Otherwise sort by name
            return group1.name < group2.name
        }
    }

    /// Sort items for ungrouped view (checked items go to bottom)
    func sortForUngroupedView() -> [GroceryItemDisplay] {
        self.sorted { item1, item2 in
            // Unchecked items first
            if item1.isChecked != item2.isChecked {
                return !item1.isChecked
            }
            // Within same checked state, sort by addedOrder
            return item1.addedOrder < item2.addedOrder
        }
    }
}

extension GroceryItemModel {
    /// Convert to display model
    func toDisplay() -> GroceryItemDisplay {
        let quantity = try? getQuantity()
        return GroceryItemDisplay(
            id: id,
            name: name,
            quantity: quantity,
            isChecked: isChecked,
            recipeID: recipeID,
            recipeName: recipeName,
            addedOrder: addedOrder
        )
    }
}
