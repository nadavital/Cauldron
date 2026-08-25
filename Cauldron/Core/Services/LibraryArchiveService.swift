import Foundation
import CryptoKit
import SwiftData
import UIKit
import ImageIO

nonisolated struct LibraryArchive: Codable, Sendable {
    nonisolated static let currentVersion = 1

    var version: Int
    var exportedAt: Date
    /// The account that owned the exported library. Archives created before
    /// this field existed decode it as `nil` and are treated as foreign.
    var sourceOwnerID: UUID?
    var recipes: [PortableRecipe]
    var collections: [PortableCollection]

    nonisolated init(
        version: Int = LibraryArchive.currentVersion,
        exportedAt: Date = Date(),
        sourceOwnerID: UUID? = nil,
        recipes: [PortableRecipe],
        collections: [PortableCollection]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.sourceOwnerID = sourceOwnerID
        self.recipes = recipes
        self.collections = collections
    }
}

nonisolated struct PortableRecipe: Codable, Sendable {
    var id: UUID
    var title: String
    var ingredients: [Ingredient]
    var steps: [CookStep]
    var yields: String
    var totalMinutes: Int?
    var tags: [Tag]
    var nutrition: Nutrition?
    var sourceURL: URL?
    var sourceTitle: String?
    var notes: String?
    var isFavorite: Bool
    var visibility: RecipeVisibility
    var originalCreatorName: String?
    var originalRecipeID: UUID?
    var originalCreatorID: UUID?
    var savedAt: Date?
    var sourceRecipeUpdatedAt: Date?
    var followsSourceUpdates: Bool?
    var relatedRecipeIDs: [UUID]?
    /// Compressed image bytes. Optional so archives exported before image
    /// support remain readable.
    var imageData: Data?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(recipe: Recipe, imageData: Data? = nil) {
        id = recipe.id
        title = recipe.title
        ingredients = recipe.ingredients
        steps = recipe.steps
        yields = recipe.yields
        totalMinutes = recipe.totalMinutes
        tags = recipe.tags
        nutrition = recipe.nutrition
        sourceURL = recipe.sourceURL
        sourceTitle = recipe.sourceTitle
        notes = recipe.notes
        isFavorite = recipe.isFavorite
        visibility = recipe.visibility
        originalCreatorName = recipe.originalCreatorName
        originalRecipeID = recipe.originalRecipeId
        originalCreatorID = recipe.originalCreatorId
        savedAt = recipe.savedAt
        sourceRecipeUpdatedAt = recipe.sourceRecipeUpdatedAt
        followsSourceUpdates = recipe.followsSourceUpdates
        relatedRecipeIDs = recipe.relatedRecipeIds
        self.imageData = imageData
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
    }

    nonisolated func restored(
        id restoredID: UUID,
        ownerID: UUID,
        imageURL: URL?,
        relatedRecipeIDs restoredRelatedRecipeIDs: [UUID]
    ) -> Recipe {
        Recipe(
            id: restoredID,
            title: title,
            ingredients: ingredients,
            steps: steps,
            yields: yields,
            totalMinutes: totalMinutes,
            tags: tags,
            nutrition: nutrition,
            sourceURL: sourceURL,
            sourceTitle: sourceTitle,
            notes: notes,
            imageURL: imageURL,
            isFavorite: isFavorite,
            visibility: visibility,
            ownerId: ownerID,
            cloudRecordName: nil,
            cloudImageRecordName: nil,
            imageModifiedAt: imageData == nil ? nil : updatedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalRecipeId: originalRecipeID,
            originalCreatorId: originalCreatorID,
            originalCreatorName: originalCreatorName,
            savedAt: savedAt,
            sourceRecipeUpdatedAt: sourceRecipeUpdatedAt,
            followsSourceUpdates: followsSourceUpdates ?? false,
            relatedRecipeIds: restoredRelatedRecipeIDs,
            isPreview: false
        )
    }

}

nonisolated struct PortableCollection: Codable, Sendable {
    var id: UUID
    var name: String
    var description: String?
    var recipeIDs: [UUID]
    var visibility: RecipeVisibility
    var emoji: String?
    var symbolName: String?
    var color: String?
    var coverImageType: CoverImageType
    var originalCollectionID: UUID?
    var originalCollectionOwnerID: UUID?
    var originalCollectionName: String?
    var savedAt: Date?
    var sourceCollectionUpdatedAt: Date?
    var followsSourceUpdates: Bool?
    /// Compressed custom cover bytes. Optional for archives exported before
    /// collection cover support.
    var coverImageData: Data?
    var createdAt: Date
    var updatedAt: Date

    nonisolated init(collection: Collection, coverImageData: Data? = nil) {
        id = collection.id
        name = collection.name
        description = collection.description
        recipeIDs = collection.recipeIds
        visibility = collection.visibility
        emoji = collection.emoji
        symbolName = collection.symbolName
        color = collection.color
        coverImageType = collection.coverImageType
        originalCollectionID = collection.originalCollectionId
        originalCollectionOwnerID = collection.originalCollectionOwnerId
        originalCollectionName = collection.originalCollectionName
        savedAt = collection.savedAt
        sourceCollectionUpdatedAt = collection.sourceCollectionUpdatedAt
        followsSourceUpdates = collection.followsSourceUpdates
        self.coverImageData = coverImageData
        createdAt = collection.createdAt
        updatedAt = collection.updatedAt
    }

    nonisolated func restored(
        id restoredID: UUID,
        ownerID: UUID,
        recipeIDs: [UUID],
        coverImageURL: URL?
    ) -> Collection {
        Collection(
            id: restoredID,
            name: name,
            description: description,
            userId: ownerID,
            recipeIds: recipeIDs,
            visibility: visibility,
            emoji: emoji,
            symbolName: symbolName,
            color: color,
            coverImageType: coverImageType,
            coverImageURL: coverImageURL,
            cloudCoverImageRecordName: nil,
            coverImageModifiedAt: coverImageData == nil ? nil : updatedAt,
            cloudRecordName: nil,
            originalCollectionId: originalCollectionID,
            originalCollectionOwnerId: originalCollectionOwnerID,
            originalCollectionName: originalCollectionName,
            savedAt: savedAt,
            sourceCollectionUpdatedAt: sourceCollectionUpdatedAt,
            followsSourceUpdates: followsSourceUpdates ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

}

actor LibraryArchiveService {
    nonisolated static let defaultMaximumArchiveBytes = 400_000_000
    nonisolated static let maximumSingleImageBytes = 5_000_000
    nonisolated static let maximumDecodedImageBytes = 250_000_000
    nonisolated static let maximumImagePixelDimension = 16_384
    nonisolated static let maximumImagePixelCount = 100_000_000
    nonisolated static let maximumImageFrameCount = 16
    nonisolated static let restoreThumbnailPixelDimension = 2_000
    nonisolated static let maximumArchiveFutureClockSkew: TimeInterval = 86_400

    nonisolated struct RestoreReport: Sendable, Equatable {
        var recipesInserted = 0
        var recipesUpdated = 0
        var recipesKept = 0
        var collectionsInserted = 0
        var collectionsUpdated = 0
        var collectionsKept = 0
        var imagesRestored = 0
        var membershipsSkipped = 0
    }

    /// Restore is an idempotent merge. Stable IDs are retained for same-account
    /// archives unless they collide with another owner or deletion-wins
    /// history. Foreign and legacy archives receive deterministic replacement
    /// IDs so a new account never publishes another creator's record identity.
    enum CollisionPolicy: Sendable {
        case preferNewestKeepingStableIDs
    }

    enum ArchiveError: Error, Equatable {
        case unsupportedVersion(Int)
        case invalidRecipe(UUID)
        case duplicateRecipeID(UUID)
        case duplicateCollectionID(UUID)
        case archiveTooLarge
        case imageTooLarge(UUID)
        case collectionImageTooLarge(UUID)
        case archiveImagesTooLarge
        case invalidImage(UUID)
        case invalidCollectionImage(UUID)
        case invalidArchiveTimestamp
        case invalidRecipeTimestamp(UUID)
        case invalidCollectionTimestamp(UUID)
        case accountAuthorizationUnavailable
        case accountAuthorizationChanged
        case accountDeletionInProgress
    }

    enum RestoreCheckpoint: Sendable, Equatable {
        case leaseAcquired
        case recipeCommitted(Int)
        case collectionCommitted(Int)
    }

    enum ExportCheckpoint: Sendable, Equatable {
        case recipesFetched
        case recipeImageLoaded(Int)
        case collectionsFetched
        case collectionImageLoaded(Int)
        case beforeReturn
    }

    private let recipeRepository: RecipeRepository
    private let collectionRepository: CollectionRepository
    private let modelContainer: ModelContainer
    private let imageManager: RecipeImageManager
    private let collectionImageManager: CollectionImageManagerV2
    private let maximumArchiveBytes: Int
    private let maximumSingleArchiveImageBytes: Int
    private let maximumArchiveImageBytes: Int
    private let fetchRemoteDeletedRecipeIDs: (@Sendable (UUID) async throws -> Set<UUID>)?
    private let fetchRemoteDeletedCollectionIDs: (@Sendable (UUID) async throws -> Set<UUID>)?
    private let captureAccountScope: @Sendable (UUID) async -> SyncOperationAccountScope?
    private let permitsAccountScope: @Sendable (SyncOperationAccountScope) async -> Bool
    private let restoreCheckpoint: (@Sendable (RestoreCheckpoint) async -> Void)?
    private let exportCheckpoint: (@Sendable (ExportCheckpoint) async -> Void)?
    private var activeRestoreOwners: Set<UUID> = []
    private var restoreWaiters: [UUID: [CheckedContinuation<Void, Never>]] = [:]

    init(
        recipeRepository: RecipeRepository,
        collectionRepository: CollectionRepository,
        modelContainer: ModelContainer,
        imageManager: RecipeImageManager,
        collectionImageManager: CollectionImageManagerV2,
        maximumArchiveBytes: Int = LibraryArchiveService.defaultMaximumArchiveBytes,
        maximumSingleImageBytes: Int = LibraryArchiveService.maximumSingleImageBytes,
        maximumTotalImageBytes: Int = LibraryArchiveService.maximumDecodedImageBytes,
        captureAccountScope: @escaping @Sendable (UUID) async -> SyncOperationAccountScope? = {
            SyncOperationAccountScope(ownerId: $0, revision: UUID())
        },
        permitsAccountScope: @escaping @Sendable (SyncOperationAccountScope) async -> Bool = { _ in true },
        restoreCheckpoint: (@Sendable (RestoreCheckpoint) async -> Void)? = nil,
        exportCheckpoint: (@Sendable (ExportCheckpoint) async -> Void)? = nil,
        fetchRemoteDeletedRecipeIDs: (@Sendable (UUID) async throws -> Set<UUID>)? = nil,
        fetchRemoteDeletedCollectionIDs: (@Sendable (UUID) async throws -> Set<UUID>)? = nil
    ) {
        self.recipeRepository = recipeRepository
        self.collectionRepository = collectionRepository
        self.modelContainer = modelContainer
        self.imageManager = imageManager
        self.collectionImageManager = collectionImageManager
        self.maximumArchiveBytes = maximumArchiveBytes
        self.maximumSingleArchiveImageBytes = maximumSingleImageBytes
        self.maximumArchiveImageBytes = maximumTotalImageBytes
        self.captureAccountScope = captureAccountScope
        self.permitsAccountScope = permitsAccountScope
        self.restoreCheckpoint = restoreCheckpoint
        self.exportCheckpoint = exportCheckpoint
        self.fetchRemoteDeletedRecipeIDs = fetchRemoteDeletedRecipeIDs
        self.fetchRemoteDeletedCollectionIDs = fetchRemoteDeletedCollectionIDs
    }

    func export(ownerID: UUID, now: Date = Date()) async throws -> Data {
        guard let accountScope = await captureAccountScope(ownerID) else {
            throw ArchiveError.accountAuthorizationUnavailable
        }
        async let recipes = recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        async let collections = collectionRepository.fetchUserCollections(ownerId: ownerID)
        let ownedRecipes = try await recipes
        await exportCheckpoint?(.recipesFetched)
        try await requireAccountScope(accountScope)
        var portableRecipes: [PortableRecipe] = []
        var totalImageBytes = 0
        portableRecipes.reserveCapacity(ownedRecipes.count)
        for (index, recipe) in ownedRecipes.enumerated() {
            let imageData = await imageManager.loadImage(recipeId: recipe.id)?.jpegData(compressionQuality: 0.9)
            await exportCheckpoint?(.recipeImageLoaded(index + 1))
            try await requireAccountScope(accountScope)
            if let imageData {
                totalImageBytes = try validatedImageByteTotal(
                    currentTotal: totalImageBytes,
                    imageData: imageData,
                    oversizedError: .imageTooLarge(recipe.id),
                    invalidError: .invalidImage(recipe.id)
                )
            }
            portableRecipes.append(PortableRecipe(recipe: recipe, imageData: imageData))
        }
        let ownedCollections = try await collections
        await exportCheckpoint?(.collectionsFetched)
        try await requireAccountScope(accountScope)
        var portableCollections: [PortableCollection] = []
        portableCollections.reserveCapacity(ownedCollections.count)
        for (index, collection) in ownedCollections.enumerated() {
            let coverImageData: Data?
            if collection.coverImageType == .customImage {
                coverImageData = await collectionImageManager.loadImage(collectionId: collection.id)?
                    .jpegData(compressionQuality: 0.9)
            } else {
                coverImageData = nil
            }
            await exportCheckpoint?(.collectionImageLoaded(index + 1))
            try await requireAccountScope(accountScope)
            if let coverImageData {
                totalImageBytes = try validatedImageByteTotal(
                    currentTotal: totalImageBytes,
                    imageData: coverImageData,
                    oversizedError: .collectionImageTooLarge(collection.id),
                    invalidError: .invalidCollectionImage(collection.id)
                )
            }
            portableCollections.append(PortableCollection(
                collection: collection,
                coverImageData: coverImageData
            ))
        }
        let archive = LibraryArchive(
            exportedAt: now,
            sourceOwnerID: ownerID,
            recipes: portableRecipes,
            collections: portableCollections
        )
        let data = try JSONEncoder.cauldronArchive.encode(archive)
        guard data.count <= maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge
        }
        await exportCheckpoint?(.beforeReturn)
        try await requireAccountScope(accountScope)
        return data
    }

    func decodeAndValidate(_ data: Data, now: Date = Date()) throws -> LibraryArchive {
        guard data.count <= maximumArchiveBytes else {
            throw ArchiveError.archiveTooLarge
        }
        var archive = try JSONDecoder.cauldronArchive.decode(LibraryArchive.self, from: data)
        guard archive.version == LibraryArchive.currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.version)
        }
        let futureLimit = now.addingTimeInterval(Self.maximumArchiveFutureClockSkew)
        guard archive.exportedAt <= futureLimit else {
            throw ArchiveError.invalidArchiveTimestamp
        }
        let exportChronologyLimit = archive.exportedAt.addingTimeInterval(Self.maximumArchiveFutureClockSkew)
        archive.exportedAt = min(archive.exportedAt, now)
        var recipeIDs = Set<UUID>()
        var totalImageBytes = 0
        for index in archive.recipes.indices {
            var recipe = archive.recipes[index]
            guard !recipe.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !recipe.ingredients.isEmpty,
                  !recipe.steps.isEmpty else {
                throw ArchiveError.invalidRecipe(recipe.id)
            }
            guard recipeIDs.insert(recipe.id).inserted else {
                throw ArchiveError.duplicateRecipeID(recipe.id)
            }
            let timestamps = [recipe.createdAt, recipe.updatedAt]
                + [recipe.savedAt, recipe.sourceRecipeUpdatedAt].compactMap { $0 }
            guard recipe.createdAt <= recipe.updatedAt,
                  timestamps.allSatisfy({ $0 <= futureLimit && $0 <= exportChronologyLimit }) else {
                throw ArchiveError.invalidRecipeTimestamp(recipe.id)
            }
            recipe.createdAt = min(recipe.createdAt, now)
            recipe.updatedAt = min(recipe.updatedAt, now)
            recipe.savedAt = recipe.savedAt.map { min($0, now) }
            recipe.sourceRecipeUpdatedAt = recipe.sourceRecipeUpdatedAt.map { min($0, now) }
            archive.recipes[index] = recipe
            if let imageData = recipe.imageData {
                totalImageBytes = try validatedImageByteTotal(
                    currentTotal: totalImageBytes,
                    imageData: imageData,
                    oversizedError: .imageTooLarge(recipe.id),
                    invalidError: .invalidImage(recipe.id)
                )
            }
        }
        var collectionIDs = Set<UUID>()
        for index in archive.collections.indices {
            var collection = archive.collections[index]
            guard collectionIDs.insert(collection.id).inserted else {
                throw ArchiveError.duplicateCollectionID(collection.id)
            }
            let timestamps = [collection.createdAt, collection.updatedAt]
                + [collection.savedAt, collection.sourceCollectionUpdatedAt].compactMap { $0 }
            guard collection.createdAt <= collection.updatedAt,
                  timestamps.allSatisfy({ $0 <= futureLimit && $0 <= exportChronologyLimit }) else {
                throw ArchiveError.invalidCollectionTimestamp(collection.id)
            }
            collection.createdAt = min(collection.createdAt, now)
            collection.updatedAt = min(collection.updatedAt, now)
            collection.savedAt = collection.savedAt.map { min($0, now) }
            collection.sourceCollectionUpdatedAt = collection.sourceCollectionUpdatedAt.map { min($0, now) }
            archive.collections[index] = collection
            if let imageData = collection.coverImageData {
                totalImageBytes = try validatedImageByteTotal(
                    currentTotal: totalImageBytes,
                    imageData: imageData,
                    oversizedError: .collectionImageTooLarge(collection.id),
                    invalidError: .invalidCollectionImage(collection.id)
                )
            }
        }
        return archive
    }

    private func validatedImageByteTotal(
        currentTotal: Int,
        imageData: Data,
        oversizedError: ArchiveError,
        invalidError: ArchiveError
    ) throws -> Int {
        guard imageData.count <= maximumSingleArchiveImageBytes else {
            throw oversizedError
        }
        guard Self.archiveImageMetadataIsSafe(imageData) else {
            throw invalidError
        }
        let (newTotal, overflowed) = currentTotal.addingReportingOverflow(imageData.count)
        guard !overflowed, newTotal <= maximumArchiveImageBytes else {
            throw ArchiveError.archiveImagesTooLarge
        }
        return newTotal
    }

    /// Reads container metadata only. `UIImage(data:)` may eagerly allocate the
    /// declared raster, so it must never be used as the archive validity probe.
    nonisolated static func archiveImageMetadataIsSafe(_ data: Data) -> Bool {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return false
        }
        let frameCount = CGImageSourceGetCount(source)
        guard CGImageSourceGetStatus(source) == .statusComplete,
              frameCount > 0,
              frameCount <= maximumImageFrameCount else {
            return false
        }

        // Containers such as GIF and TIFF may give every frame independent
        // dimensions. Checking only frame zero lets a later frame retain a
        // hostile declared raster even though restore displays frame zero.
        for frameIndex in 0..<frameCount {
            guard CGImageSourceGetStatusAtIndex(source, frameIndex) == .statusComplete,
                  let rawProperties = CGImageSourceCopyPropertiesAtIndex(
                      source,
                      frameIndex,
                      sourceOptions
                  ),
                  let properties = rawProperties as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.uint64Value,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.uint64Value,
                  width > 0,
                  height > 0,
                  width <= UInt64(maximumImagePixelDimension),
                  height <= UInt64(maximumImagePixelDimension) else {
                return false
            }
            let (pixelCount, overflowed) = width.multipliedReportingOverflow(by: height)
            guard !overflowed, pixelCount <= UInt64(maximumImagePixelCount) else {
                return false
            }
        }
        return true
    }

    /// ImageIO creates the thumbnail directly from encoded bytes, bounding the
    /// decoded allocation before a UIImage reaches the normal image pipeline.
    nonisolated static func downsampledArchiveImage(from data: Data) -> UIImage? {
        guard archiveImageMetadataIsSafe(data),
              let source = CGImageSourceCreateWithData(
                  data as CFData,
                  [kCGImageSourceShouldCache: false] as CFDictionary
              ),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: restoreThumbnailPixelDimension,
              ] as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }

    @discardableResult
    /// `progress` is invoked after every durable recipe or collection commit.
    /// If restore later throws, its last value is the exact partial result that
    /// callers can surface while explaining that retry is safe and idempotent.
    func restore(
        _ data: Data,
        ownerID: UUID,
        collisionPolicy: CollisionPolicy = .preferNewestKeepingStableIDs,
        progress: (@Sendable (RestoreReport) async -> Void)? = nil
    ) async throws -> RestoreReport {
        // This owner-keyed lease is registered before the first suspension in
        // restore, preventing actor reentrancy from taking duplicate snapshots
        // and inserting duplicate owner+ID rows.
        if !activeRestoreOwners.insert(ownerID).inserted {
            await withCheckedContinuation { continuation in
                restoreWaiters[ownerID, default: []].append(continuation)
            }
        }
        do {
            guard let accountScope = await captureAccountScope(ownerID) else {
                throw ArchiveError.accountAuthorizationUnavailable
            }
            guard let deletionLease = await AccountDeletionGate.shared.acquirePublicationLease(ownerID: ownerID) else {
                throw ArchiveError.accountDeletionInProgress
            }
            let report: RestoreReport
            do {
                await restoreCheckpoint?(.leaseAcquired)
                report = try await performRestore(
                    data,
                    ownerID: ownerID,
                    accountScope: accountScope,
                    collisionPolicy: collisionPolicy,
                    progress: progress
                )
                await AccountDeletionGate.shared.releasePublicationLease(deletionLease)
            } catch {
                await AccountDeletionGate.shared.releasePublicationLease(deletionLease)
                throw error
            }
            releaseRestoreLease(ownerID: ownerID)
            return report
        } catch {
            releaseRestoreLease(ownerID: ownerID)
            throw error
        }
    }

    private func releaseRestoreLease(ownerID: UUID) {
        if var waiters = restoreWaiters[ownerID], !waiters.isEmpty {
            let next = waiters.removeFirst()
            if waiters.isEmpty {
                restoreWaiters.removeValue(forKey: ownerID)
            } else {
                restoreWaiters[ownerID] = waiters
            }
            next.resume()
        } else {
            activeRestoreOwners.remove(ownerID)
        }
    }

    private func performRestore(
        _ data: Data,
        ownerID: UUID,
        accountScope: SyncOperationAccountScope,
        collisionPolicy: CollisionPolicy,
        progress: (@Sendable (RestoreReport) async -> Void)?
    ) async throws -> RestoreReport {
        try await requireAccountScope(accountScope)
        let archive = try decodeAndValidate(data)
        let isForeignArchive = archive.sourceOwnerID != ownerID
        var report = RestoreReport()

        let localRecipes = try await recipeRepository.fetchLibraryRecipes(ownerId: ownerID)
        try await requireAccountScope(accountScope)
        var localRecipeByID: [UUID: Recipe] = [:]
        for recipe in localRecipes {
            if let existing = localRecipeByID[recipe.id], existing.updatedAt >= recipe.updatedAt { continue }
            localRecipeByID[recipe.id] = recipe
        }
        let context = ModelContext(modelContainer)
        let allRecipeModels = try context.fetch(FetchDescriptor<RecipeModel>())
        let allRecipeIDs = Set(allRecipeModels.map(\.id))
        let targetRecipeIDs = Set(allRecipeModels.compactMap { model in
            model.ownerId == ownerID ? model.id : nil
        })
        let foreignRecipeIDs = Set(allRecipeModels.compactMap { model in
            model.ownerId == ownerID ? nil : model.id
        })
        let localDeletedRecipeIDs = Set(
            try context.fetch(FetchDescriptor<DeletedRecipeModel>()).compactMap { tombstone in
                tombstone.ownerId == ownerID ? tombstone.recipeId : nil
            }
        )
        let remoteRecipeHistory = await remoteDeletionHistory(
            ownerID: ownerID,
            fetch: fetchRemoteDeletedRecipeIDs
        )
        try await requireAccountScope(accountScope)
        var assignedRecipeIDs = Set<UUID>()
        var recipeIDMap: [UUID: UUID] = [:]
        for portable in archive.recipes.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let requiresRemap = isForeignArchive
                || foreignRecipeIDs.contains(portable.id)
                || localDeletedRecipeIDs.contains(portable.id)
                || remoteRecipeHistory.ids.contains(portable.id)
                || (remoteRecipeHistory.isUnknown && !targetRecipeIDs.contains(portable.id))
            let restoredID = Self.archiveRestoreID(
                sourceID: portable.id,
                ownerID: ownerID,
                kind: "recipe",
                requiresRemap: requiresRemap,
                allExistingIDs: allRecipeIDs,
                targetOwnedIDs: targetRecipeIDs,
                retiredIDs: localDeletedRecipeIDs.union(remoteRecipeHistory.ids),
                assignedIDs: assignedRecipeIDs
            )
            recipeIDMap[portable.id] = restoredID
            assignedRecipeIDs.insert(restoredID)
        }

        let expectedDestinationRecipeIDs = Set(localRecipeByID.keys).union(recipeIDMap.values)
        for portable in archive.recipes.sorted(by: { $0.createdAt < $1.createdAt }) {
            try await requireAccountScope(accountScope)
            let restoredID = recipeIDMap[portable.id] ?? portable.id

            if let existing = localRecipeByID[restoredID] {
                switch collisionPolicy {
                case .preferNewestKeepingStableIDs:
                    guard portable.updatedAt > existing.updatedAt else {
                        report.recipesKept += 1
                        await progress?(report)
                        continue
                    }
                }
            }

            var restoredImageURL: URL?
            var imageReplacement: SavedImageReplacement?
            if let imageData = portable.imageData {
                guard let image = Self.downsampledArchiveImage(from: imageData) else {
                    throw ArchiveError.invalidImage(portable.id)
                }
                let preparedData = try await imageManager.prepareImageData(image)
                try await requireAccountScope(accountScope)
                let replacement = try await imageManager.commitPreparedImageData(
                    preparedData,
                    entityId: restoredID
                )
                imageReplacement = replacement
                restoredImageURL = replacement.url
            } else if await imageManager.imageExists(recipeId: restoredID) {
                restoredImageURL = await imageManager.imageURL(recipeId: restoredID)
            }
            do {
                try await requireAccountScope(accountScope)

                let relatedRecipeIDs = (portable.relatedRecipeIDs ?? []).map { relatedID in
                    recipeIDMap[relatedID] ?? relatedID
                }.filter(expectedDestinationRecipeIDs.contains)
                let restored = portable.restored(
                    id: restoredID,
                    ownerID: ownerID,
                    imageURL: restoredImageURL,
                    relatedRecipeIDs: relatedRecipeIDs
                )
                if localRecipeByID[restoredID] != nil {
                    try await recipeRepository.update(
                        restored,
                        shouldUpdateTimestamp: false,
                        skipImageSync: portable.imageData == nil
                    )
                    report.recipesUpdated += 1
                } else {
                    try await recipeRepository.create(restored)
                    report.recipesInserted += 1
                }
                if imageReplacement != nil { report.imagesRestored += 1 }
                localRecipeByID[restoredID] = restored
            } catch {
                if let imageReplacement {
                    await imageManager.rollbackImageReplacementIfUnchanged(
                        imageReplacement,
                        entityId: restoredID
                    )
                }
                throw error
            }
            await progress?(report)
            await restoreCheckpoint?(.recipeCommitted(report.recipesInserted + report.recipesUpdated))
        }

        let validRecipeIDs = Set(localRecipeByID.keys)
        let allCollectionModels = try context.fetch(FetchDescriptor<CollectionModel>())
        let allCollectionIDs = Set(allCollectionModels.map(\.id))
        let targetCollectionIDs = Set(allCollectionModels.compactMap { model in
            model.userId == ownerID ? model.id : nil
        })
        let foreignCollectionIDs = Set(allCollectionModels.compactMap { model in
            model.userId == ownerID ? nil : model.id
        })
        let localDeletedCollectionIDs = Set(
            try context.fetch(FetchDescriptor<DeletedCollectionModel>()).compactMap(\.collectionId)
        )
        let remoteCollectionHistory = await remoteDeletionHistory(
            ownerID: ownerID,
            fetch: fetchRemoteDeletedCollectionIDs
        )
        try await requireAccountScope(accountScope)
        var localCollectionByID: [UUID: Collection] = [:]
        for collection in try await collectionRepository.fetchUserCollections(ownerId: ownerID) {
            if let existing = localCollectionByID[collection.id], existing.updatedAt >= collection.updatedAt { continue }
            localCollectionByID[collection.id] = collection
        }
        var assignedCollectionIDs = Set<UUID>()
        var collectionIDMap: [UUID: UUID] = [:]
        for portable in archive.collections.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let localDisposition = try await collectionRepository.archiveImportIdentityDisposition(
                collectionID: portable.id
            )
            let requiresRemap = isForeignArchive
                || foreignCollectionIDs.contains(portable.id)
                || localDisposition == .remapDeletedID
                || remoteCollectionHistory.ids.contains(portable.id)
                || (remoteCollectionHistory.isUnknown && !targetCollectionIDs.contains(portable.id))
            let restoredID = Self.archiveRestoreID(
                sourceID: portable.id,
                ownerID: ownerID,
                kind: "collection",
                requiresRemap: requiresRemap,
                allExistingIDs: allCollectionIDs,
                targetOwnedIDs: targetCollectionIDs,
                retiredIDs: localDeletedCollectionIDs.union(remoteCollectionHistory.ids),
                assignedIDs: assignedCollectionIDs
            )
            collectionIDMap[portable.id] = restoredID
            assignedCollectionIDs.insert(restoredID)
        }

        for portable in archive.collections.sorted(by: { $0.createdAt < $1.createdAt }) {
            try await requireAccountScope(accountScope)
            let restoredID = collectionIDMap[portable.id] ?? portable.id
            // Membership cannot point at absent recipes after a cross-account
            // restore. Its order is retained for every recipe that was restored
            // or already belongs to the destination account.
            let mappedRecipeIDs = portable.recipeIDs.map { recipeIDMap[$0] ?? $0 }
            let restoredIDs = mappedRecipeIDs.filter(validRecipeIDs.contains)
            report.membershipsSkipped += portable.recipeIDs.count - restoredIDs.count
            if let existing = localCollectionByID[restoredID] {
                switch collisionPolicy {
                case .preferNewestKeepingStableIDs:
                    guard portable.updatedAt > existing.updatedAt else {
                        report.collectionsKept += 1
                        await progress?(report)
                        continue
                    }
                }
            }

            var restoredCoverImageURL: URL?
            var coverImageReplacement: SavedImageReplacement?
            if let imageData = portable.coverImageData {
                guard let image = Self.downsampledArchiveImage(from: imageData) else {
                    throw ArchiveError.invalidCollectionImage(portable.id)
                }
                let preparedData = try await collectionImageManager.prepareImageData(image)
                try await requireAccountScope(accountScope)
                let replacement = try await collectionImageManager.commitPreparedImageData(
                    preparedData,
                    entityId: restoredID
                )
                coverImageReplacement = replacement
                restoredCoverImageURL = replacement.url
            } else if await collectionImageManager.imageExists(collectionId: restoredID) {
                restoredCoverImageURL = await collectionImageManager.imageURL(for: restoredID)
            }
            do {
                try await requireAccountScope(accountScope)

                let restored = portable.restored(
                    id: restoredID,
                    ownerID: ownerID,
                    recipeIDs: restoredIDs,
                    coverImageURL: restoredCoverImageURL
                )
                if localCollectionByID[restoredID] != nil {
                    try await collectionRepository.update(restored, shouldUpdateTimestamp: false)
                    report.collectionsUpdated += 1
                } else {
                    try await collectionRepository.create(restored)
                    report.collectionsInserted += 1
                }
                if coverImageReplacement != nil { report.imagesRestored += 1 }
                localCollectionByID[restoredID] = restored
            } catch {
                if let coverImageReplacement {
                    await collectionImageManager.rollbackImageReplacementIfUnchanged(
                        coverImageReplacement,
                        entityId: restoredID
                    )
                }
                throw error
            }
            await progress?(report)
            await restoreCheckpoint?(.collectionCommitted(report.collectionsInserted + report.collectionsUpdated))
        }

        try await requireAccountScope(accountScope)
        return report
    }

    private func requireAccountScope(_ scope: SyncOperationAccountScope) async throws {
        guard await permitsAccountScope(scope) else {
            // Mutations already committed before this boundary remain owned by
            // the originally authorized account. Restore stops immediately and
            // is safe to retry because the merge is idempotent/newest-wins.
            throw ArchiveError.accountAuthorizationChanged
        }
    }

    private nonisolated struct RemoteDeletionHistory: Sendable {
        let ids: Set<UUID>
        let isUnknown: Bool
    }

    private func remoteDeletionHistory(
        ownerID: UUID,
        fetch: (@Sendable (UUID) async throws -> Set<UUID>)?
    ) async -> RemoteDeletionHistory {
        guard !RuntimeEnvironment.isSimulatorQAMode,
              let fetch else {
            return RemoteDeletionHistory(ids: [], isUnknown: false)
        }
        do {
            return RemoteDeletionHistory(ids: try await fetch(ownerID), isUnknown: false)
        } catch {
            // An offline restore cannot prove that an old CloudKit tombstone is
            // absent. Deterministic remapping is safer than reviving IDs that
            // deletion-wins sync may immediately suppress.
            return RemoteDeletionHistory(ids: [], isUnknown: true)
        }
    }

    private nonisolated static func archiveRestoreID(
        sourceID: UUID,
        ownerID: UUID,
        kind: String,
        requiresRemap: Bool,
        allExistingIDs: Set<UUID>,
        targetOwnedIDs: Set<UUID>,
        retiredIDs: Set<UUID>,
        assignedIDs: Set<UUID>
    ) -> UUID {
        guard requiresRemap else { return sourceID }

        var salt = 0
        while true {
            let candidate = deterministicUUID(
                seed: "cauldron.archive.restore|\(kind)|\(ownerID.uuidString)|\(sourceID.uuidString)|\(salt)"
            )
            if targetOwnedIDs.contains(candidate) {
                return candidate
            }
            if !allExistingIDs.contains(candidate),
               !retiredIDs.contains(candidate),
               !assignedIDs.contains(candidate) {
                return candidate
            }
            salt += 1
        }
    }

    private nonisolated static func deterministicUUID(seed: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let value = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: value)!
    }

}

private extension JSONEncoder {
    nonisolated static var cauldronArchive: JSONEncoder {
        let encoder = JSONEncoder()
        // Numeric reference-date seconds retain Date's subsecond precision.
        // Older archives used whole-second ISO-8601 strings; the decoder below
        // intentionally accepts both representations.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var cauldronArchive: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self), seconds.isFinite {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let string = try value.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: value,
                    debugDescription: "Expected a numeric or ISO-8601 archive date"
                )
            }
            return date
        }
        return decoder
    }
}
