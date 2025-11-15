//
//  TestModelContainer.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import Foundation
import SwiftData
@testable import Cauldron

/// Helper for creating in-memory ModelContainers for testing
struct TestModelContainer {

    /// Create an in-memory ModelContainer with all Cauldron models
    /// This container will not persist data between test runs
    static func create() throws -> ModelContainer {
        let schema = Schema([
            RecipeModel.self,
            CollectionModel.self,
            CollectionReferenceModel.self,
            DeletedRecipeModel.self,
            ConnectionModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self
        ])

        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            allowsSave: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }

    /// Create a minimal in-memory ModelContainer with only specific models
    /// Useful when you only need to test a subset of models
    static func create(with models: [any PersistentModel.Type]) throws -> ModelContainer {
        let schema = Schema(models)

        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: true,
            allowsSave: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
