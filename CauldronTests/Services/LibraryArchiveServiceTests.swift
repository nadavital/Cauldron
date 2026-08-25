import SwiftData
import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Cauldron

private actor ArchiveAuthorizationProbe {
    var isPermitted = true
    var latestProgress: LibraryArchiveService.RestoreReport?
    func permits() -> Bool { isPermitted }
    func revoke() { isPermitted = false }
    func record(_ report: LibraryArchiveService.RestoreReport) { latestProgress = report }
    func progress() -> LibraryArchiveService.RestoreReport? { latestProgress }
}

private actor ArchiveDeletionProbe {
    private var completed = false
    private var observedWaiting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func start(ownerID: UUID) {
        Task {
            let lease = await AccountDeletionGate.shared.begin(ownerID: ownerID)
            markCompleted()
            await AccountDeletionGate.shared.end(lease)
        }
    }

    func hasCompleted() -> Bool { completed }
    func markObservedWaitingIfNeeded() { observedWaiting = !completed }
    func didObserveWaiting() -> Bool { observedWaiting }

    func waitUntilCompleted() async {
        if completed { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func markCompleted() {
        completed = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ArchiveConcurrentRestoreProbe {
    private var didReachFirstCheckpoint = false
    private var firstCheckpointWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseFirstContinuation: CheckedContinuation<Void, Never>?

    func pauseFirstRestoreAtCheckpoint() async {
        guard !didReachFirstCheckpoint else { return }
        didReachFirstCheckpoint = true
        let waiters = firstCheckpointWaiters
        firstCheckpointWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { releaseFirstContinuation = $0 }
    }

    func waitUntilFirstCheckpoint() async {
        if didReachFirstCheckpoint { return }
        await withCheckedContinuation { firstCheckpointWaiters.append($0) }
    }

    func releaseFirstRestore() {
        releaseFirstContinuation?.resume()
        releaseFirstContinuation = nil
    }
}

@MainActor
final class LibraryArchiveServiceTests: XCTestCase {
    override func tearDown() async throws {
        CurrentUserSession.shared.signOut()
        try await super.tearDown()
    }

    func testCrossAccountRestoreIntoCleanLibraryRemapsRelationshipsAndIsIdempotent() async throws {
        let sourceOwner = UUID()
        let targetOwner = UUID()
        let recipeID = UUID()
        let collectionID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = createdAt.addingTimeInterval(600)
        let source = DependencyContainer.preview()
        setCurrentUser(sourceOwner)

        let recipe = Recipe(
            id: recipeID,
            title: "Archive Soup",
            ingredients: [Ingredient(name: "Carrots")],
            steps: [CookStep(index: 0, text: "Simmer.")],
            yields: "2 bowls",
            notes: "Preserve this note",
            visibility: .privateRecipe,
            ownerId: sourceOwner,
            createdAt: createdAt,
            updatedAt: updatedAt,
            relatedRecipeIds: [UUID()]
        )
        try await source.recipeRepository.create(recipe, skipCloudSync: true)
        try await source.collectionRepository.create(Collection(
            id: collectionID,
            name: "Comfort Food",
            userId: sourceOwner,
            recipeIds: [recipeID],
            visibility: .privateRecipe,
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
        let archive = try await source.libraryArchiveService.export(ownerID: sourceOwner, now: updatedAt)

        let target = DependencyContainer.preview()
        setCurrentUser(targetOwner)
        let first = try await target.libraryArchiveService.restore(archive, ownerID: targetOwner)
        XCTAssertEqual(first.recipesInserted, 1)
        XCTAssertEqual(first.collectionsInserted, 1)

        let targetRecipes = try await target.recipeRepository.fetchLibraryRecipes(ownerId: targetOwner)
        let restoredRecipe = try XCTUnwrap(targetRecipes.first)
        XCTAssertNotEqual(restoredRecipe.id, recipeID)
        XCTAssertEqual(restoredRecipe.ownerId, targetOwner)
        XCTAssertEqual(restoredRecipe.title, "Archive Soup")
        XCTAssertEqual(restoredRecipe.notes, "Preserve this note")
        XCTAssertEqual(restoredRecipe.createdAt, createdAt)
        XCTAssertEqual(restoredRecipe.updatedAt, updatedAt)
        XCTAssertNil(restoredRecipe.cloudImageRecordName)

        let targetCollections = try await target.collectionRepository.fetchUserCollections(ownerId: targetOwner)
        let restoredCollection = try XCTUnwrap(targetCollections.first)
        XCTAssertNotEqual(restoredCollection.id, collectionID)
        XCTAssertEqual(restoredCollection.userId, targetOwner)
        XCTAssertEqual(restoredCollection.recipeIds, [restoredRecipe.id])
        XCTAssertEqual(restoredCollection.updatedAt, updatedAt)

        let second = try await target.libraryArchiveService.restore(archive, ownerID: targetOwner)
        XCTAssertEqual(second.recipesInserted, 0)
        XCTAssertEqual(second.collectionsInserted, 0)
        XCTAssertEqual(second.recipesKept, 1)
        XCTAssertEqual(second.collectionsKept, 1)

        let finalRecipeIDs = try await target.recipeRepository
            .fetchLibraryRecipes(ownerId: targetOwner)
            .map(\.id)
        let finalCollectionIDs = try await target.collectionRepository
            .fetchUserCollections(ownerId: targetOwner)
            .map(\.id)
        XCTAssertEqual(finalRecipeIDs, [restoredRecipe.id])
        XCTAssertEqual(finalCollectionIDs, [restoredCollection.id])
    }

    func testArchiveRoundTripIncludesRecipeImageBytes() async throws {
        let ownerID = UUID()
        let recipeID = UUID()
        let dependencies = DependencyContainer.preview()
        setCurrentUser(ownerID)
        defer { Task { await dependencies.imageManager.deleteImage(recipeId: recipeID) } }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let filename = try await dependencies.imageManager.saveImage(image, recipeId: recipeID)
        let recipe = Recipe(
            id: recipeID,
            title: "Photographed Toast",
            ingredients: [Ingredient(name: "Bread")],
            steps: [CookStep(index: 0, text: "Toast.")],
            imageURL: await dependencies.imageManager.imageURL(for: filename),
            ownerId: ownerID
        )
        try await dependencies.recipeRepository.create(recipe, skipCloudSync: true)

        let data = try await dependencies.libraryArchiveService.export(ownerID: ownerID)
        let decoded = try await dependencies.libraryArchiveService.decodeAndValidate(data)
        let archivedImageData = try XCTUnwrap(decoded.recipes.first?.imageData)
        XCTAssertFalse(archivedImageData.isEmpty)

        await dependencies.imageManager.deleteImage(recipeId: recipeID)
        let emptyTarget = DependencyContainer.preview()
        let report = try await emptyTarget.libraryArchiveService.restore(data, ownerID: ownerID)
        XCTAssertEqual(report.imagesRestored, 1)
        let imageExists = await emptyTarget.imageManager.imageExists(recipeId: recipeID)
        XCTAssertTrue(imageExists)
    }

    func testExportEnforcesPerImageAndAggregateImageBoundariesAndRoundTrips() async throws {
        let ownerID = UUID()
        let recipeIDs = [UUID(), UUID()]
        let dependencies = DependencyContainer.preview()
        setCurrentUser(ownerID)
        defer {
            Task {
                for recipeID in recipeIDs {
                    await dependencies.imageManager.deleteImage(recipeId: recipeID)
                }
            }
        }

        for (index, recipeID) in recipeIDs.enumerated() {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
            let image = renderer.image { context in
                (index == 0 ? UIColor.systemOrange : UIColor.systemPurple).setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
            _ = try await dependencies.imageManager.saveImage(image, recipeId: recipeID)
            try await dependencies.recipeRepository.create(Recipe(
                id: recipeID,
                title: "Budget Image \(index)",
                ingredients: [Ingredient(name: "Ingredient")],
                steps: [CookStep(index: 0, text: "Cook")],
                ownerId: ownerID
            ), skipCloudSync: true)
        }

        let baseline = try await dependencies.libraryArchiveService.export(ownerID: ownerID)
        let decodedBaseline = try await dependencies.libraryArchiveService.decodeAndValidate(baseline)
        let payloads = decodedBaseline.recipes.compactMap { portable in
            portable.imageData.map { (id: portable.id, count: $0.count) }
        }
        XCTAssertEqual(payloads.count, 2)
        let largest = try XCTUnwrap(payloads.max(by: { $0.count < $1.count }))
        let aggregate = payloads.reduce(0) { $0 + $1.count }

        let exactBoundaryService = makeService(
            dependencies,
            maximumSingleImageBytes: largest.count,
            maximumTotalImageBytes: aggregate
        )
        let exactBoundaryArchive = try await exactBoundaryService.export(ownerID: ownerID)
        let roundTripped = try await exactBoundaryService.decodeAndValidate(exactBoundaryArchive)
        XCTAssertEqual(roundTripped.recipes.compactMap(\.imageData).count, 2)

        let perImageRejectingService = makeService(
            dependencies,
            maximumSingleImageBytes: largest.count - 1,
            maximumTotalImageBytes: aggregate
        )
        do {
            _ = try await perImageRejectingService.export(ownerID: ownerID)
            XCTFail("Expected export per-image budget rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            guard case .imageTooLarge(let rejectedID) = error else {
                return XCTFail("Expected per-image error, received \(error)")
            }
            XCTAssertTrue(payloads.contains {
                $0.id == rejectedID && $0.count > largest.count - 1
            })
        }

        let aggregateRejectingService = makeService(
            dependencies,
            maximumSingleImageBytes: largest.count,
            maximumTotalImageBytes: aggregate - 1
        )
        do {
            _ = try await aggregateRejectingService.export(ownerID: ownerID)
            XCTFail("Expected export aggregate image budget rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .archiveImagesTooLarge)
        }
    }

    func testRestoreRemapsSameStoreForeignOwnerCollisionsAndRelationships() async throws {
        let sourceOwner = UUID()
        let targetOwner = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let collectionID = UUID()
        let dependencies = DependencyContainer.preview()
        setCurrentUser(sourceOwner)

        try await dependencies.recipeRepository.create(Recipe(
            id: firstID,
            title: "Source First",
            ingredients: [Ingredient(name: "One")],
            steps: [CookStep(index: 0, text: "First")],
            ownerId: sourceOwner,
            relatedRecipeIds: [secondID]
        ), skipCloudSync: true)
        try await dependencies.recipeRepository.create(Recipe(
            id: secondID,
            title: "Source Second",
            ingredients: [Ingredient(name: "Two")],
            steps: [CookStep(index: 0, text: "Second")],
            ownerId: sourceOwner
        ), skipCloudSync: true)
        try await dependencies.collectionRepository.create(Collection(
            id: collectionID,
            name: "Source Pair",
            userId: sourceOwner,
            recipeIds: [firstID, secondID]
        ))
        let archive = try await dependencies.libraryArchiveService.export(ownerID: sourceOwner)

        setCurrentUser(targetOwner)
        let report = try await dependencies.libraryArchiveService.restore(archive, ownerID: targetOwner)
        XCTAssertEqual(report.recipesInserted, 2)
        XCTAssertEqual(report.collectionsInserted, 1)

        let targetRecipes = try await dependencies.recipeRepository.fetchLibraryRecipes(ownerId: targetOwner)
        XCTAssertEqual(targetRecipes.count, 2)
        let targetFirst = try XCTUnwrap(targetRecipes.first { $0.title == "Source First" })
        let targetSecond = try XCTUnwrap(targetRecipes.first { $0.title == "Source Second" })
        XCTAssertNotEqual(targetFirst.id, firstID)
        XCTAssertNotEqual(targetSecond.id, secondID)
        XCTAssertEqual(targetFirst.relatedRecipeIds, [targetSecond.id])

        let targetCollections = try await dependencies.collectionRepository.fetchUserCollections(ownerId: targetOwner)
        let targetCollection = try XCTUnwrap(targetCollections.first)
        XCTAssertNotEqual(targetCollection.id, collectionID)
        XCTAssertEqual(targetCollection.recipeIds, [targetFirst.id, targetSecond.id])

        let sourceRecipes = try await dependencies.recipeRepository.fetchLibraryRecipes(ownerId: sourceOwner)
        XCTAssertEqual(Set(sourceRecipes.map(\.id)), [firstID, secondID])
        let sourceCollectionIDs = try await dependencies.collectionRepository
            .fetchUserCollections(ownerId: sourceOwner)
            .map(\.id)
        XCTAssertEqual(sourceCollectionIDs, [collectionID])

        let secondRestore = try await dependencies.libraryArchiveService.restore(archive, ownerID: targetOwner)
        XCTAssertEqual(secondRestore.recipesKept, 2)
        XCTAssertEqual(secondRestore.collectionsKept, 1)
        let targetRecipeCount = try await dependencies.recipeRepository
            .fetchLibraryRecipes(ownerId: targetOwner)
            .count
        XCTAssertEqual(targetRecipeCount, 2)
    }

    func testArchiveRoundTripIncludesCustomCollectionCoverImage() async throws {
        let sourceOwner = UUID()
        let targetOwner = UUID()
        let collectionID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(sourceOwner)
        defer {
            Task {
                await source.collectionImageManager.deleteImage(collectionId: collectionID)
            }
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        let image = renderer.image { context in
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let imageURL = try await source.collectionImageManager.saveImage(image, collectionId: collectionID)
        try await source.collectionRepository.create(Collection(
            id: collectionID,
            name: "Covered Collection",
            userId: sourceOwner,
            coverImageType: .customImage,
            coverImageURL: imageURL,
            coverImageModifiedAt: Date()
        ))

        let archive = try await source.libraryArchiveService.export(ownerID: sourceOwner)
        let decoded = try await source.libraryArchiveService.decodeAndValidate(archive)
        let coverImageData = try XCTUnwrap(decoded.collections.first?.coverImageData)
        XCTAssertFalse(coverImageData.isEmpty)
        let rejectingExportService = makeService(
            source,
            maximumSingleImageBytes: coverImageData.count - 1
        )
        do {
            _ = try await rejectingExportService.export(ownerID: sourceOwner)
            XCTFail("Expected collection cover export budget rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .collectionImageTooLarge(collectionID))
        }
        await source.collectionImageManager.deleteImage(collectionId: collectionID)

        let target = DependencyContainer.preview()
        setCurrentUser(targetOwner)
        let report = try await target.libraryArchiveService.restore(archive, ownerID: targetOwner)
        XCTAssertEqual(report.imagesRestored, 1)
        let restoredCollections = try await target.collectionRepository.fetchUserCollections(ownerId: targetOwner)
        let restored = try XCTUnwrap(restoredCollections.first)
        XCTAssertEqual(restored.coverImageType, .customImage)
        XCTAssertNotNil(restored.coverImageURL)
        XCTAssertNil(restored.cloudCoverImageRecordName)
        let coverImageExists = await target.collectionImageManager.imageExists(collectionId: restored.id)
        XCTAssertTrue(coverImageExists)
        await target.collectionImageManager.deleteImage(collectionId: restored.id)
    }

    func testDecodeRejectsOversizedRawInputBeforeJSONDecoding() async throws {
        let dependencies = DependencyContainer.preview()
        let service = LibraryArchiveService(
            recipeRepository: dependencies.recipeRepository,
            collectionRepository: dependencies.collectionRepository,
            modelContainer: dependencies.modelContainer,
            imageManager: dependencies.imageManager,
            collectionImageManager: dependencies.collectionImageManager,
            maximumArchiveBytes: 32
        )

        do {
            _ = try await service.decodeAndValidate(Data(repeating: 0x20, count: 33))
            XCTFail("Expected oversized archive rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .archiveTooLarge)
        }
    }

    func testDecodeRejectsInvalidTimestampChronologyAndGrossFutureValues() async throws {
        let dependencies = DependencyContainer.preview()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recipeID = UUID()
        let recipe = Recipe(
            id: recipeID,
            title: "Chronology Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            createdAt: now,
            updatedAt: now
        )

        var reversedRecipe = PortableRecipe(recipe: recipe)
        reversedRecipe.createdAt = now
        reversedRecipe.updatedAt = now.addingTimeInterval(-1)
        let reversedData = try encodeArchive(LibraryArchive(
            exportedAt: now,
            recipes: [reversedRecipe],
            collections: []
        ))
        do {
            _ = try await dependencies.libraryArchiveService.decodeAndValidate(reversedData, now: now)
            XCTFail("Expected reversed recipe chronology rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .invalidRecipeTimestamp(recipeID))
        }

        let collectionID = UUID()
        var reversedCollection = PortableCollection(collection: Collection(
            id: collectionID,
            name: "Chronology Collection",
            userId: UUID(),
            createdAt: now,
            updatedAt: now
        ))
        reversedCollection.createdAt = now
        reversedCollection.updatedAt = now.addingTimeInterval(-1)
        let reversedCollectionData = try encodeArchive(LibraryArchive(
            exportedAt: now,
            recipes: [],
            collections: [reversedCollection]
        ))
        do {
            _ = try await dependencies.libraryArchiveService.decodeAndValidate(
                reversedCollectionData,
                now: now
            )
            XCTFail("Expected reversed collection chronology rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .invalidCollectionTimestamp(collectionID))
        }

        let grossFuture = now.addingTimeInterval(
            LibraryArchiveService.maximumArchiveFutureClockSkew + 1
        )
        var futureRecipe = PortableRecipe(recipe: recipe)
        futureRecipe.sourceRecipeUpdatedAt = grossFuture
        let futureData = try encodeArchive(LibraryArchive(
            exportedAt: now,
            recipes: [futureRecipe],
            collections: []
        ))
        do {
            _ = try await dependencies.libraryArchiveService.decodeAndValidate(futureData, now: now)
            XCTFail("Expected gross-future recipe timestamp rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .invalidRecipeTimestamp(recipeID))
        }

        let futureArchiveData = try encodeArchive(LibraryArchive(
            exportedAt: grossFuture,
            recipes: [],
            collections: []
        ))
        do {
            _ = try await dependencies.libraryArchiveService.decodeAndValidate(futureArchiveData, now: now)
            XCTFail("Expected gross-future archive timestamp rejection")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .invalidArchiveTimestamp)
        }
    }

    func testDecodeNormalizesSafeFutureRecipeAndCollectionTimestamps() async throws {
        let dependencies = DependencyContainer.preview()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let safeFuture = now.addingTimeInterval(3_600)
        let ownerID = UUID()
        var portableRecipe = PortableRecipe(recipe: Recipe(
            title: "Clock Skew Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: safeFuture,
            savedAt: safeFuture,
            sourceRecipeUpdatedAt: safeFuture
        ))
        portableRecipe.updatedAt = safeFuture
        portableRecipe.savedAt = safeFuture
        portableRecipe.sourceRecipeUpdatedAt = safeFuture

        var portableCollection = PortableCollection(collection: Collection(
            name: "Clock Skew Collection",
            userId: ownerID,
            savedAt: safeFuture,
            sourceCollectionUpdatedAt: safeFuture,
            createdAt: now.addingTimeInterval(-60),
            updatedAt: safeFuture
        ))
        portableCollection.updatedAt = safeFuture
        portableCollection.savedAt = safeFuture
        portableCollection.sourceCollectionUpdatedAt = safeFuture

        let data = try encodeArchive(LibraryArchive(
            exportedAt: safeFuture,
            sourceOwnerID: ownerID,
            recipes: [portableRecipe],
            collections: [portableCollection]
        ))
        let decoded = try await dependencies.libraryArchiveService.decodeAndValidate(data, now: now)

        XCTAssertEqual(decoded.exportedAt, now)
        XCTAssertEqual(decoded.recipes.first?.createdAt, now.addingTimeInterval(-60))
        XCTAssertEqual(decoded.recipes.first?.updatedAt, now)
        XCTAssertEqual(decoded.recipes.first?.savedAt, now)
        XCTAssertEqual(decoded.recipes.first?.sourceRecipeUpdatedAt, now)
        XCTAssertEqual(decoded.collections.first?.createdAt, now.addingTimeInterval(-60))
        XCTAssertEqual(decoded.collections.first?.updatedAt, now)
        XCTAssertEqual(decoded.collections.first?.savedAt, now)
        XCTAssertEqual(decoded.collections.first?.sourceCollectionUpdatedAt, now)
    }

    func testArchiveRoundTripPreservesSubsecondNewestWinsTimestamps() async throws {
        let ownerID = UUID()
        let dependencies = DependencyContainer.preview()
        setCurrentUser(ownerID)
        let updatedAt = Date(timeIntervalSinceReferenceDate: 800_000_000.987_654)
        try await dependencies.recipeRepository.create(Recipe(
            title: "Subsecond Soup",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID,
            createdAt: updatedAt.addingTimeInterval(-1),
            updatedAt: updatedAt
        ), skipCloudSync: true)

        let data = try await dependencies.libraryArchiveService.export(ownerID: ownerID, now: updatedAt)
        let decoded = try await dependencies.libraryArchiveService.decodeAndValidate(data, now: updatedAt)

        XCTAssertEqual(try XCTUnwrap(decoded.recipes.first?.updatedAt).timeIntervalSinceReferenceDate,
                       updatedAt.timeIntervalSinceReferenceDate,
                       accuracy: 0.000_001)
    }

    func testExportStopsWhenAccountAuthorizationChangesDuringSuspension() async throws {
        let ownerID = UUID()
        let dependencies = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await dependencies.recipeRepository.create(Recipe(
            title: "Account-bound Export",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        let probe = ArchiveAuthorizationProbe()
        let scope = SyncOperationAccountScope(ownerId: ownerID, revision: UUID())
        let service = makeService(
            dependencies,
            captureAccountScope: { _ in scope },
            permitsAccountScope: { _ in await probe.permits() },
            exportCheckpoint: { checkpoint in
                if checkpoint == .recipesFetched { await probe.revoke() }
            }
        )

        do {
            _ = try await service.export(ownerID: ownerID)
            XCTFail("Expected account-boundary failure")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .accountAuthorizationChanged)
        }
    }

    func testDecodeRejectsSmallEncodedImageWithOversizedDeclaredDimensions() async throws {
        let dependencies = DependencyContainer.preview()
        let recipeID = UUID()
        let safeGIF = try makeGIF(width: 1, height: 1)
        XCTAssertTrue(LibraryArchiveService.archiveImageMetadataIsSafe(safeGIF))

        // ImageIO itself creates this standards-valid GIF. Its single-row
        // raster keeps the encoded fixture tiny while exceeding the allowed
        // pixel dimension by one, rather than relying on a malformed header.
        let oversizedGIF = try makeGIF(
            width: LibraryArchiveService.maximumImagePixelDimension + 1,
            height: 1
        )
        XCTAssertLessThan(oversizedGIF.count, 1_000)
        XCTAssertFalse(LibraryArchiveService.archiveImageMetadataIsSafe(oversizedGIF))

        let recipe = Recipe(
            id: recipeID,
            title: "Metadata Bomb",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")]
        )
        let archive = LibraryArchive(
            recipes: [PortableRecipe(recipe: recipe, imageData: oversizedGIF)],
            collections: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        do {
            _ = try await dependencies.libraryArchiveService.decodeAndValidate(data)
            XCTFail("Expected oversized declared image dimensions to be rejected")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .invalidImage(recipeID))
        }
    }

    func testImageMetadataValidationChecksEveryFrameAndFrameCount() throws {
        let oversizedSecondFrame = try makeGIF(frames: [
            (width: 1, height: 1),
            (width: LibraryArchiveService.maximumImagePixelDimension + 1, height: 1),
        ])
        XCTAssertFalse(LibraryArchiveService.archiveImageMetadataIsSafe(oversizedSecondFrame))

        let tooManyFrames = try makeGIF(
            frames: Array(
                repeating: (width: 1, height: 1),
                count: LibraryArchiveService.maximumImageFrameCount + 1
            )
        )
        XCTAssertFalse(LibraryArchiveService.archiveImageMetadataIsSafe(tooManyFrames))
    }

    func testNormalImageMetadataAndBoundedDownsamplingRemainCompatible() throws {
        let normalImage = try makeGIF(width: 2_400, height: 1_200)
        XCTAssertTrue(LibraryArchiveService.archiveImageMetadataIsSafe(normalImage))

        let downsampled = try XCTUnwrap(
            LibraryArchiveService.downsampledArchiveImage(from: normalImage)
        )
        let pixelWidth = downsampled.size.width * downsampled.scale
        let pixelHeight = downsampled.size.height * downsampled.scale
        XCTAssertLessThanOrEqual(pixelWidth, CGFloat(LibraryArchiveService.restoreThumbnailPixelDimension))
        XCTAssertLessThanOrEqual(pixelHeight, CGFloat(LibraryArchiveService.restoreThumbnailPixelDimension))
        XCTAssertEqual(pixelWidth / pixelHeight, 2, accuracy: 0.01)
    }

    func testRestoreRemapsDeletedCollectionIdentityAndPreservesTombstone() async throws {
        let ownerID = UUID()
        let recipeID = UUID()
        let collectionID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            id: recipeID,
            title: "Restored Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        try await source.collectionRepository.create(Collection(
            id: collectionID,
            name: "Deleted Then Restored",
            userId: ownerID,
            recipeIds: [recipeID]
        ))
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)

        let target = DependencyContainer.preview()
        setCurrentUser(ownerID)
        let context = ModelContext(target.modelContainer)
        context.insert(DeletedRecipeModel(
            recipeId: recipeID,
            ownerId: ownerID,
            deletedAt: Date(),
            cloudRecordName: nil
        ))
        context.insert(DeletedCollectionModel(
            collectionId: collectionID,
            ownerId: ownerID,
            deletedAt: Date(),
            cloudRecordName: nil
        ))
        try context.save()

        let first = try await target.libraryArchiveService.restore(archive, ownerID: ownerID)
        XCTAssertEqual(first.collectionsInserted, 1)
        let restoredCollections = try await target.collectionRepository.fetchUserCollections(ownerId: ownerID)
        let restored = try XCTUnwrap(restoredCollections.first)
        let restoredRecipes = try await target.recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        let restoredRecipe = try XCTUnwrap(restoredRecipes.first)
        XCTAssertNotEqual(restoredRecipe.id, recipeID)
        XCTAssertNotEqual(restored.id, collectionID)
        XCTAssertEqual(restored.recipeIds, [restoredRecipe.id])
        let originalRecipe = try await target.recipeRepository.fetch(id: recipeID, preferredOwnerId: ownerID)
        XCTAssertNil(originalRecipe)
        let originalCollection = try await target.collectionRepository.fetch(id: collectionID)
        XCTAssertNil(originalCollection)

        let tombstones = try context.fetch(FetchDescriptor<DeletedCollectionModel>())
        XCTAssertEqual(tombstones.compactMap(\.collectionId), [collectionID])
        let recipeTombstones = try context.fetch(FetchDescriptor<DeletedRecipeModel>())
        XCTAssertEqual(recipeTombstones.compactMap(\.recipeId), [recipeID])

        let second = try await target.libraryArchiveService.restore(archive, ownerID: ownerID)
        XCTAssertEqual(second.collectionsKept, 1)
        let restoredCollectionCount = try await target.collectionRepository
            .fetchUserCollections(ownerId: ownerID)
            .count
        XCTAssertEqual(restoredCollectionCount, 1)
    }

    func testRestoreIgnoresAnotherOwnersRecipeTombstone() async throws {
        let ownerID = UUID()
        let otherOwnerID = UUID()
        let recipeID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            id: recipeID,
            title: "Owner-Scoped Restore",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)

        let target = DependencyContainer.preview()
        setCurrentUser(ownerID)
        let context = ModelContext(target.modelContainer)
        context.insert(DeletedRecipeModel(
            recipeId: recipeID,
            ownerId: otherOwnerID,
            deletedAt: Date(),
            cloudRecordName: nil
        ))
        try context.save()

        let report = try await target.libraryArchiveService.restore(archive, ownerID: ownerID)
        XCTAssertEqual(report.recipesInserted, 1)
        let restored = try await target.recipeRepository.fetch(
            id: recipeID,
            preferredOwnerId: ownerID
        )
        XCTAssertEqual(restored?.id, recipeID)
        XCTAssertEqual(restored?.ownerId, ownerID)

        let tombstones = try context.fetch(FetchDescriptor<DeletedRecipeModel>())
        XCTAssertTrue(tombstones.contains {
            $0.recipeId == recipeID && $0.ownerId == otherOwnerID
        })
    }

    func testInjectedRemoteHistorySuccessKeepsUnretiredStableID() async throws {
        let ownerID = UUID()
        let recipeID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            id: recipeID,
            title: "Remote History Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)
        let target = DependencyContainer.preview()
        let service = makeService(target, fetchRemoteDeletedRecipeIDs: { _ in [] })

        _ = try await service.restore(archive, ownerID: ownerID)

        let restored = try await target.recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        XCTAssertEqual(restored.map(\.id), [recipeID])
    }

    func testInjectedRemoteHistoryFailurePessimisticallyRemapsStableID() async throws {
        enum Expected: Error { case offline }
        let ownerID = UUID()
        let recipeID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            id: recipeID,
            title: "Offline History Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)
        let target = DependencyContainer.preview()
        let service = makeService(target, fetchRemoteDeletedRecipeIDs: { _ in throw Expected.offline })

        _ = try await service.restore(archive, ownerID: ownerID)

        let restored = try await target.recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        XCTAssertEqual(restored.count, 1)
        XCTAssertNotEqual(restored.first?.id, recipeID)
    }

    func testRestoreStopsAfterAccountAuthorizationChangesAndKeepsSafePartialResult() async throws {
        let ownerID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        for index in 0..<2 {
            try await source.recipeRepository.create(Recipe(
                title: "Recipe \(index)",
                ingredients: [Ingredient(name: "Ingredient")],
                steps: [CookStep(index: 0, text: "Cook")],
                ownerId: ownerID,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ), skipCloudSync: true)
        }
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)
        let target = DependencyContainer.preview()
        let probe = ArchiveAuthorizationProbe()
        let scope = SyncOperationAccountScope(ownerId: ownerID, revision: UUID())
        let service = makeService(
            target,
            captureAccountScope: { _ in scope },
            permitsAccountScope: { _ in await probe.permits() },
            restoreCheckpoint: { checkpoint in
                if checkpoint == .recipeCommitted(1) { await probe.revoke() }
            }
        )

        do {
            _ = try await service.restore(archive, ownerID: ownerID, progress: { report in
                await probe.record(report)
            })
            XCTFail("Expected account-boundary failure")
        } catch let error as LibraryArchiveService.ArchiveError {
            XCTAssertEqual(error, .accountAuthorizationChanged)
        }
        let restored = try await target.recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        XCTAssertEqual(restored.count, 1)
        let partialReport = await probe.progress()
        XCTAssertEqual(partialReport?.recipesInserted, 1)
    }

    func testConcurrentSameOwnerRestoresDoNotCreateDuplicateRows() async throws {
        let ownerID = UUID()
        let recipeID = UUID()
        let collectionID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            id: recipeID,
            title: "Serialized Restore",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        try await source.collectionRepository.create(Collection(
            id: collectionID,
            name: "Serialized Collection",
            userId: ownerID,
            recipeIds: [recipeID]
        ))
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)

        let target = DependencyContainer.preview()
        let probe = ArchiveConcurrentRestoreProbe()
        let service = makeService(target, restoreCheckpoint: { checkpoint in
            guard checkpoint == .leaseAcquired else { return }
            await probe.pauseFirstRestoreAtCheckpoint()
        })

        let firstTask = Task { try await service.restore(archive, ownerID: ownerID) }
        await probe.waitUntilFirstCheckpoint()
        let secondTask = Task { try await service.restore(archive, ownerID: ownerID) }
        for _ in 0..<20 { await Task.yield() }
        await probe.releaseFirstRestore()

        let first = try await firstTask.value
        let second = try await secondTask.value
        XCTAssertEqual(first.recipesInserted, 1)
        XCTAssertEqual(first.collectionsInserted, 1)
        XCTAssertEqual(second.recipesKept, 1)
        XCTAssertEqual(second.collectionsKept, 1)

        let context = ModelContext(target.modelContainer)
        let recipeRows = try context.fetch(FetchDescriptor<RecipeModel>()).filter {
            $0.ownerId == ownerID && $0.id == recipeID
        }
        let collectionRows = try context.fetch(FetchDescriptor<CollectionModel>()).filter {
            $0.userId == ownerID && $0.id == collectionID
        }
        XCTAssertEqual(recipeRows.count, 1)
        XCTAssertEqual(collectionRows.count, 1)
        let restoredCollection = try await target.collectionRepository.fetch(id: collectionID)
        XCTAssertEqual(restoredCollection?.recipeIds, [recipeID])
    }

    func testRestoreLeaseMakesConcurrentAccountDeletionWaitForRestore() async throws {
        let ownerID = UUID()
        let source = DependencyContainer.preview()
        setCurrentUser(ownerID)
        try await source.recipeRepository.create(Recipe(
            title: "Lease Recipe",
            ingredients: [Ingredient(name: "Ingredient")],
            steps: [CookStep(index: 0, text: "Cook")],
            ownerId: ownerID
        ), skipCloudSync: true)
        let archive = try await source.libraryArchiveService.export(ownerID: ownerID)
        let target = DependencyContainer.preview()
        let probe = ArchiveDeletionProbe()
        let service = makeService(target, restoreCheckpoint: { checkpoint in
            guard checkpoint == .leaseAcquired else { return }
            await probe.start(ownerID: ownerID)
            await Task.yield()
            await probe.markObservedWaitingIfNeeded()
        })

        let report = try await service.restore(archive, ownerID: ownerID)
        XCTAssertEqual(report.recipesInserted, 1)
        await probe.waitUntilCompleted()
        let didObserveWaiting = await probe.didObserveWaiting()
        let didComplete = await probe.hasCompleted()
        XCTAssertTrue(didObserveWaiting)
        XCTAssertTrue(didComplete)
    }

    private func makeService(
        _ dependencies: DependencyContainer,
        maximumSingleImageBytes: Int = LibraryArchiveService.maximumSingleImageBytes,
        maximumTotalImageBytes: Int = LibraryArchiveService.maximumDecodedImageBytes,
        captureAccountScope: @escaping @Sendable (UUID) async -> SyncOperationAccountScope? = {
            SyncOperationAccountScope(ownerId: $0, revision: UUID())
        },
        permitsAccountScope: @escaping @Sendable (SyncOperationAccountScope) async -> Bool = { _ in true },
        restoreCheckpoint: (@Sendable (LibraryArchiveService.RestoreCheckpoint) async -> Void)? = nil,
        exportCheckpoint: (@Sendable (LibraryArchiveService.ExportCheckpoint) async -> Void)? = nil,
        fetchRemoteDeletedRecipeIDs: (@Sendable (UUID) async throws -> Set<UUID>)? = nil
    ) -> LibraryArchiveService {
        LibraryArchiveService(
            recipeRepository: dependencies.recipeRepository,
            collectionRepository: dependencies.collectionRepository,
            modelContainer: dependencies.modelContainer,
            imageManager: dependencies.imageManager,
            collectionImageManager: dependencies.collectionImageManager,
            maximumSingleImageBytes: maximumSingleImageBytes,
            maximumTotalImageBytes: maximumTotalImageBytes,
            captureAccountScope: captureAccountScope,
            permitsAccountScope: permitsAccountScope,
            restoreCheckpoint: restoreCheckpoint,
            exportCheckpoint: exportCheckpoint,
            fetchRemoteDeletedRecipeIDs: fetchRemoteDeletedRecipeIDs
        )
    }

    private func setCurrentUser(_ id: UUID) {
        CurrentUserSession.shared.replaceCurrentUserIfChanged(User(
            id: id,
            username: "archive-\(id.uuidString.prefix(6))",
            displayName: "Archive Tester",
            createdAt: Date()
        ))
    }

    private func encodeArchive(_ archive: LibraryArchive) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(archive)
    }

    private func makeGIF(width: Int, height: Int) throws -> Data {
        try makeGIF(frames: [(width: width, height: height)])
    }

    private func makeGIF(frames: [(width: Int, height: Int)]) throws -> Data {
        let images = try frames.map { dimensions -> CGImage in
            let bytesPerRow = try XCTUnwrap(
                dimensions.width.multipliedReportingOverflow(by: 4).overflow
                    ? nil
                    : dimensions.width * 4
            )
            let context = try XCTUnwrap(CGContext(
                data: nil,
                width: dimensions.width,
                height: dimensions.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            return try XCTUnwrap(context.makeImage())
        }

        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data,
            UTType.gif.identifier as CFString,
            images.count,
            nil
        ))
        images.forEach { CGImageDestinationAddImage(destination, $0, nil) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
