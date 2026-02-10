//
//  PendingOperation.swift
//  Cauldron
//
//  Created by Claude on 11/14/25.
//

import Foundation

/// Represents a type of sync operation that can be performed on an entity
enum SyncOperationType: String, Codable {
    case create
    case update
    case delete
    case acceptConnection
    case rejectConnection
}

/// Represents the type of entity being operated on
enum EntityType: String, Codable {
    case recipe
    case collection
    case groceryItem
    case userProfile
    case connection
}

/// Represents the status of a pending operation
enum OperationStatus: String, Codable {
    case pending      // Waiting to be processed
    case inProgress   // Currently being synced
    case failed       // Last attempt failed, will retry
    case completed    // Successfully synced
}

/// A pending sync operation that needs to be synced to CloudKit
struct SyncOperation: Codable, Identifiable, Equatable {
    let id: UUID
    let type: SyncOperationType
    let entityType: EntityType
    let entityId: UUID
    let payload: Data?
    var status: OperationStatus
    var attempts: Int
    var lastAttemptDate: Date?
    var nextRetryDate: Date?
    var errorMessage: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        entityType: EntityType,
        entityId: UUID,
        payload: Data? = nil,
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
        self.status = status
        self.attempts = attempts
        self.lastAttemptDate = lastAttemptDate
        self.nextRetryDate = nextRetryDate
        self.errorMessage = errorMessage
        self.createdAt = createdAt
    }

    /// Returns a new operation with incremented attempt count and updated retry date
    func withRetry(error: String? = nil) -> SyncOperation {
        let newAttempts = attempts + 1
        let backoffSeconds = calculateBackoff(attempts: newAttempts)

        return SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            status: .failed,
            attempts: newAttempts,
            lastAttemptDate: Date(),
            nextRetryDate: Date().addingTimeInterval(backoffSeconds),
            errorMessage: error,
            createdAt: createdAt
        )
    }

    /// Returns a new operation marked as in progress
    func markInProgress() -> SyncOperation {
        SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
            status: .inProgress,
            attempts: attempts,
            lastAttemptDate: Date(),
            nextRetryDate: nextRetryDate,
            errorMessage: errorMessage,
            createdAt: createdAt
        )
    }

    /// Returns a new operation marked as completed
    func markCompleted() -> SyncOperation {
        SyncOperation(
            id: id,
            type: type,
            entityType: entityType,
            entityId: entityId,
            payload: payload,
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
    private func calculateBackoff(attempts: Int) -> TimeInterval {
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
    var isReadyForRetry: Bool {
        guard status == .failed else { return false }
        guard let nextRetry = nextRetryDate else { return true }
        return Date() >= nextRetry
    }

    /// User-friendly description of the operation
    var displayDescription: String {
        let action = type.displayName
        let entity = entityType.displayName
        return "\(action) \(entity)"
    }
}

// MARK: - Display Extensions

extension SyncOperationType {
    var displayName: String {
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
    var displayName: String {
        switch self {
        case .recipe: return "recipe"
        case .collection: return "collection"
        case .groceryItem: return "grocery item"
        case .userProfile: return "profile"
        case .connection: return "connection"
        }
    }
}

extension OperationStatus {
    var displayName: String {
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
