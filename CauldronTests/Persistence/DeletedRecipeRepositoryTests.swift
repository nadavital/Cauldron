//
//  DeletedRecipeRepositoryTests.swift
//  CauldronTests
//

import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class DeletedRecipeRepositoryTests: XCTestCase {
    private var repository: DeletedRecipeRepository!
    private var modelContainer: ModelContainer!
    private var ownerId: UUID!

    override func setUp() async throws {
        try await super.setUp()
        modelContainer = try TestModelContainer.create(with: [DeletedRecipeModel.self])
        repository = DeletedRecipeRepository(modelContainer: modelContainer)
        ownerId = UUID()
    }

    override func tearDown() async throws {
        ownerId = nil
        repository = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testMarkAsDeletedCreatesOneOwnerScopedTombstoneAndKeepsNewestMetadata() async throws {
        let recipeId = UUID()
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_700_000_500)

        try await repository.markAsDeleted(
            recipeId: recipeId,
            ownerId: ownerId,
            cloudRecordName: "private-record",
            deletedAt: olderDate
        )
        try await repository.markAsDeleted(
            recipeId: recipeId,
            ownerId: ownerId,
            cloudRecordName: nil,
            deletedAt: newerDate
        )

        let tombstones = try ModelContext(modelContainer).fetch(FetchDescriptor<DeletedRecipeModel>())
        XCTAssertEqual(tombstones.count, 1)
        XCTAssertEqual(tombstones.first?.recipeId, recipeId)
        XCTAssertEqual(tombstones.first?.ownerId, ownerId)
        XCTAssertEqual(tombstones.first?.deletedAt, newerDate)
        XCTAssertEqual(tombstones.first?.cloudRecordName, "private-record")
    }

    func testSameRecipeIdIsIndependentAcrossOwners() async throws {
        let recipeId = UUID()
        let otherOwnerId = UUID()
        try await repository.markAsDeleted(
            recipeId: recipeId,
            ownerId: ownerId,
            cloudRecordName: "owner-a"
        )
        try await repository.markAsDeleted(
            recipeId: recipeId,
            ownerId: otherOwnerId,
            cloudRecordName: "owner-b"
        )

        let ownerAInitiallyDeleted = try await repository.isDeleted(recipeId: recipeId, ownerId: ownerId)
        let ownerBInitiallyDeleted = try await repository.isDeleted(recipeId: recipeId, ownerId: otherOwnerId)
        XCTAssertTrue(ownerAInitiallyDeleted)
        XCTAssertTrue(ownerBInitiallyDeleted)

        try await repository.unmarkAsDeleted(recipeId: recipeId, ownerId: ownerId)

        let ownerADeleted = try await repository.isDeleted(recipeId: recipeId, ownerId: ownerId)
        let ownerBDeleted = try await repository.isDeleted(recipeId: recipeId, ownerId: otherOwnerId)
        let ownerBDeletedIDs = try await repository.fetchAllDeletedRecipeIds(ownerId: otherOwnerId)
        XCTAssertFalse(ownerADeleted)
        XCTAssertTrue(ownerBDeleted)
        XCTAssertEqual(ownerBDeletedIDs, [recipeId])
    }

    func testFetchAndUnmarkAffectOnlyRequestedRecipeForOwner() async throws {
        let recipeIds = [UUID(), UUID(), UUID()]
        for recipeId in recipeIds {
            try await repository.markAsDeleted(
                recipeId: recipeId,
                ownerId: ownerId,
                cloudRecordName: nil
            )
        }

        try await repository.unmarkAsDeleted(recipeId: recipeIds[1], ownerId: ownerId)

        let remaining = Set(try await repository.fetchAllDeletedRecipeIds(ownerId: ownerId))
        XCTAssertEqual(remaining, [recipeIds[0], recipeIds[2]])
        let removedRecipeIsDeleted = try await repository.isDeleted(
            recipeId: recipeIds[1],
            ownerId: ownerId
        )
        XCTAssertFalse(removedRecipeIsDeleted)
    }

    func testCleanupOldTombstonesDoesNotDeleteAnotherOwnersRows() async throws {
        let oldRecipeId = UUID()
        let recentRecipeId = UUID()
        let otherOwnerId = UUID()
        let context = ModelContext(modelContainer)
        context.insert(DeletedRecipeModel(
            recipeId: oldRecipeId,
            ownerId: ownerId,
            deletedAt: Date().addingTimeInterval(-31 * 24 * 60 * 60),
            cloudRecordName: nil
        ))
        context.insert(DeletedRecipeModel(
            recipeId: oldRecipeId,
            ownerId: otherOwnerId,
            deletedAt: Date().addingTimeInterval(-31 * 24 * 60 * 60),
            cloudRecordName: nil
        ))
        context.insert(DeletedRecipeModel(
            recipeId: recentRecipeId,
            ownerId: ownerId,
            deletedAt: Date().addingTimeInterval((-30 * 24 * 60 * 60) + 2),
            cloudRecordName: nil
        ))
        try context.save()

        try await repository.cleanupOldTombstones(ownerId: ownerId)

        let ownerAOldDeleted = try await repository.isDeleted(recipeId: oldRecipeId, ownerId: ownerId)
        let ownerBOldDeleted = try await repository.isDeleted(recipeId: oldRecipeId, ownerId: otherOwnerId)
        let ownerARecentDeleted = try await repository.isDeleted(recipeId: recentRecipeId, ownerId: ownerId)
        XCTAssertFalse(ownerAOldDeleted)
        XCTAssertTrue(ownerBOldDeleted)
        XCTAssertTrue(ownerARecentDeleted)
    }

    func testLegacyOwnerlessMigrationRunsOnceAndCannotBeReadByNextAccount() async throws {
        let recipeId = UUID()
        let context = ModelContext(modelContainer)
        context.insert(DeletedRecipeModel(
            recipeId: recipeId,
            deletedAt: Date(),
            cloudRecordName: "legacy"
        ))
        try context.save()
        let defaults = try makeDefaults()

        try await repository.migrateLegacyOwnerlessTombstones(to: ownerId, defaults: defaults)
        try await repository.migrateLegacyOwnerlessTombstones(to: UUID(), defaults: defaults)

        let isDeletedByMigratedOwner = try await repository.isDeleted(recipeId: recipeId, ownerId: ownerId)
        XCTAssertTrue(isDeletedByMigratedOwner)
        XCTAssertEqual(
            defaults.integer(forKey: DeletedRecipeRepository.legacyOwnerMigrationVersionKey),
            DeletedRecipeRepository.legacyOwnerMigrationVersion
        )
        XCTAssertEqual(
            defaults.string(forKey: DeletedRecipeRepository.legacyOwnerMigrationOwnerKey),
            ownerId.uuidString
        )
    }

    func testLegacyMigrationCoalescesOwnerlessAndAlreadyOwnedDuplicates() async throws {
        let recipeId = UUID()
        let olderDate = Date(timeIntervalSince1970: 100)
        let newerDate = Date(timeIntervalSince1970: 200)
        let context = ModelContext(modelContainer)
        context.insert(DeletedRecipeModel(
            recipeId: recipeId,
            ownerId: ownerId,
            deletedAt: olderDate,
            cloudRecordName: "owned"
        ))
        context.insert(DeletedRecipeModel(
            recipeId: recipeId,
            deletedAt: newerDate,
            cloudRecordName: "legacy"
        ))
        try context.save()

        try await repository.migrateLegacyOwnerlessTombstones(
            to: ownerId,
            defaults: try makeDefaults()
        )

        let rows = try ModelContext(modelContainer).fetch(FetchDescriptor<DeletedRecipeModel>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.ownerId, ownerId)
        XCTAssertEqual(rows.first?.deletedAt, newerDate)
        XCTAssertEqual(rows.first?.cloudRecordName, "owned")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "DeletedRecipeRepositoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
