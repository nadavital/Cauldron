import Foundation

nonisolated struct SyncHealthSnapshot: Sendable, Equatable {
    nonisolated enum Status: Sendable, Equatable {
        case upToDate
        case waiting
        case syncing
        case actionRequired
    }

    var status: Status
    var pendingCount: Int
    var failedCount: Int
    var deadLetterCount: Int
    var oldestPendingAge: TimeInterval?

    nonisolated static func make(
        operations: [SyncOperation],
        deadLetterCount: Int = 0,
        now: Date = Date()
    ) -> SyncHealthSnapshot {
        let active = operations.filter { $0.status != .completed }
        let failed = active.filter { $0.status == .failed }
        let failedCount = failed.count
        let status: Status
        if deadLetterCount > 0 {
            status = .actionRequired
        } else if active.contains(where: { $0.status == .inProgress }) {
            status = .syncing
        } else if !active.isEmpty {
            status = .waiting
        } else {
            status = .upToDate
        }
        let oldest = active.map(\.createdAt).min().map { max(0, now.timeIntervalSince($0)) }
        return SyncHealthSnapshot(
            status: status,
            pendingCount: active.count,
            failedCount: failedCount,
            deadLetterCount: deadLetterCount,
            oldestPendingAge: oldest
        )
    }
}
