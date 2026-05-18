//
//  RecipeRepository.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/2/25.
//

import Foundation
import SwiftData
import os
import CloudKit
import UIKit

/// Thread-safe repository for Recipe operations
actor RecipeRepository {
    internal let modelContainer: ModelContainer
    internal let cloudKitCore: CloudKitCore
    internal let recipeCloudService: RecipeCloudService
    internal let deletedRecipeRepository: DeletedRecipeRepository
    internal let collectionRepository: CollectionRepository?
    internal let imageManager: RecipeImageManager
    internal let imageSyncManager: ImageSyncManager
    internal let operationQueueService: OperationQueueService
    internal let externalShareService: ExternalShareService
    internal let logger = Logger(subsystem: "com.cauldron", category: "RecipeRepository")

    // Track recipes pending sync
    internal var pendingSyncRecipes = Set<UUID>()
    internal var syncRetryTask: Task<Void, Never>?
    internal var imageSyncRetryTask: Task<Void, Never>?
    internal var operationQueueReplayTask: Task<Void, Never>?

    // Track retry attempts for exponential backoff
    internal var imageRetryAttempts: [UUID: Int] = [:]

    init(
        modelContainer: ModelContainer,
        cloudKitCore: CloudKitCore,
        recipeCloudService: RecipeCloudService,
        deletedRecipeRepository: DeletedRecipeRepository,
        collectionRepository: CollectionRepository? = nil,
        imageManager: RecipeImageManager,
        imageSyncManager: ImageSyncManager,
        operationQueueService: OperationQueueService,
        externalShareService: ExternalShareService
    ) {
        self.modelContainer = modelContainer
        self.cloudKitCore = cloudKitCore
        self.recipeCloudService = recipeCloudService
        self.deletedRecipeRepository = deletedRecipeRepository
        self.collectionRepository = collectionRepository
        self.imageManager = imageManager
        self.imageSyncManager = imageSyncManager
        self.operationQueueService = operationQueueService
        self.externalShareService = externalShareService

        if !RuntimeEnvironment.isRunningTests && !RuntimeEnvironment.isSimulatorQAMode {
            // Start retry mechanism for failed syncs
            Task {
                await self.startSyncRetryTask()
                await self.startImageSyncRetryTask()
                await self.startOperationQueueReplayTask()
            }
        }
    }
}

enum RepositoryError: Error, LocalizedError, Equatable {
    case notFound
    case invalidData
    case saveFailed
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .invalidData:
            return "Invalid data format"
        case .saveFailed:
            return "Failed to save changes"
        case .notAuthorized:
            return "You can only delete recipes you own"
        }
    }
}
