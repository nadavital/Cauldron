import AppIntents
import Foundation

@MainActor
enum RecipeIntentDonation {
    private static let boundaryCoordinator = RecipeIntentDonationBoundaryCoordinator()

    static func recordCookModeStarted(for recipe: Recipe) async {
        guard let ownerID = CurrentUserSession.shared.userId,
              recipe.ownerId == ownerID,
              !recipe.isPreview else {
            return
        }
        do {
            _ = try await boundaryCoordinator.performDonation(
                ownerID: ownerID,
                currentOwnerID: { CurrentUserSession.shared.userId }
            ) {
                _ = try await StartCookingRecipeIntent(
                    recipe: RecipeIntentEntity(recipe: recipe)
                ).donate()
            }
        } catch {
            AppLogger.general.debug("Unable to donate Cook Mode action: \(error.localizedDescription)")
        }
    }

    static func recordIngredientsAdded(for recipe: Recipe) async {
        guard let ownerID = CurrentUserSession.shared.userId,
              recipe.ownerId == ownerID,
              !recipe.isPreview else {
            return
        }
        do {
            _ = try await boundaryCoordinator.performDonation(
                ownerID: ownerID,
                currentOwnerID: { CurrentUserSession.shared.userId }
            ) {
                _ = try await AddRecipeIngredientsToGroceriesIntent(
                    recipe: RecipeIntentEntity(recipe: recipe)
                ).donate()
            }
        } catch {
            AppLogger.general.debug("Unable to donate grocery action: \(error.localizedDescription)")
        }
    }

    static func recordTimerStarted(_ timer: TimerSpec) async {
        guard let minutes = timerDonationMinutes(for: timer) else { return }
        do {
            _ = try await StartCookingTimerIntent(minutes: minutes, label: timer.label).donate()
        } catch {
            AppLogger.general.debug("Unable to donate cooking timer action: \(error.localizedDescription)")
        }
    }

    nonisolated static func timerDonationMinutes(for timer: TimerSpec) -> Int? {
        guard timer.seconds >= 60,
              timer.seconds <= 86_400,
              timer.seconds.isMultiple(of: 60) else {
            return nil
        }
        return timer.seconds / 60
    }

    static func reconcileAccountBoundary(currentOwnerID: UUID?) async {
        await boundaryCoordinator.reconcile(currentOwnerID: currentOwnerID)
    }
}

@MainActor
final class RecipeIntentDonationBoundaryCoordinator {
    enum RecipeScopedIntent: CaseIterable, Equatable {
        case startCookingRecipe
        case addRecipeIngredientsToGroceries
    }

    enum ReconciliationResult: Equatable {
        case unchanged
        case deleted
        case deletionFailed([RecipeScopedIntent])

        var allowsDonation: Bool {
            switch self {
            case .unchanged, .deleted:
                true
            case .deletionFailed:
                false
            }
        }
    }

    typealias DeleteDonations = (RecipeScopedIntent) async throws -> Void
    typealias ReconciliationRequested = (UUID?) -> Void

    private static let ownerIDKey = "appIntents.recipeDonationOwnerID.v1"
    private static let migrationEstablishedKey = "appIntents.recipeDonationMigrationEstablished.v1"
    private static let cleanupRequiredKey = "appIntents.recipeDonationCleanupRequired.v1"

    private let defaults: UserDefaults
    private let deleteDonations: DeleteDonations
    private let reconciliationRequested: ReconciliationRequested?
    private var latestRequestedOwnerID: UUID?
    private var requestGeneration: UInt = 0
    private var isReconciling = false
    private var reconciliationWaiters: [CheckedContinuation<ReconciliationResult, Never>] = []

    init(
        defaults: UserDefaults = UserDefaults(suiteName: CookSessionSharedStore.appGroupID) ?? .standard,
        deleteDonations: @escaping DeleteDonations = RecipeIntentDonationBoundaryCoordinator.deleteLiveDonations,
        reconciliationRequested: ReconciliationRequested? = nil
    ) {
        self.defaults = defaults
        self.deleteDonations = deleteDonations
        self.reconciliationRequested = reconciliationRequested
    }

    @discardableResult
    func reconcile(currentOwnerID: UUID?) async -> ReconciliationResult {
        latestRequestedOwnerID = currentOwnerID
        requestGeneration &+= 1
        reconciliationRequested?(currentOwnerID)

        if isReconciling {
            return await withCheckedContinuation { continuation in
                reconciliationWaiters.append(continuation)
            }
        }

        isReconciling = true
        let result = await reconcileLatestRequest()
        isReconciling = false

        let waiters = reconciliationWaiters
        reconciliationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
        return result
    }

    /// Keeps recipe-scoped donation creation inside the same single-flight as
    /// account-boundary deletion. If identity changes while the system donate
    /// call is suspended, boundary callers wait and the newly-created stale
    /// donation is deleted before any waiter resumes.
    @discardableResult
    func performDonation(
        ownerID: UUID,
        currentOwnerID: @MainActor () -> UUID?,
        operation: () async throws -> Void
    ) async throws -> Bool {
        // Do not let a stale caller overwrite a newer boundary request before
        // its first suspension point.
        guard currentOwnerID() == ownerID else { return false }
        let reconciliation = await reconcile(currentOwnerID: ownerID)
        guard reconciliation.allowsDonation,
              latestRequestedOwnerID == ownerID,
              currentOwnerID() == ownerID else {
            return false
        }

        guard await acquireDonationFlight(
            ownerID: ownerID,
            currentOwnerID: currentOwnerID
        ) else {
            return false
        }
        let donationGeneration = requestGeneration
        do {
            try await operation()
        } catch {
            let cleanupResult = await finishDonationFlight(
                ownerID: ownerID,
                donationGeneration: donationGeneration,
                currentOwnerID: currentOwnerID()
            )
            finishSingleFlight(result: cleanupResult)
            throw error
        }

        let cleanupResult = await finishDonationFlight(
            ownerID: ownerID,
            donationGeneration: donationGeneration,
            currentOwnerID: currentOwnerID()
        )
        let remainedCurrent = donationGeneration == requestGeneration
            && latestRequestedOwnerID == ownerID
            && currentOwnerID() == ownerID
        if remainedCurrent {
            recordDonation(ownerID: ownerID)
        }
        finishSingleFlight(result: cleanupResult)
        return remainedCurrent
    }

    /// Reconciliation waiters are resumed together, so donation callers must
    /// acquire the single-flight again after waking. This keeps system donate
    /// calls exclusive with one another as well as with account cleanup.
    private func acquireDonationFlight(
        ownerID: UUID,
        currentOwnerID: @MainActor () -> UUID?
    ) async -> Bool {
        while isReconciling {
            let result = await withCheckedContinuation { continuation in
                reconciliationWaiters.append(continuation)
            }
            guard result.allowsDonation else { return false }
        }
        guard latestRequestedOwnerID == ownerID,
              currentOwnerID() == ownerID else {
            return false
        }
        isReconciling = true
        return true
    }

    private func finishDonationFlight(
        ownerID: UUID,
        donationGeneration: UInt,
        currentOwnerID: UUID?
    ) async -> ReconciliationResult {
        if donationGeneration == requestGeneration,
           latestRequestedOwnerID == ownerID,
           currentOwnerID != ownerID {
            latestRequestedOwnerID = currentOwnerID
            requestGeneration &+= 1
            reconciliationRequested?(currentOwnerID)
        }
        guard donationGeneration != requestGeneration || latestRequestedOwnerID != ownerID else {
            return .unchanged
        }
        return await reconcileLatestRequest()
    }

    private func finishSingleFlight(result: ReconciliationResult) {
        isReconciling = false
        let waiters = reconciliationWaiters
        reconciliationWaiters.removeAll()
        waiters.forEach { $0.resume(returning: result) }
    }

    private func reconcileLatestRequest() async -> ReconciliationResult {
        while true {
            let generation = requestGeneration
            let ownerID = latestRequestedOwnerID
            if let result = await performReconciliation(
                currentOwnerID: ownerID,
                generation: generation
            ) {
                return result
            }
        }
    }

    /// Returns `nil` when a newer account-boundary request supersedes this pass.
    /// The single-flight loop then repeats every deletion for the newest owner.
    private func performReconciliation(
        currentOwnerID: UUID?,
        generation: UInt
    ) async -> ReconciliationResult? {
        let recordedOwnerID = defaults.string(forKey: Self.ownerIDKey).flatMap(UUID.init(uuidString:))
        let needsCleanup = defaults.bool(forKey: Self.cleanupRequiredKey) ||
            !defaults.bool(forKey: Self.migrationEstablishedKey) ||
            recordedOwnerID != currentOwnerID

        guard needsCleanup else {
            return generation == requestGeneration ? .unchanged : nil
        }

        // Persist before crossing into the system API so a process exit or API
        // failure is retried at the next account-boundary reconciliation.
        defaults.set(true, forKey: Self.cleanupRequiredKey)

        var failedIntents: [RecipeScopedIntent] = []
        for intent in RecipeScopedIntent.allCases {
            do {
                try await deleteDonations(intent)
            } catch {
                failedIntents.append(intent)
                AppLogger.general.error(
                    "Unable to delete recipe-scoped App Intent donations: \(error.localizedDescription)"
                )
            }

            guard generation == requestGeneration else {
                return nil
            }
        }

        guard failedIntents.isEmpty else {
            return .deletionFailed(failedIntents)
        }

        defaults.set(currentOwnerID?.uuidString, forKey: Self.ownerIDKey)
        defaults.set(true, forKey: Self.migrationEstablishedKey)
        defaults.set(false, forKey: Self.cleanupRequiredKey)
        return .deleted
    }

    func recordDonation(ownerID: UUID) {
        let recordedOwnerID = defaults.string(forKey: Self.ownerIDKey).flatMap(UUID.init(uuidString:))
        guard !defaults.bool(forKey: Self.cleanupRequiredKey),
              recordedOwnerID == ownerID else {
            return
        }
        defaults.set(ownerID.uuidString, forKey: Self.ownerIDKey)
        defaults.set(true, forKey: Self.migrationEstablishedKey)
    }

    private static func deleteLiveDonations(for intent: RecipeScopedIntent) async throws {
        let predicate: IntentDonationMatchingPredicate
        switch intent {
        case .startCookingRecipe:
            predicate = .intentType(StartCookingRecipeIntent.self)
        case .addRecipeIngredientsToGroceries:
            predicate = .intentType(AddRecipeIngredientsToGroceriesIntent.self)
        }
        _ = try await IntentDonationManager.shared.deleteDonations(matching: predicate)
    }
}
