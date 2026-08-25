//
//  PendingOperation.swift
//  Cauldron
//
//  Created by Claude on 11/14/25.
//

import Foundation

nonisolated struct SyncOperationAccountScope: Equatable, Sendable {
    let ownerId: UUID
    let revision: UUID
    let cloudKitIdentity: String?

    init(ownerId: UUID, revision: UUID, cloudKitIdentity: String? = nil) {
        self.ownerId = ownerId
        self.revision = revision
        self.cloudKitIdentity = cloudKitIdentity
    }
}

nonisolated enum SyncOperationAccountDecision: Equatable, Sendable {
    case allowed
    case migrateLegacy
    case deferred
    case reject
}

/// Shared by live and replay paths so account-boundary policy is deterministic
/// and directly testable without invoking CloudKit.
nonisolated enum SyncOperationAccountPolicy {
    static func decision(
        operation: SyncOperation,
        entityOwnerId: UUID,
        currentScope: SyncOperationAccountScope?
    ) -> SyncOperationAccountDecision {
        guard let currentScope else { return .deferred }
        guard entityOwnerId == currentScope.ownerId else { return .deferred }
        if operation.ownerId == nil, operation.accountRevision == nil, operation.accountIdentity == nil {
            return .migrateLegacy
        }
        guard let queuedOwnerId = operation.ownerId,
              let queuedRevision = operation.accountRevision else {
            // A partially persisted account scope is malformed, not legacy.
            // Adopting it could authorize an operation across an account boundary.
            return .reject
        }
        guard queuedOwnerId == entityOwnerId else { return .reject }
        guard queuedOwnerId == currentScope.ownerId else { return .deferred }
        guard let queuedIdentity = operation.accountIdentity else {
            // Compatibility for operations produced by the immediately prior
            // scoped-queue format. They remain generation-bound and cannot be
            // resumed after switching away until rewritten by a new mutation.
            return queuedRevision == currentScope.revision ? .allowed : .deferred
        }
        guard let currentIdentity = currentScope.cloudKitIdentity else { return .deferred }
        guard queuedIdentity == currentIdentity else { return .deferred }
        guard queuedRevision == currentScope.revision else { return .migrateLegacy }
        return .allowed
    }
}

nonisolated enum QueuedMutationFreshnessPolicy {
    static func matchesPersistedMutation(
        persistedUpdatedAt: Date,
        persistedVisibility: RecipeVisibility,
        expectedUpdatedAt: Date,
        expectedVisibility: RecipeVisibility
    ) -> Bool {
        persistedUpdatedAt == expectedUpdatedAt && persistedVisibility == expectedVisibility
    }
}

/// Represents a type of sync operation that can be performed on an entity
nonisolated enum SyncOperationType: String, Codable, Sendable {
    case create
    case update
    case delete
    case acceptConnection
    case rejectConnection
}

/// Represents the type of entity being operated on
nonisolated enum EntityType: String, Codable, Sendable {
    case recipe
    case collection
    case savedRecipeReference
    case savedCollectionReference
    case groceryItem
    case userProfile
    case connection
}

/// Represents the status of a pending operation
nonisolated enum OperationStatus: String, Codable, Sendable {
    case pending      // Waiting to be processed
    case inProgress   // Currently being synced
    case failed       // Last attempt failed, will retry
    case completed    // Successfully synced
}

/// A pending sync operation that needs to be synced to CloudKit
nonisolated struct SyncOperation: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let type: SyncOperationType
    let entityType: EntityType
    let entityId: UUID
    let payload: Data?
    /// Account that authorized this durable mutation. `nil` is reserved for
    /// operations written by app versions that predate account-scoped queues.
    let ownerId: UUID?
    /// Durable identity generation captured when the operation was enqueued.
    /// It changes on sign-out or a CloudKit account-change notification, so an
    /// operation cannot become valid again after switching away and back.
    let accountRevision: UUID?
    /// Stable CloudKit account identifier captured with the durable owner.
    let accountIdentity: String?
    var status: OperationStatus
    var attempts: Int
    var lastAttemptDate: Date?
    var nextRetryDate: Date?
    var errorMessage: String?
    let createdAt: Date

    nonisolated init(
        id: UUID = UUID(),
        type: SyncOperationType,
        entityType: EntityType,
        entityId: UUID,
        payload: Data? = nil,
        ownerId: UUID? = nil,
        accountRevision: UUID? = nil,
        accountIdentity: String? = nil,
        status: OperationStatus = .pending,
        attempts: Int = 0,
        lastAttemptDate: Date? = nil,
        nextRetryDate: Date? = nil,
        errorMessage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.ownerId = ownerId
        self.accountRevision = accountRevision
        self.accountIdentity = accountIdentity
        self.status = status
        self.attempts = attempts
        self.lastAttemptDate = lastAttemptDate
        self.nextRetryDate = nextRetryDate
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    /// Returns a new operation with incremented attempt count and updated retry date
    nonisolated func withRetry(error: String? = nil) -> SyncOperation {
        let newAttempts = attempts + 1
        let backoffSeconds = calculateBackoff(attempts: newAttempts)

        return SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            ownerId: ownerId,
            accountRevision: accountRevision,
            accountIdentity: accountIdentity,
            status: .failed,
            attempts: newAttempts,
            lastAttemptDate: Date(),
            nextRetryDate: Date().addingTimeInterval(backoffSeconds),
            errorMessage: error,
            createdAt: createdAt
        )
    }

    /// Returns a new operation marked as in progress
    nonisolated func markInProgress() -> SyncOperation {
        SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            ownerId: ownerId,
            accountRevision: accountRevision,
            accountIdentity: accountIdentity,
            status: .inProgress,
            attempts: attempts,
            lastAttemptDate: Date(),
            nextRetryDate: nextRetryDate,
            errorMessage: errorMessage,
            createdAt: createdAt
        )
    }

    /// Returns a new operation marked as completed
    nonisolated func markCompleted() -> SyncOperation {
        SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            ownerId: ownerId,
            accountRevision: accountRevision,
            accountIdentity: accountIdentity,
            status: .completed,
            attempts: attempts,
            lastAttemptDate: Date(),
            nextRetryDate: nil,
            errorMessage: nil,
            createdAt: createdAt
        )
    }

    /// Calculate exponential backoff with jitter
    /// - Parameter attempts: Number of attempts made
    /// - Returns: Seconds to wait before next retry
    nonisolated private func calculateBackoff(attempts: Int) -> TimeInterval {
        // Exponential backoff: 2^attempts minutes, capped at 60 minutes
        let baseDelay: TimeInterval = 60 // 1 minute base
        let exponentialDelay = baseDelay * pow(2.0, Double(min(attempts, 6))) // Cap at 2^6 = 64 minutes
        let maxDelay: TimeInterval = 60 * 60 // 1 hour max
        let delay = min(exponentialDelay, maxDelay)

        // Add jitter (±20%) to prevent thundering herd
        let jitter = Double.random(in: 0.8...1.2)
        return delay * jitter
    }

    /// Whether this operation is ready to retry
    nonisolated var isReadyForRetry: Bool {
        guard status == .failed else { return false }
        guard let nextRetry = nextRetryDate else { return true }
        return Date() >= nextRetry
    }

    /// User-friendly description of the operation
    nonisolated var displayDescription: String {
        let action = type.displayName
        let entity = entityType.displayName
        return "\(action) \(entity)"
    }
}

// MARK: - Display Extensions

extension SyncOperationType {
    nonisolated var displayName: String {
        switch self {
        case .create: return "Creating"
        case .update: return "Updating"
        case .delete: return "Deleting"
        case .acceptConnection: return "Accepting"
        case .rejectConnection: return "Rejecting"
        }
    }
}

extension EntityType {
    nonisolated var displayName: String {
        switch self {
        case .recipe: return "recipe"
        case .collection: return "collection"
        case .savedRecipeReference: return "saved recipe"
        case .savedCollectionReference: return "saved collection"
        case .groceryItem: return "grocery item"
        case .userProfile: return "profile"
        case .connection: return "connection"
        }
    }
}

extension OperationStatus {
    nonisolated var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress: return "Syncing"
        case .failed: return "Failed"
        case .completed: return "Completed"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .inProgress: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.triangle"
        case .completed: return "checkmark.circle"
        }
    }
}
