import Foundation

/// Keeps public web publication behind a successful authoritative CloudKit
/// reconciliation so a stale device cannot republish deleted or private data.
nonisolated enum PublicWebRepairWorkflow {
    static func run(
        maxAttempts: Int = 3,
        sync: @Sendable () async throws -> Void,
        publish: @Sendable () async throws -> Void,
        waitBeforeRetry: @Sendable (Int) async throws -> Void = { attempt in
            try await Task.sleep(for: .seconds(attempt * 2))
        }
    ) async throws {
        precondition(maxAttempts > 0)
        var lastError: (any Error)?

        for attempt in 1...maxAttempts {
            do {
                try await sync()
                try Task.checkCancellation()
                try await publish()
                return
            } catch {
                lastError = error
                guard attempt < maxAttempts else { break }
                try Task.checkCancellation()
                try await waitBeforeRetry(attempt)
            }
        }

        throw lastError ?? CancellationError()
    }
}

nonisolated enum SharedContentAuthority {
    static func matches(pointerOwnerID: UUID?, recordOwnerID: UUID?) -> Bool {
        guard let pointerOwnerID, let recordOwnerID else { return false }
        return pointerOwnerID == recordOwnerID
    }
}
