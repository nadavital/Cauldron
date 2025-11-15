//
//  DeletedRecipeRepositoryTests.swift
//  CauldronTests
//
//  Created on November 13, 2025.
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class DeletedRecipeRepositoryTests: XCTestCase {

    var repository: DeletedRecipeRepository!
    var modelContainer: ModelContainer!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        modelContainer = try TestModelContainer.create(with: [DeletedRecipeModel.self])

        // Initialize repository
        repository = DeletedRecipeRepository(modelContainer: modelContainer)
    }

    override func tearDown() async throws {
        repository = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Mark as Deleted Tests

    func testMarkAsDeleted_CreatesTombstone() async throws {
        // Given
        let recipeId = UUID()
        let cloudRecordName = "test-recipe-123"

        // When
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: cloudRecordName)

        // Then
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted)
    }

    func testMarkAsDeleted_WithNilCloudRecordName() async throws {
        // Given
        let recipeId = UUID()

        // When
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: nil)

        // Then
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted)
    }

    func testMarkAsDeleted_DuplicateCall_DoesNotCreateDuplicate() async throws {
        // Given
        let recipeId = UUID()
        let cloudRecordName = "test-recipe-123"

        // When
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: cloudRecordName)
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: cloudRecordName)

        // Then
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()
        let count = deletedIds.filter { $0 == recipeId }.count
        XCTAssertEqual(count, 1, "Should only have one tombstone for the recipe")
    }

    func testMarkAsDeleted_MultipleRecipes() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let recipeId3 = UUID()

        // When
        try await repository.markAsDeleted(recipeId: recipeId1, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId2, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId3, cloudRecordName: nil)

        // Then
        let isDeleted1 = try await repository.isDeleted(recipeId: recipeId1)
        let isDeleted2 = try await repository.isDeleted(recipeId: recipeId2)
        let isDeleted3 = try await repository.isDeleted(recipeId: recipeId3)
        XCTAssertTrue(isDeleted1)
        XCTAssertTrue(isDeleted2)
        XCTAssertTrue(isDeleted3)

        let deletedIds = try await repository.fetchAllDeletedRecipeIds()
        XCTAssertEqual(deletedIds.count, 3)
    }

    // MARK: - Is Deleted Tests

    func testIsDeleted_ReturnsTrueForDeletedRecipe() async throws {
        // Given
        let recipeId = UUID()
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: nil)

        // When
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)

        // Then
        XCTAssertTrue(isDeleted)
    }

    func testIsDeleted_ReturnsFalseForNonDeletedRecipe() async throws {
        // Given
        let recipeId = UUID()

        // When
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)

        // Then
        XCTAssertFalse(isDeleted)
    }

    func testIsDeleted_AfterUnmark_ReturnsFalse() async throws {
        // Given
        let recipeId = UUID()
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: nil)

        // When
        try await repository.unmarkAsDeleted(recipeId: recipeId)

        // Then
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertFalse(isDeleted)
    }

    // MARK: - Unmark as Deleted Tests

    func testUnmarkAsDeleted_RemovesTombstone() async throws {
        // Given
        let recipeId = UUID()
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: nil)

        // When
        try await repository.unmarkAsDeleted(recipeId: recipeId)

        // Then
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertFalse(isDeleted)

        let deletedIds = try await repository.fetchAllDeletedRecipeIds()
        XCTAssertFalse(deletedIds.contains(recipeId))
    }

    func testUnmarkAsDeleted_NonExistentRecipe_DoesNotThrow() async throws {
        // Given
        let recipeId = UUID()

        // When/Then - Should not throw
        try await repository.unmarkAsDeleted(recipeId: recipeId)
    }

    func testUnmarkAsDeleted_RemovesOnlySpecifiedRecipe() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let recipeId3 = UUID()
        try await repository.markAsDeleted(recipeId: recipeId1, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId2, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId3, cloudRecordName: nil)

        // When
        try await repository.unmarkAsDeleted(recipeId: recipeId2)

        // Then
        let isDeleted1 = try await repository.isDeleted(recipeId: recipeId1)
        let isDeleted2 = try await repository.isDeleted(recipeId: recipeId2)
        let isDeleted3 = try await repository.isDeleted(recipeId: recipeId3)
        XCTAssertTrue(isDeleted1)
        XCTAssertFalse(isDeleted2)
        XCTAssertTrue(isDeleted3)
    }

    // MARK: - Cleanup Old Tombstones Tests

    func testCleanupOldTombstones_RemovesOldTombstones() async throws {
        // Given - Create a tombstone with a very old date
        let oldRecipeId = UUID()
        let context = ModelContext(modelContainer)

        let oldDate = Date().addingTimeInterval(-31 * 24 * 60 * 60) // 31 days ago
        let oldTombstone = DeletedRecipeModel(
            recipeId: oldRecipeId,
            deletedAt: oldDate,
            cloudRecordName: nil
        )
        context.insert(oldTombstone)
        try context.save()

        // Create a recent tombstone
        let recentRecipeId = UUID()
        try await repository.markAsDeleted(recipeId: recentRecipeId, cloudRecordName: nil)

        // When
        try await repository.cleanupOldTombstones()

        // Then
        let oldIsDeleted = try await repository.isDeleted(recipeId: oldRecipeId)
        let recentIsDeleted = try await repository.isDeleted(recipeId: recentRecipeId)
        XCTAssertFalse(oldIsDeleted, "Old tombstone should be removed")
        XCTAssertTrue(recentIsDeleted, "Recent tombstone should remain")
    }

    func testCleanupOldTombstones_KeepsRecentTombstones() async throws {
        // Given
        let recipeId = UUID()
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: nil)

        // When
        try await repository.cleanupOldTombstones()

        // Then
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted, "Recent tombstone should not be removed")
    }

    func testCleanupOldTombstones_WithNoTombstones_DoesNotThrow() async throws {
        // When/Then - Should not throw
        try await repository.cleanupOldTombstones()

        // Verify no tombstones exist
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()
        XCTAssertEqual(deletedIds.count, 0)
    }

    func testCleanupOldTombstones_ExactlyThirtyDaysOld_IsKept() async throws {
        // Given - Create tombstone exactly 30 days old (minus 1 second to avoid timing edge case)
        let recipeId = UUID()
        let context = ModelContext(modelContainer)

        // Use 30 days minus 1 second to ensure we're safely within the 30-day window
        let thirtyDaysAgo = Date().addingTimeInterval((-30 * 24 * 60 * 60) + 1)
        let tombstone = DeletedRecipeModel(
            recipeId: recipeId,
            deletedAt: thirtyDaysAgo,
            cloudRecordName: nil
        )
        context.insert(tombstone)
        try context.save()

        // When
        try await repository.cleanupOldTombstones()

        // Then - 30 days is NOT older than 30 days, so it should be kept
        let isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted, "Exactly 30-day-old tombstone should be kept")
    }

    // MARK: - Fetch All Deleted Recipe IDs Tests

    func testFetchAllDeletedRecipeIds_EmptyList() async throws {
        // When
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()

        // Then
        XCTAssertEqual(deletedIds.count, 0)
    }

    func testFetchAllDeletedRecipeIds_ReturnsAllIds() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()
        let recipeId3 = UUID()

        try await repository.markAsDeleted(recipeId: recipeId1, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId2, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId3, cloudRecordName: nil)

        // When
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()

        // Then
        XCTAssertEqual(deletedIds.count, 3)
        XCTAssertTrue(deletedIds.contains(recipeId1))
        XCTAssertTrue(deletedIds.contains(recipeId2))
        XCTAssertTrue(deletedIds.contains(recipeId3))
    }

    func testFetchAllDeletedRecipeIds_AfterUnmark_DoesNotIncludeUnmarked() async throws {
        // Given
        let recipeId1 = UUID()
        let recipeId2 = UUID()

        try await repository.markAsDeleted(recipeId: recipeId1, cloudRecordName: nil)
        try await repository.markAsDeleted(recipeId: recipeId2, cloudRecordName: nil)
        try await repository.unmarkAsDeleted(recipeId: recipeId1)

        // When
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()

        // Then
        XCTAssertEqual(deletedIds.count, 1)
        XCTAssertFalse(deletedIds.contains(recipeId1))
        XCTAssertTrue(deletedIds.contains(recipeId2))
    }

    // MARK: - Integration Tests

    func testFullWorkflow_MarkUnmarkMark() async throws {
        // Given
        let recipeId = UUID()

        // Mark as deleted
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: "record-1")
        var isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted)

        // Unmark (user re-adds recipe)
        try await repository.unmarkAsDeleted(recipeId: recipeId)
        isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertFalse(isDeleted)

        // Mark as deleted again
        try await repository.markAsDeleted(recipeId: recipeId, cloudRecordName: "record-2")
        isDeleted = try await repository.isDeleted(recipeId: recipeId)
        XCTAssertTrue(isDeleted)

        // Verify only one tombstone exists
        let deletedIds = try await repository.fetchAllDeletedRecipeIds()
        let count = deletedIds.filter { $0 == recipeId }.count
        XCTAssertEqual(count, 1)
    }
}
