import Foundation

/// Keeps public web publication behind a successful authoritative CloudKit
/// reconciliation so a stale device cannot republish deleted or private data.
nonisolated enum PublicWebRepairWorkflow {
    static func reconcileOnLaunch(
        ownerID: UUID,
        defaults: UserDefaults = .standard,
        maxAttempts: Int = 3,
        sync: @Sendable () async throws -> Void,
        publish: @Sendable () async throws -> Void,
        waitBeforeRetry: @Sendable (Int) async throws -> Void = { attempt in
            try await Task.sleep(for: .seconds(attempt * 2))
        }
    ) async throws {
        PublicWebRepairLaunchPolicy.prepareForReconciliation(
            ownerID: ownerID,
            defaults: defaults
        )

        try await run(
            maxAttempts: maxAttempts,
            sync: sync,
            publish: publish,
            waitBeforeRetry: waitBeforeRetry
        )
    }

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

/// Public web snapshots are derived state, so a prior successful launch must
/// never suppress reconciliation on a later launch. The legacy checkpoint is
/// removed as users encounter this policy so missing backend data can heal.
nonisolated enum PublicWebRepairLaunchPolicy {
    static func prepareForReconciliation(
        ownerID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(
            forKey: "hasRepairedPublicWebSnapshots_v1_\(ownerID.uuidString)"
        )
    }
}

nonisolated enum SharedContentAuthority {
    static func matches(pointerOwnerID: UUID?, recordOwnerID: UUID?) -> Bool {
        guard let pointerOwnerID, let recordOwnerID else { return false }
        return pointerOwnerID == recordOwnerID
    }
}
