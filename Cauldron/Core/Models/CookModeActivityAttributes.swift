//
//  CookModeActivityAttributes.swift
//  Cauldron
//
//  Created for Live Activities support
//

import Foundation
import Darwin

nonisolated struct CookSessionSharedSnapshot: Codable, Sendable, Equatable {
    var recipeID: UUID
    var ownerID: UUID?
    var stepIndex: Int
    var totalSteps: Int
    var sessionStartTime: Date
    var revision: Int
    var updatedAt: Date
    var stepInstructions: [String]?

    nonisolated init(
        recipeID: UUID,
        ownerID: UUID? = nil,
        stepIndex: Int,
        totalSteps: Int,
        sessionStartTime: Date,
        revision: Int = 0,
        updatedAt: Date = Date(),
        stepInstructions: [String]? = nil
    ) {
        self.recipeID = recipeID
        self.ownerID = ownerID
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.sessionStartTime = sessionStartTime
        self.revision = revision
        self.updatedAt = updatedAt
        self.stepInstructions = stepInstructions
    }

    nonisolated func belongs(to userID: UUID) -> Bool {
        ownerID == userID
    }
}

enum CookSessionSharedStore {
    nonisolated static let appGroupID = "group.Nadav.Cauldron"
    nonisolated private static let snapshotKey = "activeCookSession.snapshot.v1"
    nonisolated private static let snapshotFilename = "CookSessionState.v1.json"

    nonisolated static func read(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) -> CookSessionSharedSnapshot? {
        withExclusiveLock {
            readUnlocked(defaults: defaults, usesFileAuthority: true)
        }
    }

    nonisolated static func readForTesting(defaults: UserDefaults?) -> CookSessionSharedSnapshot? {
        withExclusiveLock { readUnlocked(defaults: defaults, usesFileAuthority: false) }
    }

    nonisolated static func save(
        _ snapshot: CookSessionSharedSnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)
    ) {
        withExclusiveLock {
            saveUnlocked(snapshot, defaults: defaults, usesFileAuthority: true)
        }
    }

    nonisolated static func saveForTesting(_ snapshot: CookSessionSharedSnapshot, defaults: UserDefaults?) {
        withExclusiveLock { saveUnlocked(snapshot, defaults: defaults, usesFileAuthority: false) }
    }

    /// Atomically creates or refreshes a session. For the same recipe it
    /// preserves any newer cross-process step while updating bounds and text.
    @discardableResult
    nonisolated static func synchronizeSession(
        recipeID: UUID,
        ownerID: UUID?,
        preferredStep: Int,
        totalSteps: Int,
        sessionStartTime: Date,
        stepInstructions: [String],
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        now: Date = Date()
    ) -> CookSessionSharedSnapshot? {
        guard totalSteps > 0 else { return nil }
        return withExclusiveLock {
            let existing = readUnlocked(defaults: defaults, usesFileAuthority: true)
            let isSameSession = existing?.recipeID == recipeID
                && existing?.ownerID == ownerID
                && existing?.sessionStartTime == sessionStartTime
            let step = isSameSession ? existing?.stepIndex ?? preferredStep : preferredStep
            let revision = isSameSession ? existing?.revision ?? 0 : 0
            let snapshot = CookSessionSharedSnapshot(
                recipeID: recipeID,
                ownerID: ownerID,
                stepIndex: min(max(step, 0), totalSteps - 1),
                totalSteps: totalSteps,
                sessionStartTime: isSameSession
                    ? existing?.sessionStartTime ?? sessionStartTime
                    : sessionStartTime,
                revision: revision,
                updatedAt: now,
                stepInstructions: stepInstructions
            )
            saveUnlocked(snapshot, defaults: defaults, usesFileAuthority: true)
            return snapshot
        }
    }

    nonisolated static func clear(defaults: UserDefaults? = UserDefaults(suiteName: appGroupID)) {
        withExclusiveLock {
            if let snapshotURL = snapshotFileURL() {
                try? FileManager.default.removeItem(at: snapshotURL)
            }
            defaults?.removeObject(forKey: snapshotKey)
        }
    }

    nonisolated static func clearForTesting(defaults: UserDefaults?) {
        withExclusiveLock { defaults?.removeObject(forKey: snapshotKey) }
    }

    @discardableResult
    nonisolated static func move(
        by delta: Int,
        expected: CookSessionSharedSnapshot? = nil,
        defaults: UserDefaults? = UserDefaults(suiteName: appGroupID),
        now: Date = Date()
    ) -> CookSessionSharedSnapshot? {
        withExclusiveLock {
            moveUnlocked(
                by: delta,
                expected: expected,
                defaults: defaults,
                usesFileAuthority: true,
                now: now
            )
        }
    }

    nonisolated static func moveForTesting(
        by delta: Int,
        expected: CookSessionSharedSnapshot? = nil,
        defaults: UserDefaults?,
        now: Date = Date()
    ) -> CookSessionSharedSnapshot? {
        withExclusiveLock {
            moveUnlocked(
                by: delta,
                expected: expected,
                defaults: defaults,
                usesFileAuthority: false,
                now: now
            )
        }
    }

    nonisolated private static func moveUnlocked(
        by delta: Int,
        expected: CookSessionSharedSnapshot?,
        defaults: UserDefaults?,
        usesFileAuthority: Bool,
        now: Date
    ) -> CookSessionSharedSnapshot? {
        guard var snapshot = readUnlocked(defaults: defaults, usesFileAuthority: usesFileAuthority) else { return nil }
        if let expected {
            guard snapshot.recipeID == expected.recipeID,
                  snapshot.ownerID == expected.ownerID,
                  snapshot.revision == expected.revision,
                  snapshot.sessionStartTime == expected.sessionStartTime else {
                return nil
            }
        }
        let next: Int
        if delta > 0 {
            next = snapshot.stepIndex >= snapshot.totalSteps - 1 ? snapshot.stepIndex : snapshot.stepIndex + 1
        } else if delta < 0 {
            next = snapshot.stepIndex <= 0 ? snapshot.stepIndex : snapshot.stepIndex - 1
        } else {
            next = snapshot.stepIndex
        }
        guard next != snapshot.stepIndex else { return snapshot }
        snapshot.stepIndex = next
        snapshot.revision = nextRevision(snapshot.revision)
        snapshot.updatedAt = now
        saveUnlocked(snapshot, defaults: defaults, usesFileAuthority: usesFileAuthority)
        return snapshot
    }

    nonisolated private static func nextRevision(_ revision: Int) -> Int {
        revision == .max ? 0 : revision + 1
    }

    nonisolated private static func readUnlocked(
        defaults: UserDefaults?,
        usesFileAuthority: Bool
    ) -> CookSessionSharedSnapshot? {
        let data = (usesFileAuthority ? snapshotFileURL().flatMap { try? Data(contentsOf: $0) } : nil)
            ?? defaults?.data(forKey: snapshotKey)
        guard let data,
              let snapshot = try? JSONDecoder().decode(CookSessionSharedSnapshot.self, from: data),
              snapshot.totalSteps > 0 else { return nil }
        guard snapshot.ownerID != nil else {
            if usesFileAuthority, let snapshotURL = snapshotFileURL() {
                try? FileManager.default.removeItem(at: snapshotURL)
            }
            defaults?.removeObject(forKey: snapshotKey)
            return nil
        }
        return normalized(snapshot)
    }

    nonisolated private static func saveUnlocked(
        _ snapshot: CookSessionSharedSnapshot,
        defaults: UserDefaults?,
        usesFileAuthority: Bool
    ) {
        guard snapshot.totalSteps > 0,
              snapshot.ownerID != nil,
              let data = try? JSONEncoder().encode(normalized(snapshot)) else { return }
        if usesFileAuthority, let snapshotURL = snapshotFileURL() {
            try? data.write(to: snapshotURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        }
        // Keep the legacy defaults mirror during migration, but production
        // reads use the lock-protected file to avoid cross-process caches.
        defaults?.set(data, forKey: snapshotKey)
    }

    nonisolated private static func snapshotFileURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    nonisolated private static func withExclusiveLock<T>(_ body: () -> T) -> T {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return body()
        }
        let lockURL = container.appendingPathComponent("CookSessionState.lock")
        let descriptor = lockURL.path.withCString {
            open($0, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else { return body() }
        flock(descriptor, LOCK_EX)
        defer {
            flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        return body()
    }

    nonisolated private static func normalized(
        _ snapshot: CookSessionSharedSnapshot
    ) -> CookSessionSharedSnapshot {
        var value = snapshot
        value.stepIndex = min(max(value.stepIndex, 0), max(value.totalSteps - 1, 0))
        return value
    }
}

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit

/// Attributes for the Cook Mode Live Activity
/// Defines the static and dynamic content shown on lock screen and Dynamic Island
nonisolated struct CookModeActivityAttributes: ActivityAttributes {
    /// Dynamic state that changes during cooking
    public struct ContentState: Codable, Hashable {
        /// Current step index (0-based)
        var currentStep: Int

        /// Total number of steps in recipe
        var totalSteps: Int

        /// Text of the current step instruction
        var stepInstruction: String

        /// Number of active timers currently running
        var activeTimerCount: Int

        /// Primary timer information (if any)
        var primaryTimerDurationSeconds: Int?
        var primaryTimerIsRunning: Bool

        /// Overall progress through the recipe (0.0 to 1.0)
        var progressPercentage: Double

        /// Timestamp of last update for sync verification
        var lastUpdated: Date
    }

    // MARK: - Static Attributes (Set Once)

    /// Unique identifier for the recipe
    var recipeId: String

    /// Name of the recipe being cooked
    var recipeName: String

    /// Emoji representing the recipe (optional)
    var recipeEmoji: String?

    /// Time when cooking session started
    var sessionStartTime: Date
}

enum CookSessionLiveActivityUpdater {
    static func update(from snapshot: CookSessionSharedSnapshot) async {
        while true {
            guard let candidate = CookSessionSharedStore.read(),
                  candidate.recipeID == snapshot.recipeID,
                  candidate.ownerID == snapshot.ownerID,
                  candidate.sessionStartTime == snapshot.sessionStartTime,
                  let activity = Activity<CookModeActivityAttributes>.activities.first(where: {
                $0.attributes.recipeId == candidate.recipeID.uuidString
                    && $0.attributes.sessionStartTime == candidate.sessionStartTime
            }) else { return }

            var state = activity.content.state
            state.currentStep = candidate.stepIndex
            state.totalSteps = candidate.totalSteps
            if let instructions = candidate.stepInstructions,
               instructions.indices.contains(candidate.stepIndex) {
                state.stepInstruction = instructions[candidate.stepIndex]
            }
            state.progressPercentage = Double(candidate.stepIndex + 1) / Double(candidate.totalSteps)
            state.lastUpdated = candidate.updatedAt
            await activity.update(.init(state: state, staleDate: nil))

            guard let latest = CookSessionSharedStore.read(),
                  latest.recipeID == candidate.recipeID,
                  latest.ownerID == candidate.ownerID,
                  latest.sessionStartTime == candidate.sessionStartTime else {
                return
            }
            if latest == candidate {
                return
            }
        }
    }
}
#endif
