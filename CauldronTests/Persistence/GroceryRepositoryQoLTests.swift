import Foundation
import Testing
@testable import Cauldron

@MainActor
struct GroceryRepositoryQoLTests {
    @Test func bulkDeleteRemovesExactSetInOneRequest() async throws {
        let repository = GroceryRepository(modelContainer: try TestModelContainer.create())
        let listID = try await repository.getOrCreateDefaultList()
        try await repository.addItem(listId: listID, name: "Salt")
        try await repository.addItem(listId: listID, name: "Pepper")
        try await repository.addItem(listId: listID, name: "Oil")
        let items = try await repository.fetchAllItemsForDisplay()
        let deletedIDs = Set(items.filter { $0.name != "Pepper" }.map(\.id))

        try await repository.deleteItems(ids: deletedIDs)

        let remaining = try await repository.fetchAllItemsForDisplay()
        #expect(remaining.map(\.name) == ["Pepper"])
    }

    @Test func staleIDRejectsEntireBulkDeleteWithoutPartialMutation() async throws {
        let repository = GroceryRepository(modelContainer: try TestModelContainer.create())
        let listID = try await repository.getOrCreateDefaultList()
        try await repository.addItem(listId: listID, name: "Salt")
        try await repository.addItem(listId: listID, name: "Pepper")
        let before = try await repository.fetchAllItemsForDisplay()
        let requestedIDs = Set([try #require(before.first?.id), UUID()])

        await #expect(throws: RepositoryError.notFound) {
            try await repository.deleteItems(ids: requestedIDs)
        }

        let after = try await repository.fetchAllItemsForDisplay()
        #expect(Set(after.map(\.id)) == Set(before.map(\.id)))
    }
}
