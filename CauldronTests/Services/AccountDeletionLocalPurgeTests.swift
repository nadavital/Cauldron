import SwiftData
import UIKit
import XCTest
@testable import Cauldron

@MainActor
final class AccountDeletionLocalPurgeTests: XCTestCase {
    func testPurgeRemovesAccountModelsQueueAndImportInbox() async throws {
        let inboxDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cauldron-account-purge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inboxDirectory) }

        let inbox = RecipeImportInboxStore(directoryURL: inboxDirectory)
        let collectionImageManager = CollectionImageManagerV2(
            directoryName: "CollectionImages",
            baseDirectoryURL: inboxDirectory,
            removesDirectoryOnDeinit: true,
            cacheKeyGenerator: { ImageCache.collectionImageKey(collectionId: $0) }
        )
        let dependencies = DependencyContainer.preview(
            recipeImportInboxStore: inbox,
            collectionImageManager: collectionImageManager
        )
        let context = ModelContext(dependencies.modelContainer)
        let userID = UUID()
        let collectionID = UUID()

        context.insert(GroceryListModel(title: "Account groceries"))
        context.insert(CookingHistoryModel(recipeId: UUID(), recipeTitle: "Dinner"))
        context.insert(SavedRecipeReferenceModel(
            userId: userID,
            sourceRecipeId: UUID(),
            sourceRecipeName: "Shared recipe"
        ))
        context.insert(CollectionModel(
            id: collectionID,
            name: "Private photos",
            userId: userID,
            coverImageType: "custom"
        ))
        try context.save()

        let coverImage = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { renderer in
            UIColor.systemPurple.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        _ = try await collectionImageManager.saveImage(coverImage, collectionId: collectionID)

        await dependencies.operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID()
        )
        try await dependencies.operationQueueService.replaceDeadLetteredOperationsForTesting([
            DeadLetteredSyncOperation(
                operationId: UUID().uuidString,
                errorDescription: "previous account mutation",
                capturedAt: Date(),
                rawJSON: Data("private account payload".utf8)
            )
        ])
        _ = try await inbox.enqueue(source: .text("private family recipe"))

        let coverImageExistsBeforePurge = await collectionImageManager.imageExists(collectionId: collectionID)
        let deadLettersBeforePurge = await dependencies.operationQueueService.getDeadLetteredOperations()
        XCTAssertTrue(coverImageExistsBeforePurge)
        XCTAssertEqual(deadLettersBeforePurge.count, 1)

        try await dependencies.purgeAllLocalAccountData()

        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryListModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CookingHistoryModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedRecipeReferenceModel>()).isEmpty)
        let remainingOperations = await dependencies.operationQueueService.getAllOperations()
        let remainingDeadLetters = await dependencies.operationQueueService.getDeadLetteredOperations()
        let remainingInboxJobs = try await inbox.jobs()
        let coverImageExistsAfterPurge = await collectionImageManager.imageExists(collectionId: collectionID)
        XCTAssertTrue(remainingOperations.isEmpty)
        XCTAssertTrue(remainingDeadLetters.isEmpty)
        XCTAssertTrue(remainingInboxJobs.isEmpty)
        XCTAssertFalse(coverImageExistsAfterPurge)
    }
}
