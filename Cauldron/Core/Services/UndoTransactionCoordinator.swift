import Foundation
import Observation

@MainActor
@Observable
final class UndoTransactionCoordinator {
    struct VisibleTransaction: Identifiable, Equatable {
        let id: UUID
        let message: String
        let actionTitle: String
    }

    typealias Commit = @MainActor () async throws -> Void
    typealias Undo = @MainActor () -> Void
    typealias Failure = @MainActor (Error) -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct PendingTransaction {
        let visible: VisibleTransaction
        let commit: Commit
        let undo: Undo
        let onFailure: Failure
    }

    private(set) var visibleTransaction: VisibleTransaction?

    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var pending: PendingTransaction?
    @ObservationIgnored private var deadlineTask: Task<Void, Never>?

    init(sleep: @escaping Sleep = { duration in
        try await Task.sleep(for: duration)
    }) {
        self.sleep = sleep
    }

    // Required to prevent crashes in XCTest due to Swift bug #85221.
    nonisolated deinit {}

    /// Presents one undo opportunity. Replacing an existing transaction commits
    /// the older action first; it is never silently undone or discarded.
    func schedule(
        message: String,
        actionTitle: String = "Undo",
        duration: Duration = .seconds(5),
        commit: @escaping Commit,
        undo: @escaping Undo,
        onFailure: @escaping Failure
    ) async {
        await commitNow()

        let visible = VisibleTransaction(
            id: UUID(),
            message: message,
            actionTitle: actionTitle
        )
        pending = PendingTransaction(
            visible: visible,
            commit: commit,
            undo: undo,
            onFailure: onFailure
        )
        visibleTransaction = visible

        deadlineTask = Task { [weak self, sleep] in
            do {
                try await sleep(duration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.commitIfCurrent(id: visible.id)
        }
    }

    /// Cancels the pending commit and invokes its exact restoration closure.
    func undo() {
        guard let transaction = takePending() else { return }
        transaction.undo()
    }

    /// Immediately commits the visible transaction. Safe to call repeatedly.
    func commitNow() async {
        guard let transaction = takePending() else { return }
        await runCommit(transaction)
    }

    private func commitIfCurrent(id: UUID) async {
        guard pending?.visible.id == id,
              let transaction = takePending() else {
            return
        }
        await runCommit(transaction)
    }

    private func takePending() -> PendingTransaction? {
        guard let pending else { return nil }
        deadlineTask?.cancel()
        deadlineTask = nil
        self.pending = nil
        visibleTransaction = nil
        return pending
    }

    private func runCommit(_ transaction: PendingTransaction) async {
        do {
            try await transaction.commit()
        } catch {
            transaction.onFailure(error)
        }
    }
}
