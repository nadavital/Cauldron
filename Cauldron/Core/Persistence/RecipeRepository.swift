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
    internal let cloudKitService: CloudKitService
    internal let deletedRecipeRepository: DeletedRecipeRepository
    internal let collectionRepository: CollectionRepository?
    internal let imageManager: ImageManager
    internal let imageSyncManager: ImageSyncManager
    internal let operationQueueService: OperationQueueService
    internal let externalShareService: ExternalShareService
    internal let logger = Logger(subsystem: "com.cauldron", category: "RecipeRepository")

    // Track recipes pending sync
    internal var pendingSyncRecipes = Set<UUID>()
    internal var syncRetryTask: Task<Void, Never>?
    internal var imageSyncRetryTask: Task<Void, Never>?

    // Track retry attempts for exponential backoff
    internal var imageRetryAttempts: [UUID: Int] = [:]

    init(
        modelContainer: ModelContainer,
        cloudKitService: CloudKitService,
        deletedRecipeRepository: DeletedRecipeRepository,
        collectionRepository: CollectionRepository? = nil,
        imageManager: ImageManager,
        imageSyncManager: ImageSyncManager,
        operationQueueService: OperationQueueService,
        externalShareService: ExternalShareService
    ) {
        self.modelContainer = modelContainer
        self.cloudKitService = cloudKitService
        self.deletedRecipeRepository = deletedRecipeRepository
        self.collectionRepository = collectionRepository
        self.imageManager = imageManager
        self.imageSyncManager = imageSyncManager
        self.operationQueueService = operationQueueService
        self.externalShareService = externalShareService

        // Start retry mechanism for failed syncs
        startSyncRetryTask()
        startImageSyncRetryTask()
    }
}

enum RepositoryError: Error, LocalizedError {
    case notFound
    case invalidData
    case saveFailed
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Item not found"
        case .invalidData:
            return "Invalid data format"
        case .saveFailed:
            return "Failed to save changes"
        }
    }
}
