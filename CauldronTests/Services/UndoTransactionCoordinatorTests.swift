import Foundation
import Testing
@testable import Cauldron

@MainActor
struct UndoTransactionCoordinatorTests {
    private func coordinator() -> UndoTransactionCoordinator {
        UndoTransactionCoordinator { _ in
            try await Task.sleep(for: .seconds(3_600))
        }
    }

    @Test func undoCancelsCommitAndRunsRestorationExactlyOnce() async {
        let coordinator = coordinator()
        var commitCount = 0
        var undoCount = 0

        await coordinator.schedule(
            message: "Removed",
            commit: { commitCount += 1 },
            undo: { undoCount += 1 },
            onFailure: { _ in }
        )

        coordinator.undo()
        coordinator.undo()
        await coordinator.commitNow()

        #expect(commitCount == 0)
        #expect(undoCount == 1)
        #expect(coordinator.visibleTransaction == nil)
    }

    @Test func commitIsIdempotent() async {
        let coordinator = coordinator()
        var commitCount = 0

        await coordinator.schedule(
            message: "Removed",
            commit: { commitCount += 1 },
            undo: {},
            onFailure: { _ in }
        )

        await coordinator.commitNow()
        await coordinator.commitNow()

        #expect(commitCount == 1)
        #expect(coordinator.visibleTransaction == nil)
    }

    @Test func replacementCommitsOlderTransactionBeforeShowingNewOne() async {
        let coordinator = coordinator()
        var events: [String] = []

        await coordinator.schedule(
            message: "First",
            commit: { events.append("first committed") },
            undo: { events.append("first undone") },
            onFailure: { _ in }
        )
        await coordinator.schedule(
            message: "Second",
            commit: { events.append("second committed") },
            undo: { events.append("second undone") },
            onFailure: { _ in }
        )

        #expect(events == ["first committed"])
        #expect(coordinator.visibleTransaction?.message == "Second")

        coordinator.undo()
        #expect(events == ["first committed", "second undone"])
    }

    @Test func commitFailureIsReportedOnceAndClearsVisibility() async {
        enum ExpectedError: Error { case failure }
        let coordinator = coordinator()
        var failureCount = 0

        await coordinator.schedule(
            message: "Removed",
            commit: { throw ExpectedError.failure },
            undo: {},
            onFailure: { _ in failureCount += 1 }
        )

        await coordinator.commitNow()
        await coordinator.commitNow()

        #expect(failureCount == 1)
        #expect(coordinator.visibleTransaction == nil)
    }
}
