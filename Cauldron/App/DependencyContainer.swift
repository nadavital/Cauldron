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
///
/// ## Architecture
/// Services are organized in layers:
/// 1. **Infrastructure Layer**: CloudKitCore, ModelContainer
/// 2. **Cloud Services Layer**: RecipeCloudService, UserCloudService, etc.
/// 3. **Local Persistence Layer**: RecipeRepository, CollectionRepository, etc.
/// 4. **Domain Services Layer**: RecipeSyncService, ConnectionManager, etc.
/// 5. **Feature Services Layer**: ImageManager, ProfileImageManager, etc.
@MainActor
class DependencyContainer: ObservableObject {
    let modelContainer: ModelContainer

    // MARK: - Layer 1: Infrastructure

    /// Core CloudKit infrastructure (shared by all cloud services)
    let cloudKitCore: CloudKitCore

    // MARK: - Layer 2: Cloud Services

    /// Recipe cloud operations (private database sync, public sharing)
    let recipeCloudService: RecipeCloudService

    /// User profile cloud operations
    let userCloudService: UserCloudService

    /// Collection cloud operations
    let collectionCloudService: CollectionCloudService

    /// Friend connection cloud operations
    let connectionCloudService: ConnectionCloudService

    /// Search cloud operations
    let searchCloudService: SearchCloudService


    // MARK: - Layer 3: Local Persistence (Repositories)

    let recipeRepository: RecipeRepository
    let deletedRecipeRepository: DeletedRecipeRepository
    let groceryRepository: GroceryRepository
    let cookingHistoryRepository: CookingHistoryRepository
    let sharingRepository: SharingRepository
    let connectionRepository: ConnectionRepository
    let collectionRepository: CollectionRepository

    // MARK: - Layer 4: Domain Services

    let unitsService: UnitsService
    let cookSessionManager: CookSessionManager
    let groceryService: GroceryService
    let foundationModelsService: FoundationModelsService
    let groceryCategorizer: GroceryCategorizer
    let recipeOCRService: RecipeOCRService
    let recipeLineClassificationService: RecipeLineClassificationService
    let sharingService: SharingService
    let externalShareService: ExternalShareService
    let recipeSyncService: RecipeSyncService
    let imageMigrationService: CloudImageMigration
    let imageSyncManager: ImageSyncManager
    let operationQueueService: OperationQueueService

    // MARK: - Layer 5: Feature Services

    /// Recipe image manager (unified implementation)
    let imageManager: RecipeImageManager
    /// Profile image manager (unified implementation)
    let profileImageManager: ProfileImageManagerV2
    /// Collection image manager (unified implementation)
    let collectionImageManager: CollectionImageManagerV2
    /// Shared loader for profile/collection image orchestration
    let entityImageLoader: EntityImageLoader
    let recipeImageService: RecipeImageService

    // UI Services (MainActor)
    let timerManager: TimerManager
    let profileCacheManager: ProfileCacheManager
    lazy var imageSyncViewModel: ImageSyncViewModel = ImageSyncViewModel(
        imageSyncManager: imageSyncManager,
        imageMigrationService: imageMigrationService
    )
    lazy var operationQueueViewModel: OperationQueueViewModel = OperationQueueViewModel(
        service: operationQueueService
    )
    lazy var cookModeCoordinator: CookModeCoordinator = CookModeCoordinator(dependencies: self)
    lazy var connectionManager: ConnectionManager = ConnectionManager(dependencies: self)

    // Parsers
    let htmlParser: HTMLRecipeParser
    let textParser: TextRecipeParser
    let youtubeParser: YouTubeRecipeParser
    let instagramParser: InstagramRecipeParser
    let tiktokParser: TikTokRecipeParser

    // Background task for image migration (retained to prevent premature cancellation)
    private var migrationTask: Task<Void, Never>?

    nonisolated init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        // ============================================================
        // LAYER 1: Infrastructure
        // ============================================================
        self.cloudKitCore = CloudKitCore()

        // ============================================================
        // LAYER 2: Cloud Services (depend on CloudKitCore)
        // ============================================================
        self.recipeCloudService = RecipeCloudService(core: cloudKitCore)
        self.userCloudService = UserCloudService(core: cloudKitCore)
        self.collectionCloudService = CollectionCloudService(core: cloudKitCore)
        self.connectionCloudService = ConnectionCloudService(core: cloudKitCore)
        self.searchCloudService = SearchCloudService(core: cloudKitCore)


        // Image managers using unified EntityImageManager with domain-specific services
        self.imageManager = createRecipeImageManager(recipeService: recipeCloudService)
        self.profileImageManager = createProfileImageManager(userService: userCloudService)
        self.collectionImageManager = createCollectionImageManager(collectionService: collectionCloudService)
        self.imageSyncManager = ImageSyncManager()
        self.operationQueueService = OperationQueueService()

        // ============================================================
        // LAYER 3: Local Persistence (Repositories)
        // ============================================================

        // Temporary references for MainActor-isolated services
        let tempImageManager = imageManager

        self.externalShareService = MainActor.assumeIsolated {
            ExternalShareService(imageManager: tempImageManager)
        }

        self.deletedRecipeRepository = DeletedRecipeRepository(modelContainer: modelContainer)
        self.collectionRepository = CollectionRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            collectionCloudService: collectionCloudService,
            operationQueueService: operationQueueService
        )
        self.recipeRepository = RecipeRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            deletedRecipeRepository: deletedRecipeRepository,
            collectionRepository: collectionRepository,
            imageManager: imageManager,
            imageSyncManager: imageSyncManager,
            operationQueueService: operationQueueService,
            externalShareService: externalShareService
        )
        self.groceryRepository = GroceryRepository(modelContainer: modelContainer)
        self.cookingHistoryRepository = CookingHistoryRepository(modelContainer: modelContainer)
        self.sharingRepository = SharingRepository(modelContainer: modelContainer)
        self.connectionRepository = ConnectionRepository(modelContainer: modelContainer)

        // ============================================================
        // LAYER 4: Domain Services
        // ============================================================
        self.unitsService = UnitsService()
        self.cookSessionManager = CookSessionManager()
        self.foundationModelsService = FoundationModelsService()
        self.groceryCategorizer = GroceryCategorizer(foundationModelsService: foundationModelsService)
        self.recipeOCRService = RecipeOCRService()
        self.recipeLineClassificationService = RecipeLineClassificationService()
        self.timerManager = TimerManager()
        self.profileCacheManager = ProfileCacheManager()

        self.groceryService = GroceryService(
            unitsService: unitsService
        )

        self.sharingService = SharingService(
            sharingRepository: sharingRepository,
            recipeRepository: recipeRepository,
            userCloudService: userCloudService,
            connectionCloudService: connectionCloudService,
            recipeCloudService: recipeCloudService
        )

        self.recipeSyncService = RecipeSyncService(
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            recipeRepository: recipeRepository,
            deletedRecipeRepository: deletedRecipeRepository,
            imageManager: imageManager
        )

        self.imageMigrationService = CloudImageMigration(
            recipeRepository: recipeRepository,
            imageManager: imageManager,
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            imageSyncManager: imageSyncManager
        )

        // ============================================================
        // LAYER 5: Feature Services
        // ============================================================

        // Parsers
        self.textParser = TextRecipeParser(lineClassifier: recipeLineClassificationService)
        self.htmlParser = HTMLRecipeParser(textParser: textParser)
        self.youtubeParser = YouTubeRecipeParser(
            foundationModelsService: foundationModelsService,
            textParser: textParser
        )
        self.instagramParser = InstagramRecipeParser(
            foundationModelsService: foundationModelsService,
            textParser: textParser
        )
        self.tiktokParser = TikTokRecipeParser(
            foundationModelsService: foundationModelsService,
            textParser: textParser
        )

        self.recipeImageService = MainActor.assumeIsolated {
            RecipeImageService(imageManager: tempImageManager)
        }
        self.entityImageLoader = MainActor.assumeIsolated {
            EntityImageLoader.shared
        }

        // Note: lazy properties (imageSyncViewModel, operationQueueViewModel,
        // cookModeCoordinator, connectionManager) are initialized on first access

        // Start periodic sync after initialization
        self.recipeSyncService.startPeriodicSync()

        // Start background image migration after a delay (runs only once)
        // Store the task to prevent premature cancellation.
        // Note: This Task intentionally captures `imageMigrationService` directly (not `self`)
        // to keep the service alive during migration without creating a reference cycle.
        // The Task is stored in `migrationTask` and cancelled in deinit for clean shutdown.
        self.migrationTask = Task { [imageMigrationService] in
            // Wait 10 seconds after app launch to avoid impacting startup
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await imageMigrationService.startMigration()
        }
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221
    nonisolated deinit {
        migrationTask?.cancel()
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
            CollectionModel.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fatalError("Failed to create preview ModelContainer - this indicates a schema configuration error")
        }

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
            CollectionModel.self
        ])

        // Ensure Application Support directory exists
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        if !fileManager.fileExists(atPath: appSupportURL.path) {
            try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
        }

        // SwiftData will handle automatic lightweight migrations for compatible schema changes
        // New optional fields (cloudImageRecordName, imageModifiedAt) will be automatically
        // migrated with nil values for existing records
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
