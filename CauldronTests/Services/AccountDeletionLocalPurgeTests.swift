import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class AccountDeletionLocalPurgeTests: XCTestCase {
    func testPurgeRemovesAccountModelsQueueAndImportInbox() async throws {
        let inboxDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cauldron-account-purge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: inboxDirectory) }

        let inbox = RecipeImportInboxStore(directoryURL: inboxDirectory)
        let dependencies = DependencyContainer.preview(recipeImportInboxStore: inbox)
        let context = ModelContext(dependencies.modelContainer)
        let userID = UUID()

        context.insert(GroceryListModel(title: "Account groceries"))
        context.insert(CookingHistoryModel(recipeId: UUID(), recipeTitle: "Dinner"))
        context.insert(SavedRecipeReferenceModel(
            userId: userID,
            sourceRecipeId: UUID(),
            sourceRecipeName: "Shared recipe"
        ))
        try context.save()

        await dependencies.operationQueueService.addOperation(
            type: .update,
            entityType: .recipe,
            entityId: UUID()
        )
        _ = try await inbox.enqueue(source: .text("private family recipe"))

        try await dependencies.purgeAllLocalAccountData()

        XCTAssertTrue(try context.fetch(FetchDescriptor<GroceryListModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CookingHistoryModel>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SavedRecipeReferenceModel>()).isEmpty)
        let remainingOperations = await dependencies.operationQueueService.getAllOperations()
        let remainingInboxJobs = try await inbox.jobs()
        XCTAssertTrue(remainingOperations.isEmpty)
        XCTAssertTrue(remainingInboxJobs.isEmpty)
    }
}
