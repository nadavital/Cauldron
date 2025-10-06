//
//  PantryRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// Thread-safe repository for Pantry operations
actor PantryRepository {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    /// Add item to pantry
    func add(name: String, quantity: Quantity? = nil) async throws {
        let context = ModelContext(modelContainer)
        let item = try PantryItemModel.create(name: name, quantity: quantity)
        context.insert(item)
        try context.save()
    }
    
    /// Fetch all pantry items
    func fetchAll() async throws -> [(id: UUID, name: String, quantity: Quantity?)] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PantryItemModel>(
            sortBy: [SortDescriptor(\.name)]
        )
        
        let models = try context.fetch(descriptor)
        return try models.map { model in
            (id: model.id, name: model.name, quantity: try model.getQuantity())
        }
    }
    
    /// Update pantry item
    func update(id: UUID, name: String, quantity: Quantity?) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PantryItemModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        model.name = name
        if let quantity = quantity {
            model.quantityBlob = try JSONEncoder().encode(quantity)
        } else {
            model.quantityBlob = nil
        }
        model.updatedAt = Date()
        
        try context.save()
    }
    
    /// Delete pantry item
    func delete(id: UUID) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PantryItemModel>(
            predicate: #Predicate { $0.id == id }
        )
        
        guard let model = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }
        
        context.delete(model)
        try context.save()
    }
    
    /// Check if an ingredient is in pantry (by name similarity)
    func contains(ingredientName: String) async throws -> Bool {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PantryItemModel>()
        let models = try context.fetch(descriptor)
        
        let normalizedName = ingredientName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return models.contains { model in
            model.name.lowercased().contains(normalizedName) ||
            normalizedName.contains(model.name.lowercased())
        }
    }
}
