//
//  RecipeCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class RecipeCloudServiceRecordMappingTests: XCTestCase {
    func testPrivateRecipeRecordIDUsesCustomZone() {
        let zoneID = CKRecordZone.ID(zoneName: "CauldronCustomZone", ownerName: CKCurrentUserDefaultName)
        let recordID = RecipeCloudService.privateRecipeRecordID(
            recordName: "recipe-record",
            zoneID: zoneID
        )

        XCTAssertEqual(recordID.recordName, "recipe-record")
        XCTAssertEqual(recordID.zoneID.zoneName, "CauldronCustomZone")
        XCTAssertEqual(recordID.zoneID.ownerName, CKCurrentUserDefaultName)
    }

    func testPopulateAndDecodeRecipeRecordPreservesSourceLineageAndPreviewState() async throws {
        let service = RecipeCloudService(core: CloudKitCore())
        let ownerId = UUID()
        let sourceId = UUID()
        let creatorId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let createdAt = Date(timeIntervalSince1970: 1_699_999_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let relatedId = UUID()
        let recipeId = UUID()
        let recipe = Recipe(
            id: recipeId,
            title: "Lemon Pasta",
            ingredients: [Ingredient(name: "Lemon zest", quantity: Quantity(value: 2, unit: .tablespoon))],
            steps: [CookStep(index: 0, text: "Toss pasta with lemon.", timers: [])],
            yields: "2 servings",
            totalMinutes: 18,
            tags: [Tag(name: "Weeknight Dinner")],
            nutrition: nil,
            sourceURL: URL(string: "https://example.com/lemon-pasta"),
            sourceTitle: "Example Lemon Pasta",
            notes: "Use extra lemon.",
            imageURL: nil,
            isFavorite: true,
            visibility: .publicRecipe,
            ownerId: ownerId,
            cloudRecordName: "cloud-\(recipeId.uuidString)",
            cloudImageRecordName: "image-record",
            imageModifiedAt: sourceUpdatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: sourceId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice",
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceUpdatedAt,
            followsSourceUpdates: true,
            relatedRecipeIds: [relatedId],
            isPreview: true
        )
        let cloudRecordName = "cloud-\(recipeId.uuidString)"
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.sharedRecipe,
            recordID: CKRecord.ID(recordName: cloudRecordName)
        )

        await service.populateRecipeRecord(record, from: recipe, ownerId: ownerId)
        let decoded = try await service.recipeFromRecord(record)
        let decodedId = decoded.id
        let decodedOwnerId = decoded.ownerId
        let decodedTitle = decoded.title
        let decodedIngredientNames = decoded.ingredients.map { $0.name }
        let decodedStepTexts = decoded.steps.map { $0.text }
        let decodedYields = decoded.yields
        let decodedTotalMinutes = decoded.totalMinutes
        let decodedTagNames = decoded.tags.map { $0.name }
        let decodedNotes = decoded.notes
        let decodedVisibility = decoded.visibility
        let decodedCloudRecordName = decoded.cloudRecordName
        let decodedOriginalRecipeId = decoded.originalRecipeId
        let decodedOriginalCreatorId = decoded.originalCreatorId
        let decodedOriginalCreatorName = decoded.originalCreatorName
        let decodedSavedAt = decoded.savedAt
        let decodedSourceRecipeUpdatedAt = decoded.sourceRecipeUpdatedAt
        let decodedFollowsSourceUpdates = decoded.followsSourceUpdates
        let decodedRelatedRecipeIds = decoded.relatedRecipeIds
        let decodedIsPreview = decoded.isPreview

        XCTAssertEqual(decodedId, recipeId)
        XCTAssertEqual(decodedOwnerId, ownerId)
        XCTAssertEqual(decodedTitle, "Lemon Pasta")
        XCTAssertEqual(decodedIngredientNames, ["Lemon zest"])
        XCTAssertEqual(decodedStepTexts, ["Toss pasta with lemon."])
        XCTAssertEqual(decodedYields, "2 servings")
        XCTAssertEqual(decodedTotalMinutes, 18)
        XCTAssertEqual(decodedTagNames, ["Weeknight Dinner"])
        XCTAssertEqual(decodedNotes, "Use extra lemon.")
        XCTAssertEqual(decodedVisibility, .publicRecipe)
        XCTAssertEqual(decodedCloudRecordName, cloudRecordName)
        XCTAssertEqual(decodedOriginalRecipeId, sourceId)
        XCTAssertEqual(decodedOriginalCreatorId, creatorId)
        XCTAssertEqual(decodedOriginalCreatorName, "Alice")
        XCTAssertEqual(decodedSavedAt, savedAt)
        XCTAssertEqual(decodedSourceRecipeUpdatedAt, sourceUpdatedAt)
        XCTAssertTrue(decodedFollowsSourceUpdates)
        XCTAssertEqual(decodedRelatedRecipeIds, [relatedId])
        XCTAssertTrue(decodedIsPreview)
    }

    func testPopulateRecipeRecordClearsStaleOptionalFieldsOnExistingRecord() async {
        let service = RecipeCloudService(core: CloudKitCore())
        let ownerId = UUID()
        let staleSourceId = UUID()
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.recipe,
            recordID: CKRecord.ID(recordName: "recipe-record")
        )
        record["totalMinutes"] = 45 as CKRecordValue
        record["notes"] = "old notes" as CKRecordValue
        record["originalRecipeId"] = staleSourceId.uuidString as CKRecordValue
        record["originalCreatorId"] = UUID().uuidString as CKRecordValue
        record["originalCreatorName"] = "Old Creator" as CKRecordValue
        record["savedAt"] = Date(timeIntervalSince1970: 1_700_000_000) as CKRecordValue
        record["sourceRecipeUpdatedAt"] = Date(timeIntervalSince1970: 1_700_000_100) as CKRecordValue

        let localOnlyRecipe = Recipe(
            id: UUID(),
            title: "Plain Rice",
            ingredients: [Ingredient(name: "Rice", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook rice.", timers: [])],
            yields: "4 servings",
            totalMinutes: nil,
            tags: [],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .privateRecipe,
            ownerId: ownerId,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        await service.populateRecipeRecord(record, from: localOnlyRecipe, ownerId: ownerId)

        XCTAssertNil(record["totalMinutes"])
        XCTAssertNil(record["notes"])
        XCTAssertNil(record["originalRecipeId"])
        XCTAssertNil(record["originalCreatorId"])
        XCTAssertNil(record["originalCreatorName"])
        XCTAssertNil(record["savedAt"])
        XCTAssertNil(record["sourceRecipeUpdatedAt"])
        XCTAssertEqual(record["followsSourceUpdates"] as? Int64, 0)
    }

    func testDecodeLegacyCloudRecordTreatsSavedCopyWithoutSourceSnapshotAsFollowing() async throws {
        let service = RecipeCloudService(core: CloudKitCore())
        let record = makeRequiredRecipeRecord()
        let sourceId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        record["originalRecipeId"] = sourceId.uuidString as CKRecordValue
        record["savedAt"] = savedAt as CKRecordValue
        record["followsSourceUpdates"] = 0 as CKRecordValue

        let decoded = try await service.recipeFromRecord(record)
        let decodedOriginalRecipeId = decoded.originalRecipeId
        let decodedSavedAt = decoded.savedAt
        let decodedSourceRecipeUpdatedAt = decoded.sourceRecipeUpdatedAt
        let decodedFollowsSourceUpdates = decoded.followsSourceUpdates
        let decodedRequiresMigration = decoded.requiresLegacySourceTrackingMigration

        XCTAssertEqual(decodedOriginalRecipeId, sourceId)
        XCTAssertEqual(decodedSavedAt, savedAt)
        XCTAssertNil(decodedSourceRecipeUpdatedAt)
        XCTAssertTrue(decodedFollowsSourceUpdates)
        XCTAssertTrue(decodedRequiresMigration)
    }

    func testDecodeLegacyBooleanFollowsSourceUpdatesField() async throws {
        let service = RecipeCloudService(core: CloudKitCore())
        let record = makeRequiredRecipeRecord()
        record["originalRecipeId"] = UUID().uuidString as CKRecordValue
        record["sourceRecipeUpdatedAt"] = Date(timeIntervalSince1970: 1_700_000_100) as CKRecordValue
        record["followsSourceUpdates"] = true as CKRecordValue

        let decoded = try await service.recipeFromRecord(record)

        XCTAssertTrue(decoded.followsSourceUpdates)
    }

    func testPopulateRecipeRecordWritesTokenizedSearchFieldsForCloudKitQueries() async {
        let service = RecipeCloudService(core: CloudKitCore())
        let ownerId = UUID()
        let recipe = Recipe(
            id: UUID(),
            title: "Sheet-Pan Lemon Chicken",
            ingredients: [
                Ingredient(name: "Chicken thighs", quantity: nil),
                Ingredient(name: "Fresh lemon juice", quantity: nil)
            ],
            steps: [CookStep(index: 0, text: "Roast until done.", timers: [])],
            yields: "4 servings",
            tags: [Tag(name: "High Protein"), Tag(name: "Weeknight Dinner")],
            ownerId: ownerId
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.sharedRecipe,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )

        await service.populateRecipeRecord(record, from: recipe, ownerId: ownerId)

        XCTAssertEqual(record["searchableTags"] as? [String], ["dinner", "high", "protein", "weeknight"])
        XCTAssertEqual(record["searchableTitleTerms"] as? [String], ["chicken", "lemon", "pan", "sheet"])
        XCTAssertEqual(record["searchableIngredients"] as? [String], ["chicken", "fresh", "juice", "lemon", "thighs"])
    }

    func testUpdateSearchMetadataFieldsBackfillsStaleSearchTerms() async throws {
        let service = RecipeCloudService(core: CloudKitCore())
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.sharedRecipe,
            recordID: CKRecord.ID(recordName: UUID().uuidString)
        )
        let encoder = JSONEncoder()
        record["title"] = "Sheet-Pan Lemon Chicken" as CKRecordValue
        record["tagsData"] = try encoder.encode([
            Tag(name: "High Protein"),
            Tag(name: "Weeknight Dinner")
        ]) as CKRecordValue
        record["ingredientsData"] = try encoder.encode([
            Ingredient(name: "Chicken thighs", quantity: nil),
            Ingredient(name: "Fresh lemon juice", quantity: nil)
        ]) as CKRecordValue
        record["searchableTags"] = ["old"] as CKRecordValue
        record["searchableTitleTerms"] = ["old"] as CKRecordValue
        record["searchableIngredients"] = ["old"] as CKRecordValue

        let didUpdate = service.updateSearchMetadataFields(on: record)

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(record["searchableTags"] as? [String], ["dinner", "high", "protein", "weeknight"])
        XCTAssertEqual(record["searchableTitleTerms"] as? [String], ["chicken", "lemon", "pan", "sheet"])
        XCTAssertEqual(record["searchableIngredients"] as? [String], ["chicken", "fresh", "juice", "lemon", "thighs"])

        let secondUpdate = service.updateSearchMetadataFields(on: record)

        XCTAssertFalse(secondUpdate)
    }

    func testRecipeSummaryFromRecordPreservesBrowsingFieldsWithoutSteps() async throws {
        let service = RecipeCloudService(core: CloudKitCore())
        let ownerId = UUID()
        let sourceId = UUID()
        let recipe = Recipe(
            id: UUID(),
            title: "Tomato Toast",
            ingredients: [Ingredient(name: "Tomato", quantity: nil)],
            steps: [CookStep(index: 0, text: "Toast bread.", timers: [])],
            yields: "1 serving",
            totalMinutes: 8,
            tags: [Tag(name: "Breakfast")],
            visibility: .publicRecipe,
            ownerId: ownerId,
            originalRecipeId: sourceId,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            followsSourceUpdates: true,
            relatedRecipeIds: [UUID()]
        )
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.sharedRecipe,
            recordID: CKRecord.ID(recordName: recipe.id.uuidString)
        )

        await service.populateRecipeRecord(record, from: recipe, ownerId: ownerId)
        let summary = try await service.recipeSummaryFromRecord(record)
        let preview = summary.previewRecipe

        XCTAssertEqual(summary.id, recipe.id)
        XCTAssertEqual(summary.title, "Tomato Toast")
        XCTAssertEqual(summary.ownerId, ownerId)
        XCTAssertEqual(summary.originalRecipeId, sourceId)
        XCTAssertEqual(summary.ingredients.map(\.name), ["Tomato"])
        XCTAssertEqual(summary.tags.map(\.name), ["Breakfast"])
        XCTAssertEqual(summary.totalMinutes, 8)
        XCTAssertEqual(summary.relatedRecipeIds, recipe.relatedRecipeIds)
        XCTAssertTrue(summary.followsSourceUpdates)
        XCTAssertTrue(summary.isFollowingSourceUpdates)
        XCTAssertEqual(preview.id, summary.id)
        XCTAssertEqual(preview.title, summary.title)
        XCTAssertTrue(preview.steps.isEmpty)
    }

    private func makeRequiredRecipeRecord() -> CKRecord {
        let recipeId = UUID()
        let ownerId = UUID()
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.recipe,
            recordID: CKRecord.ID(recordName: recipeId.uuidString)
        )
        record["recipeId"] = recipeId.uuidString as CKRecordValue
        record["ownerId"] = ownerId.uuidString as CKRecordValue
        record["title"] = "Legacy Saved Pasta" as CKRecordValue
        record["visibility"] = RecipeVisibility.publicRecipe.rawValue as CKRecordValue
        record["createdAt"] = Date(timeIntervalSince1970: 1_699_999_000) as CKRecordValue
        record["updatedAt"] = Date(timeIntervalSince1970: 1_700_000_100) as CKRecordValue
        return record
    }
}
