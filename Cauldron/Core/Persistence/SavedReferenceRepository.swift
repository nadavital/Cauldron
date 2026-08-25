//
//  SavedReferenceRepository.swift
//  Cauldron
//

import Foundation
import SwiftData
import os

extension Notification.Name {
    /// Posted when a saved recipe reference is created, changed, or removed.
    nonisolated static let savedRecipeReferencesChanged = Notification.Name("SavedRecipeReferencesChanged")

    /// Posted when a saved collection reference is created or removed.
    nonisolated static let savedCollectionReferencesChanged = Notification.Name("SavedCollectionReferencesChanged")
}

private nonisolated struct SavedReferenceReconciliationChanges: Sendable {
    var addedRecipeReferences: [SavedRecipeReference] = []
    var removedRecipeReferences: [SavedRecipeReference] = []
    var addedCollectionReferences: [SavedCollectionReference] = []
    var removedCollectionReferences: [SavedCollectionReference] = []

    nonisolated var isEmpty: Bool {
        addedRecipeReferences.isEmpty
            && removedRecipeReferences.isEmpty
            && addedCollectionReferences.isEmpty
            && removedCollectionReferences.isEmpty
    }
}

actor SavedReferenceRepository {
    typealias AccountScopeProvider = @Sendable (UUID) async -> SyncOperationAccountScope?
    typealias AccountScopeValidator = @Sendable (SyncOperationAccountScope) async -> Bool
    typealias LocalMutationCommitHook = @Sendable () async throws -> Void

    private let modelContainer: ModelContainer
    private let savedReferenceCloudService: SavedReferenceCloudService?
    private let operationQueueService: OperationQueueService?
    private let accountScopeProvider: AccountScopeProvider?
    private let accountScopeValidator: AccountScopeValidator?
    private let localMutationCommitHook: LocalMutationCommitHook?
    private let queueMutationsDuringTests: Bool
    private let logger = Logger(subsystem: "com.cauldron", category: "SavedReferenceRepository")
    private var operationQueueReplayTask: Task<Void, Never>?

    init(
        modelContainer: ModelContainer,
        savedReferenceCloudService: SavedReferenceCloudService? = nil,
        operationQueueService: OperationQueueService? = nil,
        accountScopeProvider: AccountScopeProvider? = nil,
        accountScopeValidator: AccountScopeValidator? = nil,
        localMutationCommitHook: LocalMutationCommitHook? = nil,
        queueMutationsDuringTests: Bool = false
    ) {
        self.modelContainer = modelContainer
        self.savedReferenceCloudService = savedReferenceCloudService
        self.operationQueueService = operationQueueService
        self.accountScopeProvider = accountScopeProvider
        self.accountScopeValidator = accountScopeValidator
        self.localMutationCommitHook = localMutationCommitHook
        self.queueMutationsDuringTests = queueMutationsDuringTests

        if !RuntimeEnvironment.isRunningTests,
           !RuntimeEnvironment.isSimulatorQAMode,
           savedReferenceCloudService != nil,
           operationQueueService != nil {
            Task { await self.startOperationQueueReplayTask() }
        }
    }

    func saveRecipeReference(
        sourceRecipe: Recipe,
        userId: UUID,
        originalCreatorName: String?,
        materializedRecipeId: UUID? = nil
    ) async throws -> (reference: SavedRecipeReference, reusedExistingReference: Bool) {
        let accountScope = try await mutationAccountScope(userID: userId)
        let sourceRecipeId = sourceRecipe.relatedGraphReferenceID
        if let existing = try await recipeReference(userId: userId, sourceRecipeId: sourceRecipeId) {
            if let materializedRecipeId,
               existing.materializedRecipeId != materializedRecipeId {
                let updated = try await updateRecipeReference(existing.withMaterializedRecipeId(materializedRecipeId))
                return (updated, true)
            }
            return (existing, true)
        }

        let now = Date()
        let reference = SavedRecipeReference(
            userId: userId,
            sourceRecipeId: sourceRecipeId,
            sourceOwnerId: sourceRecipe.originalCreatorId ?? sourceRecipe.ownerId,
            sourceRecipeName: sourceRecipe.title,
            originalCreatorName: sourceRecipe.originalCreatorName ?? originalCreatorName,
            materializedRecipeId: materializedRecipeId,
            cloudRecordName: SavedReferenceCloudService.recipeReferenceRecordName(
                userId: userId,
                sourceRecipeId: sourceRecipeId
            ),
            savedAt: now,
            sourceRecipeUpdatedAt: sourceRecipe.sourceRecipeUpdatedAt ?? sourceRecipe.updatedAt,
            createdAt: now,
            updatedAt: now
        )

        try await validateMutationAccountScope(accountScope)
        let operationID = try await enqueueSavedRecipeReferenceSync(reference, type: .create, accountScope: accountScope)
        let context = ModelContext(modelContainer)
        do {
            try await validateMutationAccountScope(accountScope)
            context.insert(SavedRecipeReferenceModel.from(reference))
            try await localMutationCommitHook?()
            try await validateMutationAccountScope(accountScope)
            try context.save()
        } catch {
            await compensateFailedLocalMutation(operationID: operationID)
            throw error
        }
        syncRecipeReferenceToCloud(reference, operationID: operationID)
        postSavedRecipeReferenceChanged(changeType: "saved", reference: reference)
        logger.info("Saved recipe reference: \(sourceRecipeId)")
        return (reference, false)
    }

    func recipeReference(userId: UUID, sourceRecipeId: UUID) async throws -> SavedRecipeReference? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { model in
                model.userId == userId && model.sourceRecipeId == sourceRecipeId
            }
        )
        return try context.fetch(descriptor).first?.toDomain()
    }

    func recipeReferences(for userId: UUID) async throws -> [SavedRecipeReference] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    @discardableResult
    func deleteRecipeReference(userId: UUID, sourceRecipeId: UUID) async throws -> Bool {
        let accountScope = try await mutationAccountScope(userID: userId)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { model in
                model.userId == userId && model.sourceRecipeId == sourceRecipeId
            }
        )

        guard let model = try context.fetch(descriptor).first else {
            return false
        }

        let reference = model.toDomain()
        try await validateMutationAccountScope(accountScope)
        let operationID = try await enqueueSavedRecipeReferenceSync(reference, type: .delete, accountScope: accountScope)
        do {
            try await validateMutationAccountScope(accountScope)
            context.delete(model)
            try await localMutationCommitHook?()
            try await validateMutationAccountScope(accountScope)
            try context.save()
        } catch {
            await compensateFailedLocalMutation(operationID: operationID)
            throw error
        }
        deleteRecipeReferenceFromCloud(reference, operationID: operationID)
        postSavedRecipeReferenceChanged(changeType: "removed", reference: reference)
        return true
    }

    @discardableResult
    func updateRecipeReference(_ reference: SavedRecipeReference) async throws -> SavedRecipeReference {
        let accountScope = try await mutationAccountScope(userID: reference.userId)
        let context = ModelContext(modelContainer)
        let referenceId = reference.id
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { $0.id == referenceId }
        )

        guard let model = try context.fetch(descriptor).first else {
            throw SavedReferenceRepositoryError.referenceNotFound
        }

        try await validateMutationAccountScope(accountScope)
        let operationID = try await enqueueSavedRecipeReferenceSync(reference, type: .update, accountScope: accountScope)
        do {
            try await validateMutationAccountScope(accountScope)
            model.sourceOwnerId = reference.sourceOwnerId
            model.sourceRecipeName = reference.sourceRecipeName
            model.originalCreatorName = reference.originalCreatorName
            model.materializedRecipeId = reference.materializedRecipeId
            model.cloudRecordName = reference.cloudRecordName
            model.sourceRecipeUpdatedAt = reference.sourceRecipeUpdatedAt
            model.updatedAt = reference.updatedAt
            try await localMutationCommitHook?()
            try await validateMutationAccountScope(accountScope)
            try context.save()
        } catch {
            await compensateFailedLocalMutation(operationID: operationID)
            throw error
        }
        let updated = model.toDomain()
        syncRecipeReferenceToCloud(updated, operationID: operationID)
        postSavedRecipeReferenceChanged(changeType: "saved", reference: updated)
        return updated
    }

    func saveCollectionReference(
        sourceCollection: Collection,
        userId: UUID
    ) async throws -> (reference: SavedCollectionReference, reusedExistingReference: Bool) {
        let accountScope = try await mutationAccountScope(userID: userId)
        let sourceCollectionId = sourceCollection.sourceCollectionReferenceId
        if let existing = try await collectionReference(userId: userId, sourceCollectionId: sourceCollectionId) {
            return (existing, true)
        }

        let now = Date()
        let reference = SavedCollectionReference(
            userId: userId,
            sourceCollectionId: sourceCollectionId,
            sourceOwnerId: sourceCollection.originalCollectionOwnerId ?? sourceCollection.userId,
            sourceCollectionName: sourceCollection.originalCollectionName ?? sourceCollection.name,
            cloudRecordName: SavedReferenceCloudService.collectionReferenceRecordName(
                userId: userId,
                sourceCollectionId: sourceCollectionId
            ),
            savedAt: now,
            sourceCollectionUpdatedAt: sourceCollection.sourceCollectionUpdatedAt ?? sourceCollection.updatedAt,
            createdAt: now,
            updatedAt: now
        )

        try await validateMutationAccountScope(accountScope)
        let operationID = try await enqueueSavedCollectionReferenceSync(reference, type: .create, accountScope: accountScope)
        let context = ModelContext(modelContainer)
        do {
            try await validateMutationAccountScope(accountScope)
            context.insert(SavedCollectionReferenceModel.from(reference))
            try await localMutationCommitHook?()
            try await validateMutationAccountScope(accountScope)
            try context.save()
        } catch {
            await compensateFailedLocalMutation(operationID: operationID)
            throw error
        }
        syncCollectionReferenceToCloud(reference, operationID: operationID)
        postSavedCollectionReferenceChanged(changeType: "saved", reference: reference, collection: sourceCollection)
        logger.info("Saved collection reference: \(sourceCollectionId)")
        return (reference, false)
    }

    func collectionReference(userId: UUID, sourceCollectionId: UUID) async throws -> SavedCollectionReference? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedCollectionReferenceModel>(
            predicate: #Predicate { model in
                model.userId == userId && model.sourceCollectionId == sourceCollectionId
            }
        )
        return try context.fetch(descriptor).first?.toDomain()
    }

    func collectionReferences(for userId: UUID) async throws -> [SavedCollectionReference] {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedCollectionReferenceModel>(
            predicate: #Predicate { $0.userId == userId },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    @discardableResult
    func deleteCollectionReference(userId: UUID, sourceCollectionId: UUID) async throws -> Bool {
        let accountScope = try await mutationAccountScope(userID: userId)
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SavedCollectionReferenceModel>(
            predicate: #Predicate { model in
                model.userId == userId && model.sourceCollectionId == sourceCollectionId
            }
        )

        guard let model = try context.fetch(descriptor).first else {
            return false
        }

        let reference = model.toDomain()
        try await validateMutationAccountScope(accountScope)
        let operationID = try await enqueueSavedCollectionReferenceSync(reference, type: .delete, accountScope: accountScope)
        do {
            try await validateMutationAccountScope(accountScope)
            context.delete(model)
            try await localMutationCommitHook?()
            try await validateMutationAccountScope(accountScope)
            try context.save()
        } catch {
            await compensateFailedLocalMutation(operationID: operationID)
            throw error
        }
        deleteCollectionReferenceFromCloud(reference, operationID: operationID)
        postSavedCollectionReferenceChanged(changeType: "removed", reference: reference)
        return true
    }

    func syncFromCloudKit(userId: UUID) async throws {
        guard let savedReferenceCloudService else { return }
        let accountScope = try await beginReconciliation(userID: userId)
        try await validateReconciliation(accountScope)

        let remoteRecipeReferences: [SavedRecipeReference]
        let remoteCollectionReferences: [SavedCollectionReference]

        do {
            remoteRecipeReferences = try await savedReferenceCloudService.fetchRecipeReferences(for: userId)
            try await validateReconciliation(accountScope)
            remoteCollectionReferences = try await savedReferenceCloudService.fetchCollectionReferences(for: userId)
            try await validateReconciliation(accountScope)
        } catch SavedReferenceCloudServiceError.recordTypeUnavailable {
            logger.info("Saved reference CloudKit schema is unavailable; skipping reference reconciliation")
            return
        }

        let context = ModelContext(modelContainer)
        let pendingReferenceOperations = await pendingReferenceOperations()
        try await validateReconciliation(accountScope)
        let effectiveRemoteRecipeReferences = Self.remoteRecipeReferences(
            remoteRecipeReferences,
            excludingPendingDeletes: pendingReferenceOperations,
            for: userId
        )
        let effectiveRemoteCollectionReferences = Self.remoteCollectionReferences(
            remoteCollectionReferences,
            excludingPendingDeletes: pendingReferenceOperations,
            for: userId
        )
        let localRecipeReferences = try fetchRecipeReferences(userId: userId, context: context)
        let localCollectionReferences = try fetchCollectionReferences(userId: userId, context: context)
        let localRecipeReferencesBySourceId = Self.newestRecipeReferencesBySourceId(localRecipeReferences)
        let localCollectionSourceIds = Set(localCollectionReferences.map(\.sourceCollectionId))

        for reference in effectiveRemoteRecipeReferences {
            try upsertRecipeReference(reference, context: context)
        }
        for reference in effectiveRemoteCollectionReferences {
            try upsertCollectionReference(reference, context: context)
        }
        var changes = try await reconcileLocalReferences(
            userId: userId,
            remoteRecipeReferences: effectiveRemoteRecipeReferences,
            remoteCollectionReferences: effectiveRemoteCollectionReferences,
            context: context,
            accountScope: accountScope
        )
        changes.addedRecipeReferences = Self.appliedRemoteRecipeReferenceChanges(
            effectiveRemoteRecipeReferences,
            localBySourceId: localRecipeReferencesBySourceId
        )
        changes.addedCollectionReferences = effectiveRemoteCollectionReferences.filter {
            !localCollectionSourceIds.contains($0.sourceCollectionId)
        }
        try await validateReconciliation(accountScope)
        try context.save()
        try await validateReconciliation(accountScope)
        postReconciliationChanges(changes)
    }

    func reconcileLocalReferences(
        userId: UUID,
        remoteRecipeReferences: [SavedRecipeReference],
        remoteCollectionReferences: [SavedCollectionReference]
    ) async throws {
        let accountScope = try await beginReconciliation(userID: userId)
        try await validateReconciliation(accountScope)
        let context = ModelContext(modelContainer)
        let changes = try await reconcileLocalReferences(
            userId: userId,
            remoteRecipeReferences: remoteRecipeReferences,
            remoteCollectionReferences: remoteCollectionReferences,
            context: context,
            accountScope: accountScope
        )
        try await validateReconciliation(accountScope)
        try context.save()
        try await validateReconciliation(accountScope)
        postReconciliationChanges(changes)
    }

    func forceSyncAllReferencesToCloud(userId: UUID) async throws {
        guard let savedReferenceCloudService else { return }
        let authorizationContext = try await verifiedMutationContext(userID: userId)

        let recipeReferences = try await recipeReferences(for: userId)
        let collectionReferences = try await collectionReferences(for: userId)

        for reference in recipeReferences {
            try await savedReferenceCloudService.saveRecipeReference(
                reference,
                authorizationContext: authorizationContext
            )
        }
        for reference in collectionReferences {
            try await savedReferenceCloudService.saveCollectionReference(
                reference,
                authorizationContext: authorizationContext
            )
        }
    }

    private func enqueueSavedRecipeReferenceSync(
        _ reference: SavedRecipeReference,
        type: SyncOperationType,
        accountScope: SyncOperationAccountScope?
    ) async throws -> UUID? {
        guard shouldQueueMutations else {
            return nil
        }
        guard let operationQueueService else { throw SavedReferenceRepositoryError.operationQueueUnavailable }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(reference)
        } catch {
            throw SavedReferenceRepositoryError.operationPayloadEncodingFailed
        }

        return await operationQueueService.addOperation(
            type: type,
            entityType: .savedRecipeReference,
            entityId: reference.id,
            payload: payload,
            ownerId: reference.userId,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )
    }

    private func enqueueSavedCollectionReferenceSync(
        _ reference: SavedCollectionReference,
        type: SyncOperationType,
        accountScope: SyncOperationAccountScope?
    ) async throws -> UUID? {
        guard shouldQueueMutations else {
            return nil
        }
        guard let operationQueueService else { throw SavedReferenceRepositoryError.operationQueueUnavailable }
        let payload: Data
        do {
            payload = try JSONEncoder().encode(reference)
        } catch {
            throw SavedReferenceRepositoryError.operationPayloadEncodingFailed
        }

        return await operationQueueService.addOperation(
            type: type,
            entityType: .savedCollectionReference,
            entityId: reference.id,
            payload: payload,
            ownerId: reference.userId,
            accountRevision: accountScope?.revision,
            accountIdentity: accountScope?.cloudKitIdentity
        )
    }

    private var shouldQueueMutations: Bool {
        !RuntimeEnvironment.isSimulatorQAMode &&
            (!RuntimeEnvironment.isRunningTests || queueMutationsDuringTests)
    }

    private func compensateFailedLocalMutation(operationID: UUID?) async {
        guard let operationID else { return }
        await operationQueueService?.removeOperation(operationId: operationID)
    }

    private func beginReconciliation(userID: UUID) async throws -> SyncOperationAccountScope? {
        if let accountScopeProvider {
            guard let scope = await accountScopeProvider(userID) else {
                throw UserSessionError.accountChanged
            }
            return scope
        }
        guard !RuntimeEnvironment.isRunningTests, !RuntimeEnvironment.isSimulatorQAMode else {
            return nil
        }
        guard let scope = await MainActor.run(body: {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: userID)
        }) else { throw UserSessionError.accountChanged }
        return scope
    }

    private func validateReconciliation(_ accountScope: SyncOperationAccountScope?) async throws {
        guard let accountScope else { return }
        let isCurrent: Bool
        if let accountScopeValidator {
            isCurrent = await accountScopeValidator(accountScope)
        } else {
            isCurrent = await MainActor.run {
                CurrentUserSession.shared.syncOperationAccountScope(ownerID: accountScope.ownerId) == accountScope
            }
        }
        guard isCurrent else { throw UserSessionError.accountChanged }
    }

    private func mutationAccountScope(userID: UUID) async throws -> SyncOperationAccountScope? {
        guard !RuntimeEnvironment.isRunningTests,
              !RuntimeEnvironment.isSimulatorQAMode,
              savedReferenceCloudService != nil,
              operationQueueService != nil else { return nil }
        guard let scope = await MainActor.run(body: {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: userID)
        }) else { throw UserSessionError.accountChanged }
        return scope
    }

    private func validateMutationAccountScope(_ accountScope: SyncOperationAccountScope?) async throws {
        guard let accountScope else { return }
        let currentScope = await MainActor.run {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: accountScope.ownerId)
        }
        guard currentScope == accountScope else { throw UserSessionError.accountChanged }
    }

    private func startOperationQueueReplayTask() {
        operationQueueReplayTask?.cancel()
        operationQueueReplayTask = Task {
            await replayReadySavedReferenceOperations()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await replayReadySavedReferenceOperations()
            }
        }
    }

    private func replayReadySavedReferenceOperations() async {
        guard let operationQueueService else { return }

        let operations = await operationQueueService.getAllOperations()
            .filter { operation in
                (operation.entityType == .savedRecipeReference || operation.entityType == .savedCollectionReference) &&
                (operation.status == .pending || operation.isReadyForRetry)
            }

        for operation in operations {
            guard !Task.isCancelled else { break }
            await replaySavedReferenceOperation(operation)
        }
    }

    private func replaySavedReferenceOperation(_ operation: SyncOperation) async {
        guard let operationQueueService,
              let savedReferenceCloudService else {
            return
        }

        do {
            switch operation.entityType {
            case .savedRecipeReference:
                guard let payload = operation.payload else {
                    throw SavedReferenceRepositoryError.missingOperationPayload
                }
                let reference = try JSONDecoder().decode(SavedRecipeReference.self, from: payload)
                guard await authorizeSavedReferenceReplay(operation, entityOwnerId: reference.userId) else { return }
                let authorizationContext = try await verifiedMutationContext(userID: reference.userId)
                await operationQueueService.markInProgress(operationId: operation.id)
                if operation.type == .delete {
                    try await savedReferenceCloudService.deleteRecipeReference(
                        reference,
                        authorizationContext: authorizationContext
                    )
                } else {
                    try await savedReferenceCloudService.saveRecipeReference(
                        reference,
                        authorizationContext: authorizationContext
                    )
                }

            case .savedCollectionReference:
                guard let payload = operation.payload else {
                    throw SavedReferenceRepositoryError.missingOperationPayload
                }
                let reference = try JSONDecoder().decode(SavedCollectionReference.self, from: payload)
                guard await authorizeSavedReferenceReplay(operation, entityOwnerId: reference.userId) else { return }
                let authorizationContext = try await verifiedMutationContext(userID: reference.userId)
                await operationQueueService.markInProgress(operationId: operation.id)
                if operation.type == .delete {
                    try await savedReferenceCloudService.deleteCollectionReference(
                        reference,
                        authorizationContext: authorizationContext
                    )
                } else {
                    try await savedReferenceCloudService.saveCollectionReference(
                        reference,
                        authorizationContext: authorizationContext
                    )
                }

            default:
                throw SavedReferenceRepositoryError.unsupportedOperation
            }

            await operationQueueService.markCompleted(operationId: operation.id)
        } catch {
            await operationQueueService.markFailed(
                operationId: operation.id,
                error: "Saved reference replay failed: \(error.localizedDescription)"
            )
        }
    }

    private func replaySavedReferenceOperation(operationId: UUID) async {
        guard let operationQueueService,
              let operation = await operationQueueService.getOperation(operationId: operationId) else {
            return
        }
        await replaySavedReferenceOperation(operation)
    }

    private func authorizeSavedReferenceReplay(
        _ operation: SyncOperation,
        entityOwnerId: UUID
    ) async -> Bool {
        let currentScope = await MainActor.run {
            CurrentUserSession.shared.syncOperationAccountScope(ownerID: entityOwnerId)
        }
        switch SyncOperationAccountPolicy.decision(
            operation: operation,
            entityOwnerId: entityOwnerId,
            currentScope: currentScope
        ) {
        case .allowed:
            return true
        case .migrateLegacy:
            guard let currentScope else { return false }
            _ = await operationQueueService?.bindLegacyOperation(
                operationId: operation.id,
                scope: currentScope
            )
            return true
        case .deferred:
            return false
        case .reject:
            await operationQueueService?.quarantineOperation(
                operationId: operation.id,
                error: "Saved reference operation belongs to another account generation"
            )
            return false
        }
    }

    private func verifiedMutationContext(userID: UUID) async throws -> VerifiedAccountMutationContext {
        guard let context = await MainActor.run(body: {
            CurrentUserSession.shared.verifiedMutationContext(ownerID: userID)
        }) else {
            throw UserSessionError.accountChanged
        }
        return context
    }

    private func upsertRecipeReference(
        _ reference: SavedRecipeReference,
        context: ModelContext
    ) throws {
        let referenceId = reference.id
        let userId = reference.userId
        let sourceRecipeId = reference.sourceRecipeId
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { model in
                model.id == referenceId || (model.userId == userId && model.sourceRecipeId == sourceRecipeId)
            }
        )

        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= reference.updatedAt else { return }
            existing.sourceOwnerId = reference.sourceOwnerId
            existing.sourceRecipeName = reference.sourceRecipeName
            existing.originalCreatorName = reference.originalCreatorName
            existing.materializedRecipeId = reference.materializedRecipeId
            existing.cloudRecordName = reference.cloudRecordName
            existing.sourceRecipeUpdatedAt = reference.sourceRecipeUpdatedAt
            existing.savedAt = reference.savedAt
            existing.createdAt = reference.createdAt
            existing.updatedAt = reference.updatedAt
        } else {
            context.insert(SavedRecipeReferenceModel.from(reference))
        }
    }

    private func upsertCollectionReference(
        _ reference: SavedCollectionReference,
        context: ModelContext
    ) throws {
        let referenceId = reference.id
        let userId = reference.userId
        let sourceCollectionId = reference.sourceCollectionId
        let descriptor = FetchDescriptor<SavedCollectionReferenceModel>(
            predicate: #Predicate { model in
                model.id == referenceId || (model.userId == userId && model.sourceCollectionId == sourceCollectionId)
            }
        )

        if let existing = try context.fetch(descriptor).first {
            guard existing.updatedAt <= reference.updatedAt else { return }
            existing.sourceOwnerId = reference.sourceOwnerId
            existing.sourceCollectionName = reference.sourceCollectionName
            existing.cloudRecordName = reference.cloudRecordName
            existing.sourceCollectionUpdatedAt = reference.sourceCollectionUpdatedAt
            existing.savedAt = reference.savedAt
            existing.createdAt = reference.createdAt
            existing.updatedAt = reference.updatedAt
        } else {
            context.insert(SavedCollectionReferenceModel.from(reference))
        }
    }

    private func reconcileLocalReferences(
        userId: UUID,
        remoteRecipeReferences: [SavedRecipeReference],
        remoteCollectionReferences: [SavedCollectionReference],
        context: ModelContext,
        accountScope: SyncOperationAccountScope?
    ) async throws -> SavedReferenceReconciliationChanges {
        var changes = SavedReferenceReconciliationChanges()
        let pendingRecipeReferenceIds = await pendingReferenceEntityIds(entityType: .savedRecipeReference)
        try await validateReconciliation(accountScope)
        let pendingCollectionReferenceIds = await pendingReferenceEntityIds(entityType: .savedCollectionReference)
        try await validateReconciliation(accountScope)

        let remoteRecipeSourceIds = Set(remoteRecipeReferences.map(\.sourceRecipeId))
        for model in try fetchRecipeReferenceModels(userId: userId, context: context) {
            guard !remoteRecipeSourceIds.contains(model.sourceRecipeId),
                  !pendingRecipeReferenceIds.contains(model.id) else {
                continue
            }
            changes.removedRecipeReferences.append(model.toDomain())
            context.delete(model)
        }

        let remoteCollectionSourceIds = Set(remoteCollectionReferences.map(\.sourceCollectionId))
        for model in try fetchCollectionReferenceModels(userId: userId, context: context) {
            guard !remoteCollectionSourceIds.contains(model.sourceCollectionId),
                  !pendingCollectionReferenceIds.contains(model.id) else {
                continue
            }
            changes.removedCollectionReferences.append(model.toDomain())
            context.delete(model)
        }
        return changes
    }

    private func fetchRecipeReferences(
        userId: UUID,
        context: ModelContext
    ) throws -> [SavedRecipeReference] {
        try fetchRecipeReferenceModels(userId: userId, context: context).map { $0.toDomain() }
    }

    private func fetchRecipeReferenceModels(
        userId: UUID,
        context: ModelContext
    ) throws -> [SavedRecipeReferenceModel] {
        let descriptor = FetchDescriptor<SavedRecipeReferenceModel>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try context.fetch(descriptor)
    }

    private func fetchCollectionReferences(
        userId: UUID,
        context: ModelContext
    ) throws -> [SavedCollectionReference] {
        try fetchCollectionReferenceModels(userId: userId, context: context).map { $0.toDomain() }
    }

    private func fetchCollectionReferenceModels(
        userId: UUID,
        context: ModelContext
    ) throws -> [SavedCollectionReferenceModel] {
        let descriptor = FetchDescriptor<SavedCollectionReferenceModel>(
            predicate: #Predicate { $0.userId == userId }
        )
        return try context.fetch(descriptor)
    }

    private nonisolated func postReconciliationChanges(_ changes: SavedReferenceReconciliationChanges) {
        guard !changes.isEmpty else { return }

        for reference in changes.addedRecipeReferences {
            postSavedRecipeReferenceChanged(changeType: "saved", reference: reference)
        }
        for reference in changes.removedRecipeReferences {
            postSavedRecipeReferenceChanged(changeType: "removed", reference: reference)
        }
        for reference in changes.addedCollectionReferences {
            postSavedCollectionReferenceChanged(changeType: "saved", reference: reference)
        }
        for reference in changes.removedCollectionReferences {
            postSavedCollectionReferenceChanged(changeType: "removed", reference: reference)
        }
    }

    private nonisolated func postSavedRecipeReferenceChanged(
        changeType: String,
        reference: SavedRecipeReference
    ) {
        NotificationCenter.default.post(
            name: .savedRecipeReferencesChanged,
            object: reference.sourceRecipeId,
            userInfo: [
                "changeType": changeType,
                "sourceRecipeId": reference.sourceRecipeId,
                "reference": reference
            ]
        )
    }

    private nonisolated func postSavedCollectionReferenceChanged(
        changeType: String,
        reference: SavedCollectionReference,
        collection: Collection? = nil
    ) {
        var userInfo: [String: Any] = [
            "changeType": changeType,
            "sourceCollectionId": reference.sourceCollectionId,
            "reference": reference
        ]
        if let collection {
            userInfo["collection"] = collection
        }
        NotificationCenter.default.post(
            name: .savedCollectionReferencesChanged,
            object: reference.sourceCollectionId,
            userInfo: userInfo
        )
    }

    nonisolated static func newestRecipeReferencesBySourceId(
        _ references: [SavedRecipeReference]
    ) -> [UUID: SavedRecipeReference] {
        references.reduce(into: [:]) { result, reference in
            guard let existing = result[reference.sourceRecipeId] else {
                result[reference.sourceRecipeId] = reference
                return
            }
            if existing.updatedAt < reference.updatedAt {
                result[reference.sourceRecipeId] = reference
            }
        }
    }

    nonisolated static func appliedRemoteRecipeReferenceChanges(
        _ remoteReferences: [SavedRecipeReference],
        localBySourceId: [UUID: SavedRecipeReference]
    ) -> [SavedRecipeReference] {
        remoteReferences.filter { remoteReference in
            guard let localReference = localBySourceId[remoteReference.sourceRecipeId] else {
                return true
            }
            return localReference.updatedAt < remoteReference.updatedAt
        }
    }

    nonisolated static func remoteRecipeReferences(
        _ remoteReferences: [SavedRecipeReference],
        excludingPendingDeletes operations: [SyncOperation],
        for userId: UUID
    ) -> [SavedRecipeReference] {
        let deletedSourceIds = Set(
            operations.compactMap { operation -> UUID? in
                guard operation.type == .delete,
                      operation.entityType == .savedRecipeReference,
                      let payload = operation.payload,
                      let reference = try? JSONDecoder().decode(SavedRecipeReference.self, from: payload),
                      reference.userId == userId else {
                    return nil
                }
                return reference.sourceRecipeId
            }
        )
        guard !deletedSourceIds.isEmpty else { return remoteReferences }
        return remoteReferences.filter { !deletedSourceIds.contains($0.sourceRecipeId) }
    }

    nonisolated static func remoteCollectionReferences(
        _ remoteReferences: [SavedCollectionReference],
        excludingPendingDeletes operations: [SyncOperation],
        for userId: UUID
    ) -> [SavedCollectionReference] {
        let deletedSourceIds = Set(
            operations.compactMap { operation -> UUID? in
                guard operation.type == .delete,
                      operation.entityType == .savedCollectionReference,
                      let payload = operation.payload,
                      let reference = try? JSONDecoder().decode(SavedCollectionReference.self, from: payload),
                      reference.userId == userId else {
                    return nil
                }
                return reference.sourceCollectionId
            }
        )
        guard !deletedSourceIds.isEmpty else { return remoteReferences }
        return remoteReferences.filter { !deletedSourceIds.contains($0.sourceCollectionId) }
    }

    private func pendingReferenceEntityIds(entityType: EntityType) async -> Set<UUID> {
        let operations = await pendingReferenceOperations()
        return Set(
            operations
                .filter { $0.entityType == entityType && $0.status != .completed }
                .map(\.entityId)
        )
    }

    private func pendingReferenceOperations() async -> [SyncOperation] {
        guard let operationQueueService else { return [] }
        return await operationQueueService.getAllOperations()
    }

    private func syncRecipeReferenceToCloud(_ reference: SavedRecipeReference, operationID: UUID?) {
        guard !RuntimeEnvironment.isRunningTests,
              !RuntimeEnvironment.isSimulatorQAMode,
              savedReferenceCloudService != nil else {
            return
        }

        Task { [weak self] in
            guard let operationID else { return }
            await self?.replaySavedReferenceOperation(operationId: operationID)
        }
    }

    private func deleteRecipeReferenceFromCloud(_ reference: SavedRecipeReference, operationID: UUID?) {
        guard !RuntimeEnvironment.isRunningTests,
              !RuntimeEnvironment.isSimulatorQAMode,
              savedReferenceCloudService != nil else {
            return
        }

        Task { [weak self] in
            guard let operationID else { return }
            await self?.replaySavedReferenceOperation(operationId: operationID)
        }
    }

    private func syncCollectionReferenceToCloud(_ reference: SavedCollectionReference, operationID: UUID?) {
        guard !RuntimeEnvironment.isRunningTests,
              !RuntimeEnvironment.isSimulatorQAMode,
              savedReferenceCloudService != nil else {
            return
        }

        Task { [weak self] in
            guard let operationID else { return }
            await self?.replaySavedReferenceOperation(operationId: operationID)
        }
    }

    private func deleteCollectionReferenceFromCloud(_ reference: SavedCollectionReference, operationID: UUID?) {
        guard !RuntimeEnvironment.isRunningTests,
              !RuntimeEnvironment.isSimulatorQAMode,
              savedReferenceCloudService != nil else {
            return
        }

        Task { [weak self] in
            guard let operationID else { return }
            await self?.replaySavedReferenceOperation(operationId: operationID)
        }
    }
}

enum SavedReferenceRepositoryError: LocalizedError {
    case referenceNotFound
    case missingOperationPayload
    case unsupportedOperation
    case operationQueueUnavailable
    case operationPayloadEncodingFailed

    var errorDescription: String? {
        switch self {
        case .referenceNotFound:
            "Saved reference not found."
        case .missingOperationPayload:
            "Saved reference operation is missing its payload."
        case .unsupportedOperation:
            "Unsupported saved reference operation."
        case .operationQueueUnavailable:
            "Saved reference sync queue is unavailable."
        case .operationPayloadEncodingFailed:
            "Saved reference operation could not be encoded."
        }
    }
}
