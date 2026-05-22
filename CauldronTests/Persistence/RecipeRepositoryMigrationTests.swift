//
//  RecipeRepositoryMigrationTests.swift
//  CauldronTests
//

import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class RecipeRepositoryMigrationTests: XCTestCase {
    private var modelContainer: ModelContainer!
    private var repository: RecipeRepository!

    override func setUp() async throws {
        try await super.setUp()

        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        modelContainer = try TestModelContainer.create()
        repository = makeRepository(modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "hasFixedCorruptedImageFilenames_v2")
        repository = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testMigrateRecipeOwnershipSetsCurrentUserForLegacyRecipesWithoutOwner() async throws {
        let currentUserId = UUID()
        let model = RecipeModel(
            title: "Legacy Recipe",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data()
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, currentUserId)
        XCTAssertNil(migrated.originalCreatorId)
    }

    func testMigrateRecipeOwnershipDoesNotClaimStandaloneRecipesOwnedBySomeoneElse() async throws {
        let currentUserId = UUID()
        let previousOwnerId = UUID()
        let existingCreatorId = UUID()
        let model = RecipeModel(
            title: "Legacy Saved Recipe",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            ownerId: previousOwnerId,
            cloudRecordName: "cached-public-record",
            originalCreatorId: existingCreatorId
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, previousOwnerId)
        XCTAssertEqual(migrated.originalCreatorId, existingCreatorId)
    }

    func testMigrateRecipeOwnershipDoesNotClaimWrongOwnerStandaloneRecipesWithoutCloudIdentity() async throws {
        let currentUserId = UUID()
        let previousOwnerId = UUID()
        let model = RecipeModel(
            title: "Legacy Local Recipe",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            ownerId: previousOwnerId
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, previousOwnerId)
        XCTAssertNil(migrated.originalCreatorId)
    }

    func testMigrateRecipeOwnershipClaimsLegacySavedCopiesAndPreservesAttribution() async throws {
        let currentUserId = UUID()
        let sourceOwnerId = UUID()
        let sourceRecipeId = UUID()
        let model = RecipeModel(
            title: "Legacy Saved Copy",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            ownerId: sourceOwnerId,
            originalRecipeId: sourceRecipeId,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            followsSourceUpdates: true
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, currentUserId)
        XCTAssertEqual(migrated.originalCreatorId, sourceOwnerId)
        XCTAssertEqual(migrated.originalRecipeId, sourceRecipeId)
        XCTAssertTrue(migrated.followsSourceUpdates)
    }

    func testMigrateRecipeOwnershipDoesNotClaimPreviewRecipes() async throws {
        let currentUserId = UUID()
        let previewOwnerId = UUID()
        let model = RecipeModel(
            title: "Community Preview",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            ownerId: previewOwnerId,
            isPreview: true
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, previewOwnerId)
        XCTAssertNil(migrated.originalCreatorId)
    }

    func testMigrateRecipeOwnershipRestoresPreviouslyClaimedPreviewOwner() async throws {
        let currentUserId = UUID()
        let previewOwnerId = UUID()
        let model = RecipeModel(
            title: "Claimed Community Preview",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            ownerId: currentUserId,
            originalCreatorId: previewOwnerId,
            isPreview: true
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.migrateRecipeOwnership(currentUserId: currentUserId)

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertEqual(migrated.ownerId, previewOwnerId)
        XCTAssertEqual(migrated.originalCreatorId, previewOwnerId)
    }

    func testPublicRecipeSearchMetadataMigrationAttemptedAfterFullBestEffortScan() {
        let completedWithFailures = PublicRecipeSearchMetadataBackfillSummary(
            scanned: 20,
            updated: 5,
            alreadyCurrent: 10,
            failed: 5,
            mayHaveMore: false
        )
        let incomplete = PublicRecipeSearchMetadataBackfillSummary(
            scanned: 1_000,
            updated: 900,
            alreadyCurrent: 100,
            failed: 0,
            mayHaveMore: true
        )

        XCTAssertTrue(RecipeRepository.shouldMarkPublicRecipeSearchMetadataMigrationAttempted(completedWithFailures))
        XCTAssertFalse(RecipeRepository.shouldMarkPublicRecipeSearchMetadataMigrationAttempted(incomplete))
    }

    func testFixCorruptedImageFilenamesClearsMissingLocalImageAndMarksMigrationComplete() async throws {
        let recipeId = UUID()
        let model = RecipeModel(
            id: recipeId,
            title: "Recipe With Corrupted Image Path",
            ingredientsBlob: Data(),
            stepsBlob: Data(),
            tagsBlob: Data(),
            imageURL: "\(recipeId.uuidString).cloudkit-version-suffix"
        )
        let context = ModelContext(modelContainer)
        context.insert(model)
        try context.save()

        try await repository.fixCorruptedImageFilenames()

        let migrated = try XCTUnwrap(context.fetch(FetchDescriptor<RecipeModel>()).first)
        XCTAssertNil(migrated.imageURL)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "hasFixedCorruptedImageFilenames_v2"))
    }

    private func makeRepository(modelContainer: ModelContainer) -> RecipeRepository {
        let cloudKitCore = CloudKitCore()
        let recipeCloudService = RecipeCloudService(core: cloudKitCore)
        let imageManager = RecipeImageManager(
            directoryName: "RecipeRepositoryMigrationTests-\(UUID().uuidString)",
            uploadToCloudWithDatabase: nil,
            downloadFromCloudWithDatabase: nil
        )

        return RecipeRepository(
            modelContainer: modelContainer,
            cloudKitCore: cloudKitCore,
            recipeCloudService: recipeCloudService,
            deletedRecipeRepository: DeletedRecipeRepository(modelContainer: modelContainer),
            imageManager: imageManager,
            imageSyncManager: ImageSyncManager(),
            operationQueueService: OperationQueueService(),
            externalShareService: ExternalShareService(imageManager: imageManager)
        )
    }
}
