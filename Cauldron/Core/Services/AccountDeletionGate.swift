import Foundation

/// Process-wide generation boundary for account-scoped writers. Account
/// deletion begins this gate before taking its CloudKit inventory; suspended
/// creates and updates must reauthorize at their final publication boundary.
actor AccountDeletionGate {
    static let shared = AccountDeletionGate()

    @TaskLocal private static var authorizedDeletionLease: DeletionLease?

    struct PublicationLease: Sendable, Hashable {
        fileprivate let id: UUID
        fileprivate let ownerID: UUID
    }

    struct DeletionLease: Sendable, Hashable {
        fileprivate let id: UUID
        fileprivate let ownerID: UUID
    }

    private var deletionLeases: [UUID: Set<UUID>] = [:]
    private var activeLeases: [UUID: Set<UUID>] = [:]
    private var drainWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    func begin(ownerID: UUID) async -> DeletionLease {
        let lease = DeletionLease(id: UUID(), ownerID: ownerID)
        deletionLeases[ownerID, default: []].insert(lease.id)
        if !(activeLeases[ownerID]?.isEmpty ?? true) {
            await withCheckedContinuation { continuation in
                drainWaiters[ownerID, default: []].append(continuation)
            }
        }
        return lease
    }

    func end(_ lease: DeletionLease) {
        deletionLeases[lease.ownerID]?.remove(lease.id)
        if deletionLeases[lease.ownerID]?.isEmpty ?? true {
            deletionLeases.removeValue(forKey: lease.ownerID)
        }
    }

    func permitsWrite(ownerID: UUID?) -> Bool {
        guard let ownerID else { return false }
        if let authority = Self.authorizedDeletionLease,
           authority.ownerID == ownerID,
           deletionLeases[ownerID]?.contains(authority.id) == true {
            return true
        }
        return deletionLeases[ownerID]?.isEmpty ?? true
    }

    /// Runs the deleting account's own cleanup while admission remains closed
    /// to every unrelated task. Task-local authority follows structured child
    /// tasks but is not available to work that began before deletion.
    nonisolated static func withDeletionAuthority<T: Sendable>(
        _ lease: DeletionLease,
        operation: @escaping @Sendable () async throws -> T
    ) async rethrows -> T {
        try await $authorizedDeletionLease.withValue(lease, operation: operation)
    }

    /// Acquires authority across the full awaited publication. Deletion first
    /// closes admission, then waits for every already-issued lease to drain
    /// before taking its remote inventory.
    func acquirePublicationLease(ownerID: UUID?) -> PublicationLease? {
        guard let ownerID else { return nil }
        let hasDeletionAuthority = Self.authorizedDeletionLease.map {
            $0.ownerID == ownerID && deletionLeases[ownerID]?.contains($0.id) == true
        } ?? false
        guard hasDeletionAuthority || (deletionLeases[ownerID]?.isEmpty ?? true) else { return nil }
        let lease = PublicationLease(id: UUID(), ownerID: ownerID)
        activeLeases[ownerID, default: []].insert(lease.id)
        return lease
    }

    func releasePublicationLease(_ lease: PublicationLease) {
        activeLeases[lease.ownerID]?.remove(lease.id)
        guard activeLeases[lease.ownerID]?.isEmpty ?? true else { return }
        activeLeases.removeValue(forKey: lease.ownerID)
        let waiters = drainWaiters.removeValue(forKey: lease.ownerID) ?? []
        waiters.forEach { $0.resume() }
    }
}
