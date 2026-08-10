import AppIntents
import CoreSpotlight
import CryptoKit
import Foundation

struct RecipeSpotlightReconciliationQueue {
    enum Request {
        case accountBoundary(ownerID: UUID?)
        case full(ownerID: UUID?, recipes: [Recipe]?)

        var ownerID: UUID? {
            switch self {
            case .accountBoundary(let ownerID), .full(let ownerID, _):
                ownerID
            }
        }
    }

    struct PendingRequest {
        let generation: UInt64
        let request: Request
    }

    private(set) var isWorkerActive = false
    private(set) var nextGeneration: UInt64 = 0
    private var pendingRequest: PendingRequest?

    /// Returns true only when the caller must start a worker. Requests arriving
    /// while a worker is suspended at an await are coalesced to the newest one.
    mutating func enqueue(_ request: Request) -> Bool {
        nextGeneration &+= 1
        pendingRequest = PendingRequest(generation: nextGeneration, request: request)

        guard !isWorkerActive else { return false }
        isWorkerActive = true
        return true
    }

    mutating func takeNext() -> PendingRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }

    mutating func finishWorker() {
        precondition(pendingRequest == nil)
        isWorkerActive = false
    }
}

struct RecipeSpotlightRetryPolicy {
    enum RequestOrigin {
        case external
        case retry
    }

    let maximumAttempts: Int
    let baseDelaySeconds: Int64
    let maximumDelaySeconds: Int64

    private(set) var attempts = 0

    init(
        maximumAttempts: Int = 5,
        baseDelaySeconds: Int64 = 2,
        maximumDelaySeconds: Int64 = 32
    ) {
        precondition(maximumAttempts >= 0)
        precondition(baseDelaySeconds > 0)
        precondition(maximumDelaySeconds >= baseDelaySeconds)
        self.maximumAttempts = maximumAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maximumDelaySeconds = maximumDelaySeconds
    }

    mutating func prepare(for origin: RequestOrigin) {
        if case .external = origin {
            reset()
        }
    }

    mutating func nextDelayAfterFailure() -> Duration? {
        guard attempts < maximumAttempts else { return nil }

        let exponent = min(attempts, 62)
        let multiplier = Int64(1) << exponent
        let multiplied = baseDelaySeconds.multipliedReportingOverflow(by: multiplier)
        let delaySeconds = multiplied.overflow
            ? maximumDelaySeconds
            : min(multiplied.partialValue, maximumDelaySeconds)
        attempts += 1
        return .seconds(delaySeconds)
    }

    mutating func reset() {
        attempts = 0
    }
}

@MainActor
final class RecipeSpotlightIndexer {
    static let shared = RecipeSpotlightIndexer()

    private static let indexedRecipeIDsKey = "spotlight.indexedRecipeIDs.v1"
    private static let indexedOwnerIDKey = "spotlight.indexedOwnerID.v1"
    private static let indexedFingerprintsKey = "spotlight.indexedFingerprints.v1"
    private static let cleanupRequiredKey = "spotlight.cleanupRequired.v1"

    private let index: CSSearchableIndex
    private let defaults: UserDefaults?
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var workerTask: Task<Void, Never>?
    private var reconciliationQueue = RecipeSpotlightReconciliationQueue()
    private var retryPolicy = RecipeSpotlightRetryPolicy()

    init(
        index: CSSearchableIndex = .default(),
        defaults: UserDefaults? = UserDefaults(suiteName: CookSessionSharedStore.appGroupID)
    ) {
        self.index = index
        self.defaults = defaults
    }

    /// Checks only the account boundary. This can run immediately after session
    /// verification without putting a full library fetch on the launch path.
    func scheduleAccountBoundaryReconciliation() {
        enqueue(
            .accountBoundary(ownerID: CurrentUserSession.shared.userId),
            origin: .external
        )
    }

    /// Reconciles after a short quiet period. Preloaded recipes avoid a duplicate
    /// repository fetch when the app has already loaded the library for display.
    func scheduleReconciliation(preloadedRecipes: [Recipe]? = nil) {
        let ownerID = CurrentUserSession.shared.userId
        resetRetryBudget()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.enqueue(
                .full(ownerID: ownerID, recipes: preloadedRecipes),
                origin: .external
            )
        }
    }

    private func enqueue(
        _ request: RecipeSpotlightReconciliationQueue.Request,
        origin: RecipeSpotlightRetryPolicy.RequestOrigin
    ) {
        retryPolicy.prepare(for: origin)
        if case .external = origin {
            retryTask?.cancel()
            retryTask = nil
        }
        guard reconciliationQueue.enqueue(request) else { return }
        workerTask = Task { [weak self] in
            await self?.drainRequests()
        }
    }

    private func drainRequests() async {
        while let pendingRequest = reconciliationQueue.takeNext() {
            do {
                try await perform(pendingRequest.request)
                resetRetryBudget()
            } catch {
                AppLogger.general.error("Recipe Spotlight reconciliation failed: \(error.localizedDescription)")
                scheduleRetry()
            }
        }

        reconciliationQueue.finishWorker()
        workerTask = nil
    }

    private func perform(_ request: RecipeSpotlightReconciliationQueue.Request) async throws {
        // Identity reverification must be allowed to finish on MainActor. A
        // request captured before that boundary cannot be made safe by
        // synchronously re-enqueuing it: doing so hot-spins this drain loop and
        // can starve the session task that would make progress possible.
        guard CurrentUserSession.shared.isAccountIdentityVerified else {
            try await enforceAccountBoundary(expectedOwnerID: nil)
            return
        }

        // The verified account changed after this request was captured. Clear
        // the old account's searchable data; the verified session-change hook
        // will enqueue a fresh request with the new owner.
        let currentOwnerID = CurrentUserSession.shared.userId
        guard currentOwnerID == request.ownerID else {
            try await enforceAccountBoundary(expectedOwnerID: currentOwnerID)
            return
        }

        try await enforceAccountBoundary(expectedOwnerID: request.ownerID)
        guard sessionMatches(request.ownerID) else {
            try await removeIndexAfterSessionChange()
            return
        }

        guard case .full(let ownerID, let preloadedRecipes) = request,
              let ownerID else {
            return
        }

        let recipes: [Recipe]
        if let preloadedRecipes {
            recipes = preloadedRecipes.filter { !$0.isPreview && $0.ownerId == ownerID }
        } else {
            recipes = try await RecipeIntentProvider.shared.libraryRecipes()
        }

        guard sessionMatches(ownerID) else {
            try await removeIndexAfterSessionChange()
            return
        }

        let entities = recipes.map(RecipeIntentEntity.init(recipe:))
        let currentFingerprints = Dictionary(
            uniqueKeysWithValues: entities.map { ($0.id, Self.fingerprint(for: $0)) }
        )
        let previousFingerprints = indexedFingerprints
        let previousIDs = indexedRecipeIDs.union(previousFingerprints.keys)
        let currentIDs = Set(currentFingerprints.keys)
        let changedEntities = entities.filter {
            previousFingerprints[$0.id] != currentFingerprints[$0.id]
        }
        let removedIDs = previousIDs.subtracting(currentIDs)

        guard !changedEntities.isEmpty || !removedIDs.isEmpty || indexedOwnerID != ownerID else {
            return
        }

        // If the process exits or the account changes during either await, the
        // next run must clear the type before trusting persisted bookkeeping.
        cleanupRequired = true

        if !changedEntities.isEmpty {
            try await index.indexAppEntities(changedEntities)
            guard sessionMatches(ownerID) else {
                try await removeIndexAfterSessionChange()
                return
            }
        }

        if !removedIDs.isEmpty {
            try await index.deleteAppEntities(
                identifiedBy: Array(removedIDs),
                ofType: RecipeIntentEntity.self
            )
            guard sessionMatches(ownerID) else {
                try await removeIndexAfterSessionChange()
                return
            }
        }

        indexedRecipeIDs = currentIDs
        indexedFingerprints = currentFingerprints
        indexedOwnerID = ownerID
        cleanupRequired = false
    }

    private func enforceAccountBoundary(expectedOwnerID: UUID?) async throws {
        let hasLegacyState = indexedOwnerID == nil &&
            (!indexedRecipeIDs.isEmpty || !indexedFingerprints.isEmpty)
        let ownerChanged = indexedOwnerID != nil && indexedOwnerID != expectedOwnerID
        let signedOutWithIndexedData = expectedOwnerID == nil &&
            (!indexedRecipeIDs.isEmpty || !indexedFingerprints.isEmpty)

        guard cleanupRequired || hasLegacyState || ownerChanged || signedOutWithIndexedData else {
            return
        }

        cleanupRequired = true
        try await index.deleteAppEntities(ofType: RecipeIntentEntity.self)
        clearPersistedIndexState()
    }

    private func removeIndexAfterSessionChange() async throws {
        try await invalidatePriorAccountIndexIfNeeded()
    }

    private func invalidatePriorAccountIndexIfNeeded() async throws {
        let hasPersistedIndexState = indexedOwnerID != nil ||
            !indexedRecipeIDs.isEmpty ||
            !indexedFingerprints.isEmpty
        guard cleanupRequired || hasPersistedIndexState else { return }

        cleanupRequired = true
        try await index.deleteAppEntities(ofType: RecipeIntentEntity.self)
        clearPersistedIndexState()
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        guard let delay = retryPolicy.nextDelayAfterFailure() else {
            AppLogger.general.error("Recipe Spotlight reconciliation retry limit reached")
            return
        }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            guard let self else { return }
            self.enqueue(
                .full(ownerID: CurrentUserSession.shared.userId, recipes: nil),
                origin: .retry
            )
        }
    }

    private func resetRetryBudget() {
        retryTask?.cancel()
        retryTask = nil
        retryPolicy.reset()
    }

    private func sessionMatches(_ ownerID: UUID?) -> Bool {
        CurrentUserSession.shared.isAccountIdentityVerified &&
            CurrentUserSession.shared.userId == ownerID
    }

    private func clearPersistedIndexState() {
        indexedRecipeIDs = []
        indexedFingerprints = [:]
        indexedOwnerID = nil
        cleanupRequired = false
    }

    nonisolated static func fingerprint(for entity: RecipeIntentEntity) -> String {
        let fields = [
            entity.id.uuidString,
            entity.title,
            entity.ingredientNames.joined(separator: "\u{1F}"),
            entity.instructions,
            entity.totalMinutes.map(String.init) ?? "",
            entity.tagNames.joined(separator: "\u{1F}"),
            entity.isFavorite ? "1" : "0",
            entity.recipeYield,
            String(entity.updatedAt.timeIntervalSinceReferenceDate.bitPattern),
            String(entity.createdAt.timeIntervalSinceReferenceDate.bitPattern),
            entity.creatorName ?? "",
            entity.notes ?? ""
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "\u{1E}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private var indexedRecipeIDs: Set<UUID> {
        get {
            let values = defaults?.stringArray(forKey: Self.indexedRecipeIDsKey) ?? []
            return Set(values.compactMap(UUID.init(uuidString:)))
        }
        set {
            defaults?.set(newValue.map(\.uuidString).sorted(), forKey: Self.indexedRecipeIDsKey)
        }
    }

    private var indexedOwnerID: UUID? {
        get {
            defaults?.string(forKey: Self.indexedOwnerIDKey).flatMap(UUID.init(uuidString:))
        }
        set {
            defaults?.set(newValue?.uuidString, forKey: Self.indexedOwnerIDKey)
        }
    }

    private var indexedFingerprints: [UUID: String] {
        get {
            guard let values = defaults?.dictionary(forKey: Self.indexedFingerprintsKey) as? [String: String] else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
                UUID(uuidString: key).map { ($0, value) }
            })
        }
        set {
            let values = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value) })
            defaults?.set(values, forKey: Self.indexedFingerprintsKey)
        }
    }

    private var cleanupRequired: Bool {
        get { defaults?.bool(forKey: Self.cleanupRequiredKey) ?? false }
        set { defaults?.set(newValue, forKey: Self.cleanupRequiredKey) }
    }
}
