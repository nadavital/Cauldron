//
//  CloudImageMigrationStatusTests.swift
//  CauldronTests
//
//  Tests for CloudImageMigration's completion-flag persistence semantics.
//
//  The fix gates the persisted "migration completed" flag on `failedCount == 0`
//  so a migration that had failures is NOT marked complete and will retry on the
//  next launch. The completion flag is read back into `migrationStatus` in
//  `init`, which is the observable contract we can verify without CloudKit.
//
//  The full failedCount-gating code path runs inside `performMigration()`, which
//  short-circuits to `.failed("CloudKit not available")` under the test runtime
//  (CloudKit is disabled when running tests) before ever reaching the gating
//  logic. So we cover the persisted-flag <-> status mapping and the retry reset
//  here, and SKIP exercising the live upload loop (see report).
//

import XCTest
@testable import Cauldron

@MainActor
final class CloudImageMigrationStatusTests: XCTestCase {

    private let completedKey = "com.cauldron.imageMigrationCompleted_v2"
    private let countKey = "com.cauldron.imageMigrationCount"

    private var savedCompleted: Any?
    private var savedCount: Any?

    override func setUp() {
        super.setUp()
        // Snapshot and clear the UserDefaults keys the migration touches so the
        // real app's migration state is preserved across the test run.
        savedCompleted = UserDefaults.standard.object(forKey: completedKey)
        savedCount = UserDefaults.standard.object(forKey: countKey)
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: countKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: countKey)
        if let savedCompleted { UserDefaults.standard.set(savedCompleted, forKey: completedKey) }
        if let savedCount { UserDefaults.standard.set(savedCount, forKey: countKey) }
        super.tearDown()
    }

    private func makeMigration() -> CloudImageMigration {
        let dependencies = DependencyContainer.preview()
        return CloudImageMigration(
            recipeRepository: dependencies.recipeRepository,
            imageManager: dependencies.imageManager,
            cloudKitCore: dependencies.cloudKitCore,
            recipeCloudService: dependencies.recipeCloudService,
            imageSyncManager: dependencies.imageSyncManager
        )
    }

    /// When the completion flag was NOT persisted (e.g. a prior run had failures
    /// and the flag was withheld), a freshly constructed migration must start in
    /// `.notStarted` so it will re-attempt.
    func testInitWithoutCompletedFlagIsNotStarted() async {
        let migration = makeMigration()
        let status = await migration.getStatus()
        XCTAssertEqual(status, .notStarted)
    }

    /// When the completion flag WAS persisted (failedCount == 0 path), a freshly
    /// constructed migration must report `.completed` with the persisted count
    /// and will skip re-running.
    func testInitWithCompletedFlagIsCompleted() async {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.set(7, forKey: countKey)

        let migration = makeMigration()
        let status = await migration.getStatus()
        XCTAssertEqual(status, .completed(migratedCount: 7))
    }

    /// Completed flag set but count missing falls back to 0 (no crash).
    func testInitWithCompletedFlagButNoCountDefaultsToZero() async {
        UserDefaults.standard.set(true, forKey: completedKey)

        let migration = makeMigration()
        let status = await migration.getStatus()
        XCTAssertEqual(status, .completed(migratedCount: 0))
    }

    /// retryMigration() clears the persisted completion flag so a previously
    /// "completed" migration can run again (used to recover from a bad migration).
    func testRetryMigrationClearsCompletedFlag() async {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.set(3, forKey: countKey)

        let migration = makeMigration()
        // Precondition.
        let before = await migration.getStatus()
        XCTAssertEqual(before, .completed(migratedCount: 3))

        await migration.retryMigration()

        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: completedKey),
            "retryMigration must clear the persisted completion flag"
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: countKey),
            "retryMigration must clear the persisted migrated count"
        )

        // Cancel the background task spawned by retry -> startMigration so it
        // can't mutate state after the test finishes.
        await migration.cancelMigration()
    }

    // MARK: - MigrationStatus value semantics

    func testMigrationStatusEqualityAndDescription() {
        XCTAssertEqual(MigrationStatus.notStarted, .notStarted)
        XCTAssertEqual(MigrationStatus.completed(migratedCount: 2), .completed(migratedCount: 2))
        XCTAssertNotEqual(MigrationStatus.completed(migratedCount: 2), .completed(migratedCount: 3))
        XCTAssertNotEqual(MigrationStatus.failed("a"), .failed("b"))

        XCTAssertTrue(MigrationStatus.inProgress(completed: 1, total: 3).isInProgress)
        XCTAssertFalse(MigrationStatus.completed(migratedCount: 1).isInProgress)
        XCTAssertEqual(MigrationStatus.inProgress(completed: 1, total: 3).description, "Migrating: 1/3")
    }
}
