//
//  GroceryRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// Thread-safe repository for Grocery list operations
actor GroceryRepository {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    // MARK: - List Operations
    
    /// Create a new grocery list
    func createList(title: String) async throws -> UUID {
        let context = ModelContext(modelContainer)
        let list = GroceryListModel(title: title)
        context.insert(list)
        try context.save()
        return list.id
    }
    
    /// Fetch all grocery lists
    func fetchAllLists() async throws -> [(id: UUID, title: String, createdAt: Date, itemCount: Int)] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryListModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        let lists = try context.fetch(descriptor)
        return lists.map { list in
            (id: list.id, title: list.title, createdAt: list.createdAt, itemCount: list.items?.count ?? 0)
        }
    }
    
    /// Delete a grocery list
    func deleteList(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let list = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        context.delete(list)
        try context.save()
    }
    
    // MARK: - Item Operations
    
    /// Add item to a grocery list
    func addItem(listId: UUID, name: String, quantity: Quantity? = nil) async throws {
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )
        
        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }
        
        let item = try GroceryItemModel.create(name: name, quantity: quantity)
        item.list = list
        context.insert(item)
        try context.save()
    }
    
    /// Fetch all items in a list
    func fetchItems(listId: UUID) async throws -> [(id: UUID, name: String, quantity: Quantity?, isChecked: Bool)] {
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )
        
        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }
        
        return try (list.items ?? []).map { item in
            (id: item.id, name: item.name, quantity: try item.getQuantity(), isChecked: item.isChecked)
        }
    }
    
    /// Toggle item checked state
    func toggleItem(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryItemModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let item = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        item.isChecked.toggle()
        try context.save()
    }
    
    /// Delete an item
    func deleteItem(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryItemModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let item = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        context.delete(item)
        try context.save()
    }
    
    /// Clear all checked items from a list
    func clearCheckedItems(listId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )
        
        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }
        
        let checkedItems = (list.items ?? []).filter { $0.isChecked }
        for item in checkedItems {
            context.delete(item)
        }
        try context.save()
    }
}
