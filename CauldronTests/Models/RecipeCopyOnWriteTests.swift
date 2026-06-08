//
//  RecipeCopyOnWriteTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class RecipeCopyOnWriteTests: XCTestCase {
    func testWithOwner_FromOriginalRecipe_CreatesFollowingSavedCopy() {
        let sourceId = UUID()
        let creatorId = UUID()
        let saverId = UUID()
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let original = makeRecipe(
            id: sourceId,
            title: "Lemon Pasta",
            ownerId: creatorId,
            updatedAt: sourceUpdatedAt,
            relatedRecipeIds: [UUID()]
        )

        let savedCopy = original.withOwner(
            saverId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice"
        )

        XCTAssertNotEqual(savedCopy.id, original.id)
        XCTAssertEqual(savedCopy.ownerId, saverId)
        XCTAssertEqual(savedCopy.originalRecipeId, sourceId)
        XCTAssertEqual(savedCopy.originalCreatorId, creatorId)
        XCTAssertEqual(savedCopy.originalCreatorName, "Alice")
        XCTAssertEqual(savedCopy.sourceRecipeUpdatedAt, sourceUpdatedAt)
        XCTAssertTrue(savedCopy.followsSourceUpdates)
        XCTAssertEqual(savedCopy.relatedRecipeIds, original.relatedRecipeIds)
        XCTAssertNotNil(savedCopy.savedAt)
    }

    func testWithOwner_FromFollowingSavedCopy_PreservesRootLineage() {
        let sourceId = UUID()
        let creatorId = UUID()
        let saverId = UUID()
        let secondSaverId = UUID()
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let original = makeRecipe(
            id: sourceId,
            title: "Tomato Soup",
            ownerId: creatorId,
            updatedAt: sourceUpdatedAt
        )

        let savedCopy = original.withOwner(
            saverId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice"
        )
        let resavedCopy = savedCopy.withOwner(secondSaverId)

        XCTAssertEqual(resavedCopy.ownerId, secondSaverId)
        XCTAssertEqual(resavedCopy.originalRecipeId, sourceId)
        XCTAssertEqual(resavedCopy.originalCreatorId, creatorId)
        XCTAssertEqual(resavedCopy.originalCreatorName, "Alice")
        XCTAssertEqual(resavedCopy.sourceRecipeUpdatedAt, sourceUpdatedAt)
        XCTAssertTrue(resavedCopy.followsSourceUpdates)
    }

    func testWithOwner_AllowsCanonicalRelatedIDsToOverrideRemappedCopies() {
        let sourceId = UUID()
        let creatorId = UUID()
        let saverId = UUID()
        let secondSaverId = UUID()
        let canonicalRelatedID = UUID()
        let remappedRelatedID = UUID()

        let original = makeRecipe(
            id: sourceId,
            title: "Tomato Soup",
            ownerId: creatorId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let savedCopy = Recipe(
            id: UUID(),
            title: original.title,
            ingredients: original.ingredients,
            steps: original.steps,
            yields: original.yields,
            totalMinutes: original.totalMinutes,
            tags: original.tags,
            nutrition: original.nutrition,
            sourceURL: original.sourceURL,
            sourceTitle: original.sourceTitle,
            notes: original.notes,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: saverId,
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: original.imageModifiedAt,
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            originalRecipeId: sourceId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice",
            savedAt: Date(timeIntervalSince1970: 1_700_000_150),
            sourceRecipeUpdatedAt: original.updatedAt,
            followsSourceUpdates: true,
            relatedRecipeIds: [remappedRelatedID]
        )

        let resavedCopy = savedCopy.withOwner(
            secondSaverId,
            relatedRecipeIds: [canonicalRelatedID]
        )

        XCTAssertEqual(resavedCopy.originalRecipeId, sourceId)
        XCTAssertEqual(resavedCopy.relatedRecipeIds, [canonicalRelatedID])
    }

    func testApplyingSourceSnapshot_UpdatesRecipeContentButPreservesUserState() {
        let sourceId = UUID()
        let creatorId = UUID()
        let saverId = UUID()
        let initialSourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let refreshedSourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let localImageURL = URL(fileURLWithPath: "/tmp/saved-copy.jpg")

        let original = makeRecipe(
            id: sourceId,
            title: "Old Chili",
            ownerId: creatorId,
            updatedAt: initialSourceUpdatedAt,
            notes: "Old notes"
        )
        let savedCopy = original.withOwner(
            saverId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice"
        )

        let locallyCustomized = Recipe(
            id: savedCopy.id,
            title: savedCopy.title,
            ingredients: savedCopy.ingredients,
            steps: savedCopy.steps,
            yields: savedCopy.yields,
            totalMinutes: savedCopy.totalMinutes,
            tags: savedCopy.tags,
            nutrition: savedCopy.nutrition,
            sourceURL: savedCopy.sourceURL,
            sourceTitle: savedCopy.sourceTitle,
            notes: savedCopy.notes,
            imageURL: localImageURL,
            isFavorite: true,
            visibility: .publicRecipe,
            ownerId: savedCopy.ownerId,
            cloudRecordName: savedCopy.cloudRecordName,
            cloudImageRecordName: savedCopy.cloudImageRecordName,
            imageModifiedAt: savedCopy.imageModifiedAt,
            createdAt: savedCopy.createdAt,
            updatedAt: savedCopy.updatedAt,
            originalRecipeId: savedCopy.originalRecipeId,
            originalCreatorId: savedCopy.originalCreatorId,
            originalCreatorName: savedCopy.originalCreatorName,
            savedAt: savedCopy.savedAt,
            sourceRecipeUpdatedAt: savedCopy.sourceRecipeUpdatedAt,
            followsSourceUpdates: savedCopy.followsSourceUpdates,
            relatedRecipeIds: savedCopy.relatedRecipeIds,
            isPreview: savedCopy.isPreview
        )

        let refreshedSource = Recipe(
            id: sourceId,
            title: "New Chili",
            ingredients: [
                Ingredient(name: "Beans", quantity: nil),
                Ingredient(name: "Chili powder", quantity: nil)
            ],
            steps: [
                CookStep(index: 0, text: "Simmer", timers: []),
                CookStep(index: 1, text: "Serve", timers: [])
            ],
            yields: "6 servings",
            totalMinutes: 45,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: URL(string: "https://example.com/chili"),
            sourceTitle: "Example",
            notes: "New notes",
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: creatorId,
            cloudRecordName: sourceId.uuidString,
            cloudImageRecordName: "source-image-record",
            imageModifiedAt: refreshedSourceUpdatedAt,
            createdAt: original.createdAt,
            updatedAt: refreshedSourceUpdatedAt,
            relatedRecipeIds: [UUID()]
        )

        let refreshedSavedCopy = locallyCustomized.applyingSourceSnapshot(refreshedSource)

        XCTAssertEqual(refreshedSavedCopy.id, locallyCustomized.id)
        XCTAssertEqual(refreshedSavedCopy.title, "New Chili")
        XCTAssertEqual(refreshedSavedCopy.ingredients.map { $0.name }, ["Beans", "Chili powder"])
        XCTAssertEqual(refreshedSavedCopy.steps.map { $0.text }, ["Simmer", "Serve"])
        XCTAssertEqual(refreshedSavedCopy.yields, "6 servings")
        XCTAssertEqual(refreshedSavedCopy.notes, "New notes")
        XCTAssertEqual(refreshedSavedCopy.imageURL, localImageURL)
        XCTAssertTrue(refreshedSavedCopy.isFavorite)
        XCTAssertEqual(refreshedSavedCopy.visibility, RecipeVisibility.publicRecipe)
        XCTAssertEqual(refreshedSavedCopy.ownerId, saverId)
        XCTAssertEqual(refreshedSavedCopy.originalRecipeId, sourceId)
        XCTAssertEqual(refreshedSavedCopy.cloudImageRecordName, "source-image-record")
        XCTAssertEqual(refreshedSavedCopy.sourceRecipeUpdatedAt, refreshedSourceUpdatedAt)
        XCTAssertTrue(refreshedSavedCopy.followsSourceUpdates)
    }

    func testApplyingSourceSnapshot_ClearsLocalImageWhenSourceRemovesImage() {
        let sourceId = UUID()
        let creatorId = UUID()
        let saverId = UUID()
        let localImageURL = URL(fileURLWithPath: "/tmp/saved-copy.jpg")
        let sourceUpdatedAt = Date(timeIntervalSince1970: 1_700_000_500)

        let savedCopy = Recipe(
            id: UUID(),
            title: "Saved Chili",
            ingredients: [Ingredient(name: "Beans", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: localImageURL,
            isFavorite: true,
            visibility: .publicRecipe,
            ownerId: saverId,
            cloudRecordName: nil,
            cloudImageRecordName: "old-image-record",
            imageModifiedAt: sourceUpdatedAt,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: sourceUpdatedAt,
            originalRecipeId: sourceId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRecipeUpdatedAt: sourceUpdatedAt,
            followsSourceUpdates: true
        )

        let refreshedSource = Recipe(
            id: sourceId,
            title: "Saved Chili",
            ingredients: [Ingredient(name: "Beans", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: creatorId,
            cloudRecordName: sourceId.uuidString,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_900)
        )

        let refreshedSavedCopy = savedCopy.applyingSourceSnapshot(refreshedSource)

        XCTAssertNil(refreshedSavedCopy.imageURL)
        XCTAssertNil(refreshedSavedCopy.cloudImageRecordName)
    }

    func testApplyingSourceSnapshot_RefreshesRelatedRecipeIDsFromSource() {
        let sourceId = UUID()
        let creatorId = UUID()
        let staleRelatedID = UUID()
        let refreshedRelatedID = UUID()

        let savedCopy = Recipe(
            id: UUID(),
            title: "Saved Chili",
            ingredients: [Ingredient(name: "Beans", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: true,
            visibility: .publicRecipe,
            ownerId: UUID(),
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            originalRecipeId: sourceId,
            originalCreatorId: creatorId,
            originalCreatorName: "Alice",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRecipeUpdatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            followsSourceUpdates: true,
            relatedRecipeIds: [staleRelatedID]
        )

        let refreshedSource = Recipe(
            id: sourceId,
            title: "Saved Chili",
            ingredients: [Ingredient(name: "Beans", quantity: nil)],
            steps: [CookStep(index: 0, text: "Cook", timers: [])],
            yields: "4 servings",
            totalMinutes: 30,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: "Updated",
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: creatorId,
            cloudRecordName: sourceId.uuidString,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_900),
            relatedRecipeIds: [refreshedRelatedID]
        )

        let refreshedSavedCopy = savedCopy.applyingSourceSnapshot(refreshedSource)

        XCTAssertEqual(refreshedSavedCopy.relatedRecipeIds, [refreshedRelatedID])
    }

    func testWithImageURL_PreservesUpdatedAtForPassiveImageLocalization() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let recipe = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: updatedAt
        )

        let updatedRecipe = recipe.withImageURL(URL(fileURLWithPath: "/tmp/lemon-pasta.jpg"))

        XCTAssertEqual(updatedRecipe.updatedAt, updatedAt)
    }

    func testWithCloudImageMetadata_PreservesUpdatedAtForMetadataSync() {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let recipe = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: updatedAt
        )

        let updatedRecipe = recipe.withCloudImageMetadata(
            recordName: "cloud-image-record",
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_600)
        )

        XCTAssertEqual(updatedRecipe.updatedAt, updatedAt)
    }

    func testResolvedFollowsSourceUpdates_TreatsLegacySavedCopiesAsFollowing() {
        XCTAssertTrue(
            Recipe.resolvedFollowsSourceUpdates(
                originalRecipeId: UUID(),
                savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceRecipeUpdatedAt: nil,
                followsSourceUpdates: false
            )
        )
    }

    func testResolvedFollowsSourceUpdates_KeepsExplicitForksOptedOut() {
        XCTAssertFalse(
            Recipe.resolvedFollowsSourceUpdates(
                originalRecipeId: UUID(),
                savedAt: Date(timeIntervalSince1970: 1_700_000_000),
                sourceRecipeUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                followsSourceUpdates: false
            )
        )
    }

    func testDecodedLegacyCopy_StillRequiresSourceTrackingMigration() throws {
        let sourceId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let legacyCopy = Recipe(
            id: UUID(),
            title: "Saved Pasta",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 20,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: UUID(),
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: savedAt,
            originalRecipeId: sourceId,
            originalCreatorId: UUID(),
            originalCreatorName: "Alice",
            savedAt: savedAt,
            sourceRecipeUpdatedAt: nil,
            followsSourceUpdates: false
        )

        let encoded = try JSONEncoder().encode(legacyCopy)
        let decoded = try JSONDecoder().decode(Recipe.self, from: encoded)

        XCTAssertTrue(decoded.isFollowingSourceUpdates)
        XCTAssertTrue(decoded.requiresLegacySourceTrackingMigration)
    }

    func testHasImageDifferences_ReturnsTrueWhenSourceImageMetadataDiffers() {
        let original = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let edited = Recipe(
            id: original.id,
            title: original.title,
            ingredients: original.ingredients,
            steps: original.steps,
            yields: original.yields,
            totalMinutes: original.totalMinutes,
            tags: original.tags,
            nutrition: original.nutrition,
            sourceURL: original.sourceURL,
            sourceTitle: original.sourceTitle,
            notes: original.notes,
            imageURL: original.imageURL,
            isFavorite: original.isFavorite,
            visibility: original.visibility,
            ownerId: original.ownerId,
            cloudRecordName: original.cloudRecordName,
            cloudImageRecordName: "new-image",
            imageModifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
            createdAt: original.createdAt,
            updatedAt: original.updatedAt,
            originalRecipeId: original.originalRecipeId,
            originalCreatorId: original.originalCreatorId,
            originalCreatorName: original.originalCreatorName,
            savedAt: original.savedAt,
            sourceRecipeUpdatedAt: original.sourceRecipeUpdatedAt,
            followsSourceUpdates: original.followsSourceUpdates,
            relatedRecipeIds: original.relatedRecipeIds,
            isPreview: original.isPreview
        )

        XCTAssertTrue(edited.hasImageDifferences(comparedTo: original))
    }

    func testShouldPreserveLegacyEdits_ReturnsTrueForEditedLegacyCopy() {
        let sourceId = UUID()
        let ownerId = UUID()
        let saverId = UUID()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let editedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let sourceRecipe = makeRecipe(
            id: sourceId,
            title: "Updated Pasta",
            ownerId: ownerId,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )

        let legacyCopy = Recipe(
            id: UUID(),
            title: "My Pasta",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 20,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: saverId,
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: savedAt,
            updatedAt: editedAt,
            originalRecipeId: sourceId,
            originalCreatorId: ownerId,
            originalCreatorName: "Alice",
            savedAt: savedAt,
            sourceRecipeUpdatedAt: nil,
            followsSourceUpdates: false
        )

        XCTAssertTrue(legacyCopy.shouldPreserveLegacyEdits(comparedTo: sourceRecipe))
    }

    func testHasEditableDifferences_ReturnsFalseForNoOpEdit() {
        let recipe = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertFalse(recipe.hasEditableDifferences(comparedTo: recipe))
    }

    func testHasEditableDifferences_ReturnsTrueWhenRecipeContentChanges() {
        let original = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let edited = Recipe(
            id: original.id,
            title: "Spicy Lemon Pasta",
            ingredients: original.ingredients,
            steps: original.steps,
            yields: original.yields,
            totalMinutes: original.totalMinutes,
            tags: original.tags,
            nutrition: original.nutrition,
            sourceURL: original.sourceURL,
            sourceTitle: original.sourceTitle,
            notes: original.notes,
            imageURL: original.imageURL,
            isFavorite: original.isFavorite,
            visibility: original.visibility,
            ownerId: original.ownerId,
            cloudRecordName: original.cloudRecordName,
            cloudImageRecordName: original.cloudImageRecordName,
            imageModifiedAt: original.imageModifiedAt,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            originalRecipeId: original.originalRecipeId,
            originalCreatorId: original.originalCreatorId,
            originalCreatorName: original.originalCreatorName,
            savedAt: original.savedAt,
            sourceRecipeUpdatedAt: original.sourceRecipeUpdatedAt,
            followsSourceUpdates: original.followsSourceUpdates,
            relatedRecipeIds: original.relatedRecipeIds,
            isPreview: original.isPreview
        )

        XCTAssertTrue(edited.hasEditableDifferences(comparedTo: original))
    }

    func testHasEditableDifferences_IgnoresVisibilityChangesForFollowingState() {
        let original = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let visibilityOnlyEdit = Recipe(
            id: original.id,
            title: original.title,
            ingredients: original.ingredients,
            steps: original.steps,
            yields: original.yields,
            totalMinutes: original.totalMinutes,
            tags: original.tags,
            nutrition: original.nutrition,
            sourceURL: original.sourceURL,
            sourceTitle: original.sourceTitle,
            notes: original.notes,
            imageURL: original.imageURL,
            isFavorite: original.isFavorite,
            visibility: .privateRecipe,
            ownerId: original.ownerId,
            cloudRecordName: original.cloudRecordName,
            cloudImageRecordName: original.cloudImageRecordName,
            imageModifiedAt: original.imageModifiedAt,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            originalRecipeId: original.originalRecipeId,
            originalCreatorId: original.originalCreatorId,
            originalCreatorName: original.originalCreatorName,
            savedAt: original.savedAt,
            sourceRecipeUpdatedAt: original.sourceRecipeUpdatedAt,
            followsSourceUpdates: original.followsSourceUpdates,
            relatedRecipeIds: original.relatedRecipeIds,
            isPreview: original.isPreview
        )

        XCTAssertFalse(visibilityOnlyEdit.hasEditableDifferences(comparedTo: original))
    }

    func testRelatedGraphReferenceID_UsesSourceIDForFollowingCopies() {
        let sourceId = UUID()
        let savedCopy = Recipe(
            id: UUID(),
            title: "Saved Pasta",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 20,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: UUID(),
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            originalRecipeId: sourceId,
            originalCreatorId: UUID(),
            originalCreatorName: "Alice",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRecipeUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            followsSourceUpdates: true
        )

        XCTAssertEqual(savedCopy.relatedGraphReferenceID, sourceId)
    }

    func testSourceAssetReferenceID_UsesSourceIDForFollowingCopies() {
        let sourceId = UUID()
        let savedCopy = Recipe(
            id: UUID(),
            title: "Saved Pasta",
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 20,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: nil,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: UUID(),
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: nil,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            originalRecipeId: sourceId,
            originalCreatorId: UUID(),
            originalCreatorName: "Alice",
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRecipeUpdatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            followsSourceUpdates: true
        )

        XCTAssertEqual(savedCopy.sourceAssetReferenceID, sourceId)
    }

    func testHasEditableDifferences_DetectsRelatedRecipeChanges() {
        let original = makeRecipe(
            title: "Lemon Pasta",
            ownerId: UUID(),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let relatedOnlyEdit = Recipe(
            id: original.id,
            title: original.title,
            ingredients: original.ingredients,
            steps: original.steps,
            yields: original.yields,
            totalMinutes: original.totalMinutes,
            tags: original.tags,
            nutrition: original.nutrition,
            sourceURL: original.sourceURL,
            sourceTitle: original.sourceTitle,
            notes: original.notes,
            imageURL: original.imageURL,
            isFavorite: original.isFavorite,
            visibility: original.visibility,
            ownerId: original.ownerId,
            cloudRecordName: original.cloudRecordName,
            cloudImageRecordName: original.cloudImageRecordName,
            imageModifiedAt: original.imageModifiedAt,
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            originalRecipeId: original.originalRecipeId,
            originalCreatorId: original.originalCreatorId,
            originalCreatorName: original.originalCreatorName,
            savedAt: original.savedAt,
            sourceRecipeUpdatedAt: original.sourceRecipeUpdatedAt,
            followsSourceUpdates: original.followsSourceUpdates,
            relatedRecipeIds: [UUID()],
            isPreview: original.isPreview
        )

        XCTAssertTrue(relatedOnlyEdit.hasEditableDifferences(comparedTo: original))
    }

    func testWithFavorite_PreservesOwnershipAndSyncMetadata() {
        let ownerId = UUID()
        let originalRecipeId = UUID()
        let creatorId = UUID()
        let relatedId = UUID()
        let base = Recipe(
            title: "Saved Soup",
            ingredients: [Ingredient(name: "Beans", quantity: nil)],
            steps: [CookStep(index: 0, text: "Simmer", timers: [])],
            yields: "2 servings",
            totalMinutes: 35,
            tags: [Tag(name: "Lunch")],
            nutrition: Nutrition(calories: 250, protein: 12, fat: 4, carbohydrates: 40),
            sourceURL: URL(string: "https://example.com/soup"),
            sourceTitle: "Example Soup",
            notes: "Use extra broth",
            imageURL: URL(fileURLWithPath: "/tmp/soup.jpg"),
            isFavorite: false,
            visibility: .privateRecipe,
            ownerId: ownerId,
            cloudRecordName: "private-record",
            cloudImageRecordName: "image-record",
            imageModifiedAt: Date(timeIntervalSince1970: 1_700_000_001),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
            originalRecipeId: originalRecipeId,
            originalCreatorId: creatorId,
            originalCreatorName: "Avery",
            savedAt: Date(timeIntervalSince1970: 1_700_000_020),
            sourceRecipeUpdatedAt: Date(timeIntervalSince1970: 1_700_000_030),
            followsSourceUpdates: true,
            relatedRecipeIds: [relatedId],
            isPreview: true
        )

        let favorite = base.withFavorite(true)

        XCTAssertTrue(favorite.isFavorite)
        XCTAssertEqual(favorite.visibility, base.visibility)
        XCTAssertEqual(favorite.ownerId, ownerId)
        XCTAssertEqual(favorite.cloudRecordName, base.cloudRecordName)
        XCTAssertEqual(favorite.cloudImageRecordName, base.cloudImageRecordName)
        XCTAssertEqual(favorite.originalRecipeId, originalRecipeId)
        XCTAssertEqual(favorite.originalCreatorId, creatorId)
        XCTAssertEqual(favorite.savedAt, base.savedAt)
        XCTAssertEqual(favorite.sourceRecipeUpdatedAt, base.sourceRecipeUpdatedAt)
        XCTAssertEqual(favorite.followsSourceUpdates, base.followsSourceUpdates)
        XCTAssertEqual(favorite.relatedRecipeIds, [relatedId])
        XCTAssertEqual(favorite.isPreview, base.isPreview)
    }

    private func makeRecipe(
        id: UUID = UUID(),
        title: String,
        ownerId: UUID,
        updatedAt: Date,
        notes: String? = nil,
        relatedRecipeIds: [UUID] = []
    ) -> Recipe {
        Recipe(
            id: id,
            title: title,
            ingredients: [Ingredient(name: "Salt", quantity: nil)],
            steps: [CookStep(index: 0, text: "Mix", timers: [])],
            yields: "4 servings",
            totalMinutes: 20,
            tags: [Tag(name: "Dinner")],
            nutrition: nil,
            sourceURL: nil,
            sourceTitle: nil,
            notes: notes,
            imageURL: nil,
            isFavorite: false,
            visibility: .publicRecipe,
            ownerId: ownerId,
            cloudRecordName: id.uuidString,
            cloudImageRecordName: nil,
            imageModifiedAt: updatedAt,
            createdAt: Date(timeIntervalSince1970: 1_699_999_000),
            updatedAt: updatedAt,
            relatedRecipeIds: relatedRecipeIds
        )
    }
}
