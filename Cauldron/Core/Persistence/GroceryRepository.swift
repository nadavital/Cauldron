//
//  GroceryRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData

/// Main-actor repository for Grocery list operations. SwiftData mutations and
/// account-generation invalidation share this executor, so an authorized
/// intent commit cannot interleave with another repository mutation.
@MainActor
final class GroceryRepository {
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }
    
    // MARK: - List Operations

    /// Get or create the default unified grocery list
    func getOrCreateDefaultList() async throws -> UUID {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryListModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )

        let lists = try context.fetch(descriptor)
        if let firstList = lists.first {
            return firstList.id
        }

        // Create default list if none exists
        let list = GroceryListModel(title: "My Grocery List")
        context.insert(list)
        try context.save()
        return list.id
    }

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

    /// Add item to a grocery list with recipe metadata
    func addItem(
        listId: UUID,
        name: String,
        quantity: Quantity? = nil,
        recipeID: String? = nil,
        recipeName: String? = nil
    ) async throws {
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        // Get next addedOrder value
        let maxOrder = (list.items ?? []).map { $0.addedOrder }.max() ?? -1
        let nextOrder = maxOrder + 1

        let item = try GroceryItemModel.create(
            name: name,
            quantity: quantity,
            recipeID: recipeID,
            recipeName: recipeName,
            addedOrder: nextOrder
        )
        item.list = list
        context.insert(item)
        try context.save()
    }

    /// Add multiple items from a recipe to the default list
    func addItemsFromRecipe(
        recipeID: String,
        recipeName: String,
        items: [(name: String, quantity: Quantity?)]
    ) async throws {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        // Get next addedOrder value
        var currentOrder = (list.items ?? []).map { $0.addedOrder }.max() ?? -1

        for (name, quantity) in items {
            currentOrder += 1
            let item = try GroceryItemModel.create(
                name: name,
                quantity: quantity,
                recipeID: recipeID,
                recipeName: recipeName,
                addedOrder: currentOrder
            )
            item.list = list
            context.insert(item)
        }

        try context.save()
    }

    /// Reconciles a recipe's intended ingredient multiset with its grocery
    /// group, adding only missing normalized name-and-quantity entries. This
    /// keeps retries idempotent while restoring ingredients that were removed
    /// or added to the recipe since an earlier invocation.
    @discardableResult
    func addItemsFromRecipeIfAbsent(
        recipeID: String,
        recipeName: String,
        items: [(name: String, quantity: Quantity?)]
    ) async throws -> Int {
        try await addItemsFromRecipeIfAbsent(
            recipeID: recipeID,
            recipeName: recipeName,
            items: items,
            isAuthorizedToCommit: { true }
        ) ?? 0
    }

    /// Stages the complete idempotent recipe mutation in one ModelContext and
    /// commits only if the caller's account generation is still authorized.
    /// Returning nil guarantees that neither a new list nor any ingredients
    /// from the expired identity were persisted.
    func addItemsFromRecipeIfAbsent(
        recipeID: String,
        recipeName: String,
        items: [(name: String, quantity: Quantity?)],
        isAuthorizedToCommit: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> Int? {
        // Account invalidation is also MainActor-isolated. Keeping both
        // authorization checks and the save in this synchronous, repository-
        // isolated section makes the commit linearizable with account switches
        // and every other grocery mutation.
        guard isAuthorizedToCommit() else { return nil }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        let existingLists = try context.fetch(listDescriptor)
        let list: GroceryListModel
        let insertedList: Bool
        if let existingList = existingLists.first {
            list = existingList
            insertedList = false
        } else {
            list = GroceryListModel(title: "My Grocery List")
            context.insert(list)
            insertedList = true
        }
        var existingCounts: [RecipeIngredientFingerprint: Int] = [:]
        for model in (list.items ?? []) where model.recipeID == recipeID {
            let fingerprint = RecipeIngredientFingerprint(
                name: model.name,
                quantity: try model.getQuantity()
            )
            existingCounts[fingerprint, default: 0] += 1
        }

        var currentOrder = (list.items ?? []).map(\.addedOrder).max() ?? -1
        var addedCount = 0
        for item in items {
            let fingerprint = RecipeIngredientFingerprint(name: item.name, quantity: item.quantity)
            if let existingCount = existingCounts[fingerprint], existingCount > 0 {
                existingCounts[fingerprint] = existingCount - 1
                continue
            }
            currentOrder += 1
            let model = try GroceryItemModel.create(
                name: item.name,
                quantity: item.quantity,
                recipeID: recipeID,
                recipeName: recipeName,
                addedOrder: currentOrder
            )
            model.list = list
            context.insert(model)
            addedCount += 1
        }
        guard isAuthorizedToCommit() else { return nil }
        if insertedList || addedCount > 0 {
            try context.save()
        }
        return addedCount
    }

    private struct RecipeIngredientFingerprint: Hashable {
        let name: String
        let quantityValue: UInt64?
        let quantityUpperValue: UInt64?
        let quantityUnit: String?

        init(name: String, quantity: Quantity?) {
            self.name = name
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            self.quantityValue = quantity?.value.bitPattern
            self.quantityUpperValue = quantity?.upperValue?.bitPattern
            self.quantityUnit = quantity?.unit.rawValue
        }
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

    /// Fetch all items from the default list as display models
    func fetchAllItemsForDisplay() async throws -> [GroceryItemDisplay] {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        return (list.items ?? []).map { $0.toDisplay() }
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

    /// Check or uncheck all items in a recipe
    func setRecipeChecked(recipeID: String, isChecked: Bool) async throws {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        let recipeItems = (list.items ?? []).filter { $0.recipeID == recipeID }
        for item in recipeItems {
            item.isChecked = isChecked
        }

        try context.save()
    }

    /// Check or uncheck all items in an AI category
    func setCategoryChecked(category: String, isChecked: Bool) async throws {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        // Filter items by AI category
        let categoryItems = (list.items ?? []).filter { $0.aiCategory == category }
        for item in categoryItems {
            item.isChecked = isChecked
        }

        try context.save()
    }

    /// Check or uncheck all items
    func setAllItemsChecked(isChecked: Bool) async throws {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        for item in (list.items ?? []) {
            item.isChecked = isChecked
        }

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

    /// Deletes an exact set of grocery items in one SwiftData transaction.
    /// Validation happens before mutation so a stale ID cannot produce a
    /// partially committed bulk deletion.
    func deleteItems(ids: Set<UUID>) async throws {
        guard !ids.isEmpty else { return }

        let context = ModelContext(modelContainer)
        let models = try context.fetch(FetchDescriptor<GroceryItemModel>())
            .filter { ids.contains($0.id) }
        guard models.count == ids.count else {
            throw RepositoryError.notFound
        }

        for model in models {
            context.delete(model)
        }
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

    // MARK: - AI Categorization

    /// Update AI category for an item
    func updateCategory(itemId: UUID, category: String) async throws {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<GroceryItemModel>(
            predicate: #Predicate { $0.id == itemId }
        )

        guard let item = try context.fetch(descriptor).first else {
            throw RepositoryError.notFound
        }

        item.aiCategory = category
        try context.save()
    }

    /// Get all items without AI categories
    func fetchUncategorizedItems() async throws -> [(id: UUID, name: String)] {
        let listId = try await getOrCreateDefaultList()
        let context = ModelContext(modelContainer)
        let listDescriptor = FetchDescriptor<GroceryListModel>(
            predicate: #Predicate { $0.id == listId }
        )

        guard let list = try context.fetch(listDescriptor).first else {
            throw RepositoryError.notFound
        }

        return (list.items ?? [])
            .filter { $0.aiCategory == nil }
            .map { (id: $0.id, name: $0.name) }
    }
}
