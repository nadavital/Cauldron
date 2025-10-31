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
    let groceryRepository: GroceryRepository
    let cookingHistoryRepository: CookingHistoryRepository
    let sharingRepository: SharingRepository
    let connectionRepository: ConnectionRepository
    let collectionRepository: CollectionRepository
    
    // Services (actors - thread-safe)
    let unitsService: UnitsService
    let cookSessionManager: CookSessionManager
    let groceryService: GroceryService
    let recommender: Recommender
    let foundationModelsService: FoundationModelsService
    let sharingService: SharingService
    let cloudKitService: CloudKitService
    let recipeSyncService: RecipeSyncService
    let recipeReferenceManager: RecipeReferenceManager

    // UI Services (MainActor)
    let timerManager: TimerManager
    lazy var cookModeCoordinator: CookModeCoordinator = CookModeCoordinator(dependencies: self)
    lazy var connectionManager: ConnectionManager = ConnectionManager(dependencies: self)

    // Parsers
    let htmlParser: HTMLRecipeParser
    let textParser: TextRecipeParser

    nonisolated init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // Initialize services that repositories depend on
        self.cloudKitService = CloudKitService()

        // Initialize repositories (now with CloudKit service)
        self.deletedRecipeRepository = DeletedRecipeRepository(modelContainer: modelContainer)
        self.collectionRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitService: cloudKitService
        )
        self.recipeRepository = RecipeRepository(
            modelContainer: modelContainer,
            cloudKitService: cloudKitService,
            deletedRecipeRepository: deletedRecipeRepository,
            collectionRepository: collectionRepository
        )
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
            unitsService: unitsService
        )

        self.recommender = Recommender()

        self.sharingService = SharingService(
            sharingRepository: sharingRepository,
            recipeRepository: recipeRepository,
            cloudKitService: cloudKitService
        )

        self.recipeSyncService = RecipeSyncService(
            cloudKitService: cloudKitService,
            recipeRepository: recipeRepository,
            deletedRecipeRepository: deletedRecipeRepository
        )

        self.recipeReferenceManager = RecipeReferenceManager(
            cloudKitService: cloudKitService,
            recipeRepository: recipeRepository
        )

        // Initialize parsers
        self.htmlParser = HTMLRecipeParser()
        self.textParser = TextRecipeParser()

        // Note: cookModeCoordinator and connectionManager are lazy and will be initialized on first access

        // Start periodic sync after initialization
        self.recipeSyncService.startPeriodicSync()
    }
    
    /// Create container with in-memory storage (for previews/testing)
    nonisolated static func preview() -> DependencyContainer {
        let schema = Schema([
            RecipeModel.self,
            DeletedRecipeModel.self,
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            ConnectionModel.self,
            CollectionModel.self,
            CollectionReferenceModel.self
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
            GroceryListModel.self,
            GroceryItemModel.self,
            CookingHistoryModel.self,
            UserModel.self,
            SharedRecipeModel.self,
            ConnectionModel.self,
            CollectionModel.self,
            CollectionReferenceModel.self
        ])

        // Ensure Application Support directory exists
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        // SwiftData will handle automatic lightweight migrations for compatible schema changes
        let config = ModelConfiguration(schema: schema, allowsSave: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        return DependencyContainer(modelContainer: container)
    }
}

// MARK: - Environment Key

private struct DependencyContainerKey: EnvironmentKey {
    static let defaultValue: DependencyContainer = {
        do {
            return try DependencyContainer.persistent()
        } catch {
            fatalError("""
                Failed to initialize database: \(error.localizedDescription)

                This may indicate database corruption. Please try:
                1. Restart the app
                2. If the issue persists, reinstall the app

                Note: Your recipes are safely stored in iCloud and will be restored after reinstalling.
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

