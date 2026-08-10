import Foundation
import Testing
@testable import Cauldron

@MainActor
struct GroceriesViewModelQoLTests {
    private enum ExpectedError: Error { case failure }

    private final class RepositoryItemsState {
        var items: [GroceryItemDisplay]

        init(_ items: [GroceryItemDisplay]) {
            self.items = items
        }
    }

    private final class SuspendedFirstLoad {
        private let repository: RepositoryItemsState
        private var firstContinuation: CheckedContinuation<[GroceryItemDisplay], Never>?
        private var firstSnapshot: [GroceryItemDisplay] = []
        private(set) var callCount = 0

        init(repository: RepositoryItemsState) {
            self.repository = repository
        }

        func load() async -> [GroceryItemDisplay] {
            callCount += 1
            guard callCount == 1 else { return repository.items }

            firstSnapshot = repository.items
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        func waitUntilSuspended() async {
            while firstContinuation == nil {
                await Task.yield()
            }
        }

        func resumeFirstLoad() {
            let continuation = firstContinuation
            firstContinuation = nil
            continuation?.resume(returning: firstSnapshot)
        }
    }

    private final class SuspendedLoadSequence {
        private let repository: RepositoryItemsState
        private let suspendedCallCount: Int
        private var continuations: [Int: CheckedContinuation<[GroceryItemDisplay], Never>] = [:]
        private var snapshots: [Int: [GroceryItemDisplay]] = [:]
        private(set) var callCount = 0

        init(repository: RepositoryItemsState, suspendedCallCount: Int) {
            self.repository = repository
            self.suspendedCallCount = suspendedCallCount
        }

        func load() async -> [GroceryItemDisplay] {
            callCount += 1
            let call = callCount
            guard call <= suspendedCallCount else { return repository.items }

            snapshots[call] = repository.items
            return await withCheckedContinuation { continuation in
                continuations[call] = continuation
            }
        }

        func waitUntilSuspended(call: Int) async {
            while continuations[call] == nil {
                await Task.yield()
            }
        }

        func resume(call: Int) {
            let continuation = continuations.removeValue(forKey: call)
            continuation?.resume(returning: snapshots.removeValue(forKey: call) ?? [])
        }

        func waitUntilCalled(_ expectedCount: Int) async {
            while callCount < expectedCount {
                await Task.yield()
            }
        }
    }

    private func coordinator() -> UndoTransactionCoordinator {
        UndoTransactionCoordinator { _ in
            try await Task.sleep(for: .seconds(3_600))
        }
    }

    private func item(
        id: UUID = UUID(),
        name: String,
        checked: Bool = false,
        recipeID: String? = nil,
        addedOrder: Int = 0,
        aiCategory: String? = nil
    ) -> GroceryItemDisplay {
        GroceryItemDisplay(
            id: id,
            name: name,
            quantity: nil,
            isChecked: checked,
            recipeID: recipeID,
            recipeName: recipeID == nil ? nil : "Recipe",
            addedOrder: addedOrder,
            aiCategory: aiCategory
        )
    }

    @Test func olderExplicitLoadCannotOverwriteNewerLoad() async {
        let first = item(name: "Salt")
        let newer = item(name: "Basil", addedOrder: 1)
        let repository = RepositoryItemsState([first])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )

        let olderLoad = Task { await viewModel.loadItems() }
        await suspendedLoad.waitUntilSuspended()
        repository.items = [first, newer]
        await viewModel.loadItems()
        suspendedLoad.resumeFirstLoad()
        await olderLoad.value

        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.map(\.id) == [first.id, newer.id])
    }

    @Test func loadRetriesAfterOverlappingToggleMutation() async {
        let first = item(name: "Salt")
        let repository = RepositoryItemsState([first])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in },
            toggleItemAction: { id in
                guard let index = repository.items.firstIndex(where: { $0.id == id }) else { return }
                repository.items[index].isChecked.toggle()
            },
            deleteItemsAction: { _ in }
        )
        viewModel.items = repository.items

        let load = Task { await viewModel.loadItems() }
        await suspendedLoad.waitUntilSuspended()
        await viewModel.toggleItem(id: first.id)
        suspendedLoad.resumeFirstLoad()
        await load.value

        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.first?.isChecked == true)
    }

    @Test func loadRetriesAfterOverlappingCategorizationMutation() async {
        let first = item(name: "Basil")
        let categorized = item(id: first.id, name: "Basil", aiCategory: "Produce")
        let repository = RepositoryItemsState([first])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )
        viewModel.items = repository.items

        let load = Task { await viewModel.loadItems() }
        await suspendedLoad.waitUntilSuspended()
        repository.items = [categorized]
        viewModel.applyCategorizationResults([first.id: "Produce"])
        suspendedLoad.resumeFirstLoad()
        await load.value

        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.first?.aiCategory == "Produce")
    }

    @Test func quickAddTrimsInputAndClearsAfterSuccess() async {
        var receivedNames: [String] = []
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { receivedNames.append($0) },
            deleteItemsAction: { _ in }
        )
        viewModel.inlineItemName = "  fresh basil \n"

        let added = await viewModel.addQuickItem()

        #expect(added)
        #expect(receivedNames == ["fresh basil"])
        #expect(viewModel.inlineItemName.isEmpty)
        #expect(viewModel.operationErrorMessage == nil)
    }

    @Test func quickAddRejectsWhitespaceWithoutCallingRepository() async {
        var callCount = 0
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in callCount += 1 },
            deleteItemsAction: { _ in }
        )
        viewModel.inlineItemName = " \n\t "

        let added = await viewModel.addQuickItem()

        #expect(!added)
        #expect(callCount == 0)
        #expect(viewModel.inlineItemName == " \n\t ")
    }

    @Test func quickAddFailurePreservesOriginalTextAndSurfacesError() async {
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in throw ExpectedError.failure },
            deleteItemsAction: { _ in }
        )
        viewModel.inlineItemName = "  milk  "

        let added = await viewModel.addQuickItem()

        #expect(!added)
        #expect(viewModel.inlineItemName == "  milk  ")
        #expect(viewModel.operationErrorMessage?.contains("milk") == true)
    }

    @Test func delayedDeleteUsesExactIDsAndUndoRestoresMetadataWithoutCommit() async {
        var committedIDs: [Set<UUID>] = []
        let first = item(name: "Salt", checked: true, recipeID: "recipe-1", addedOrder: 4)
        let second = item(name: "Pepper", addedOrder: 5)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in },
            deleteItemsAction: { committedIDs.append($0) }
        )
        viewModel.items = [first, second]
        viewModel.updateGroups(for: .recipe)

        await viewModel.requestDeleteItems(ids: [first.id, UUID()])
        #expect(viewModel.items.map(\.id) == [second.id])

        viewModel.undoCoordinator.undo()

        #expect(committedIDs.isEmpty)
        #expect(viewModel.items.map(\.id) == [first.id, second.id])
        #expect(viewModel.items.first?.recipeID == "recipe-1")
        #expect(viewModel.items.first?.addedOrder == 4)
    }

    @Test func clearCheckedCommitsOnlyCheckedExactSet() async {
        var committedIDs: Set<UUID> = []
        let first = item(name: "Salt", checked: true)
        let second = item(name: "Pepper", checked: false)
        let third = item(name: "Oil", checked: true)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in },
            deleteItemsAction: { committedIDs = $0 }
        )
        viewModel.items = [first, second, third]

        await viewModel.requestDeleteCheckedItems()
        #expect(viewModel.items.map(\.id) == [second.id])

        await viewModel.undoCoordinator.commitNow()

        #expect(committedIDs == [first.id, third.id])
    }

    @Test func commitFailureRestoresSnapshotAndSurfacesError() async {
        let first = item(name: "Salt")
        let second = item(name: "Pepper")
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in },
            deleteItemsAction: { _ in throw ExpectedError.failure }
        )
        viewModel.items = [first, second]

        await viewModel.requestDeleteItems(ids: [first.id])
        await viewModel.undoCoordinator.commitNow()

        #expect(viewModel.items.map(\.id) == [first.id, second.id])
        #expect(viewModel.operationErrorMessage != nil)
    }

    @Test func refreshDuringUndoWindowKeepsPendingItemsHidden() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let repository = RepositoryItemsState([first, second])
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { repository.items },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )
        viewModel.items = repository.items

        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items.append(item(name: "Oil", addedOrder: 3))
        await viewModel.loadItems()

        #expect(viewModel.items.map(\.id) == Array(repository.items.dropFirst()).map(\.id))
        #expect(!viewModel.items.contains { $0.id == first.id })
    }

    @Test func commitAfterRefreshKeepsDeletedItemsAbsentAndConcurrentItemsPresent() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let concurrent = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        var committedIDs: Set<UUID> = []
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { repository.items },
            addItemAction: { _ in },
            deleteItemsAction: { ids in
                committedIDs = ids
                repository.items.removeAll { ids.contains($0.id) }
            }
        )
        viewModel.items = repository.items

        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items.append(concurrent)
        await viewModel.loadItems()
        await viewModel.undoCoordinator.commitNow()

        #expect(committedIDs == [first.id])
        #expect(viewModel.items.map(\.id) == [second.id, concurrent.id])
    }

    @Test func undoAfterConcurrentRefreshMergesSnapshotWithoutReplacingNewItems() async {
        let first = item(name: "Salt", checked: true, recipeID: "recipe-1", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let concurrent = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { repository.items },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )
        viewModel.items = repository.items

        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items = [first, second, concurrent]
        await viewModel.loadItems()
        viewModel.undoCoordinator.undo()

        #expect(viewModel.items.map(\.id) == [first.id, second.id, concurrent.id])
        #expect(viewModel.items.first?.isChecked == true)
        #expect(viewModel.items.first?.recipeID == "recipe-1")
    }

    @Test func failedCommitMergesSnapshotWithConcurrentRefreshState() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let concurrent = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { repository.items },
            addItemAction: { _ in },
            deleteItemsAction: { _ in throw ExpectedError.failure }
        )
        viewModel.items = repository.items

        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items = [first, second, concurrent]
        await viewModel.loadItems()
        await viewModel.undoCoordinator.commitNow()

        #expect(viewModel.items.map(\.id) == [first.id, second.id, concurrent.id])
        #expect(viewModel.operationErrorMessage != nil)
    }

    @Test func quickAddLoadRetriesAfterOverlappingDeleteCommit() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let added = item(name: "Basil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in repository.items.append(added) },
            deleteItemsAction: { ids in repository.items.removeAll { ids.contains($0.id) } }
        )
        viewModel.items = repository.items
        await viewModel.requestDeleteItems(ids: [first.id])
        viewModel.inlineItemName = "Basil"

        let quickAdd = Task { await viewModel.addQuickItem() }
        await suspendedLoad.waitUntilSuspended()
        await viewModel.undoCoordinator.commitNow()
        suspendedLoad.resumeFirstLoad()

        let addedSuccessfully = await quickAdd.value
        #expect(addedSuccessfully)
        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.map(\.id) == [second.id, added.id])
    }

    @Test func loadRetriesAfterOverlappingUndoAndKeepsRemoteItem() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let remote = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )
        viewModel.items = repository.items
        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items.append(remote)

        let load = Task { await viewModel.loadItems() }
        await suspendedLoad.waitUntilSuspended()
        viewModel.undoCoordinator.undo()
        suspendedLoad.resumeFirstLoad()
        await load.value

        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.map(\.id) == [first.id, second.id, remote.id])
    }

    @Test func loadRetriesAfterOverlappingCommitFailureAndKeepsRemoteItem() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let remote = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second])
        let suspendedLoad = SuspendedFirstLoad(repository: repository)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoad.load() },
            addItemAction: { _ in },
            deleteItemsAction: { _ in throw ExpectedError.failure }
        )
        viewModel.items = repository.items
        await viewModel.requestDeleteItems(ids: [first.id])
        repository.items.append(remote)

        let load = Task { await viewModel.loadItems() }
        await suspendedLoad.waitUntilSuspended()
        await viewModel.undoCoordinator.commitNow()
        suspendedLoad.resumeFirstLoad()
        await load.value

        #expect(suspendedLoad.callCount == 2)
        #expect(viewModel.items.map(\.id) == [first.id, second.id, remote.id])
        #expect(viewModel.operationErrorMessage != nil)
    }

    @Test func exhaustedLoadBurstSchedulesOneBoundedDeferredReload() async {
        let first = item(name: "Salt", addedOrder: 1)
        let second = item(name: "Pepper", addedOrder: 2)
        let remote = item(name: "Oil", addedOrder: 3)
        let repository = RepositoryItemsState([first, second, remote])
        let suspendedLoads = SuspendedLoadSequence(repository: repository, suspendedCallCount: 3)
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            loadItemsAction: { await suspendedLoads.load() },
            addItemAction: { _ in },
            deleteItemsAction: { _ in }
        )
        viewModel.items = [first, second]

        let load = Task { await viewModel.loadItems() }
        await suspendedLoads.waitUntilSuspended(call: 1)
        await viewModel.requestDeleteItems(ids: [first.id])
        suspendedLoads.resume(call: 1)

        await suspendedLoads.waitUntilSuspended(call: 2)
        viewModel.undoCoordinator.undo()
        suspendedLoads.resume(call: 2)

        await suspendedLoads.waitUntilSuspended(call: 3)
        await viewModel.requestDeleteItems(ids: [first.id])
        suspendedLoads.resume(call: 3)
        await load.value

        await suspendedLoads.waitUntilCalled(4)
        while !viewModel.items.contains(where: { $0.id == remote.id }) {
            await Task.yield()
        }

        #expect(suspendedLoads.callCount == 4)
        #expect(viewModel.items.map(\.id) == [second.id, remote.id])
    }

    @Test func replacementCommitsFirstDeleteAndUndoRestoresOnlySecond() async {
        var commits: [Set<UUID>] = []
        let first = item(name: "Salt")
        let second = item(name: "Pepper")
        let third = item(name: "Oil")
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in },
            deleteItemsAction: { commits.append($0) }
        )
        viewModel.items = [first, second, third]

        await viewModel.requestDeleteItems(ids: [first.id])
        await viewModel.requestDeleteItems(ids: [second.id])

        #expect(commits == [[first.id]])
        #expect(viewModel.items.map(\.id) == [third.id])

        viewModel.undoCoordinator.undo()
        #expect(viewModel.items.map(\.id) == [second.id, third.id])
    }

    @Test func failedFirstReplacementCommitRestoresBeforeSecondSnapshot() async {
        var commitCount = 0
        let first = item(name: "Salt")
        let second = item(name: "Pepper")
        let third = item(name: "Oil")
        let viewModel = GroceriesViewModel(
            dependencies: .preview(),
            undoCoordinator: coordinator(),
            addItemAction: { _ in },
            deleteItemsAction: { _ in
                commitCount += 1
                if commitCount == 1 {
                    throw ExpectedError.failure
                }
            }
        )
        viewModel.items = [first, second, third]

        await viewModel.requestDeleteItems(ids: [first.id])
        await viewModel.requestDeleteItems(ids: [second.id])

        #expect(commitCount == 1)
        #expect(viewModel.items.map(\.id) == [first.id, third.id])
        #expect(viewModel.operationErrorMessage != nil)

        viewModel.undoCoordinator.undo()
        #expect(viewModel.items.map(\.id) == [first.id, second.id, third.id])
    }
}
