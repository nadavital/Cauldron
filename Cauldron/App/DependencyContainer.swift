//
//  DependencyContainer.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

/// Dependency injection container
@MainActor
class DependencyContainer: ObservableObject {
    let modelContainer: ModelContainer
    
    // Repositories (actors - thread-safe)
    let recipeRepository: RecipeRepository
    let deletedRecipeRepository: DeletedRecipeRepository
    let pantryRepository: PantryRepository
    let groceryRepository: GroceryRepository
    let cookingHistoryRepository: CookingHistoryRepository
    let sharingRepository: SharingRepository
    let connectionRepository: ConnectionRepository
    
    // Services (actors - thread-safe)
    let unitsService: UnitsService
    let cookSessionManager: CookSessionManager
    let groceryService: GroceryService
    let recommender: Recommender
    let foundationModelsService: FoundationModelsService
    let sharingService: SharingService
    let cloudKitService: CloudKitService
    let recipeSyncService: RecipeSyncService

    // UI Services (MainActor)
    let timerManager: TimerManager

    // Parsers
    let htmlParser: HTMLRecipeParser
    let textParser: TextRecipeParser

    nonisolated init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // Initialize services that repositories depend on
        self.cloudKitService = CloudKitService()

        // Initialize repositories (now with CloudKit service)
        self.deletedRecipeRepository = DeletedRecipeRepository(modelContainer: modelContainer)
        self.recipeRepository = RecipeRepository(
            modelContainer: modelContainer,
            cloudKitService: cloudKitService,
            deletedRecipeRepository: deletedRecipeRepository
        )
        self.pantryRepository = PantryRepository(modelContainer: modelContainer)
        self.groceryRepository = GroceryRepository(modelContainer: modelContainer)
        self.cookingHistoryRepository = CookingHistoryRepository(modelContainer: modelContainer)
        self.sharingRepository = SharingRepository(modelContainer: modelContainer)
        self.connectionRepository = ConnectionRepository(modelContainer: modelContainer)

        // Initialize other services
        self.unitsService = UnitsService()
        self.cookSessionManager = CookSessionManager()
        self.foundationModelsService = FoundationModelsService()
        self.timerManager = TimerManager()

        self.groceryService = GroceryService(
            pantryRepo: pantryRepository,
            unitsService: unitsService
        )

        self.recommender = Recommender(
            pantryRepo: pantryRepository
        )

        self.sharingService = SharingService(
            sharingRepository: sharingRepository,
            recipeRepository: recipeRepository
        )

        self.recipeSyncService = RecipeSyncService(
            cloudKitService: cloudKitService,
            recipeRepository: recipeRepository,
            deletedRecipeRepository: deletedRecipeRepository
        )

        // Initialize parsers
        self.htmlParser = HTMLRecipeParser()
        self.textParser = TextRecipeParser()

        // Start periodic sync after initialization
        self.recipeSyncService.startPeriodicSync()
    }
    
    /// Create container with in-memory storage (for previews/testing)
    nonisolated static func preview() -> DependencyContainer {
        let schema = Schema([
            RecipeModel.self,
            DeletedRecipeModel.self,
            PantryItemModel.self,
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            ConnectionModel.self
        ])
        
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        
        return DependencyContainer(modelContainer: container)
    }
    
    /// Create container with persistent storage
    nonisolated static func persistent() throws -> DependencyContainer {
        let schema = Schema([
            RecipeModel.self,
            DeletedRecipeModel.self,
            PantryItemModel.self,
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            ConnectionModel.self
        ])

        // Ensure Application Support directory exists
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        // Use migration plan to allow automatic migration
        let config = ModelConfiguration(schema: schema, allowsSave: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return DependencyContainer(modelContainer: container)
        } catch {
            print("⚠️ Database migration failed: \(error.localizedDescription)")
            print("🗑️ Deleting old database and starting fresh...")

            // If migration fails, delete the old database and start fresh
            // NOTE: Database deletion on migration failure is temporary beta behavior.
            // TODO: Implement proper migration strategy before v1.0 production release.
            // Current approach will cause data loss when users upgrade between TestFlight builds.
            let storeURL = appSupportURL.appendingPathComponent("default.store")
            let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
            let walURL = appSupportURL.appendingPathComponent("default.store-wal")

            try? fileManager.removeItem(at: storeURL)
            try? fileManager.removeItem(at: shmURL)
            try? fileManager.removeItem(at: walURL)

            print("✅ Old database deleted, creating fresh database...")

            // Try again with fresh database
            let container = try ModelContainer(for: schema, configurations: [config])
            return DependencyContainer(modelContainer: container)
        }
    }
}

// MARK: - Environment Key

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer = {
        do {
            return try DependencyContainer.persistent()
        } catch {
            fatalError("""
                Failed to initialize DependencyContainer: \(error.localizedDescription)

                This is usually caused by database migration issues.
                The app will now attempt to recover by deleting the database.
                Please restart the app.
                """)
        }
    }()
}

extension EnvironmentValues {
    var dependencies: DependencyContainer {
        get { self[DependencyContainerKey.self] }
        set { self[DependencyContainerKey.self] = newValue }
    }
}

extension View {
    func dependencies(_ container: DependencyContainer) -> some View {
        environment(\.dependencies, container)
    }
}

