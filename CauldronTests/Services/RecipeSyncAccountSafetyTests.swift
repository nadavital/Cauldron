import SwiftData
import XCTest
@testable import Cauldron

@MainActor
final class RecipeSyncAccountSafetyTests: XCTestCase {
    func testPrivateRecipePublicationRejectsInvalidatedAccountContext() async throws {
        let ownerID = UUID()
        let context = VerifiedAccountMutationContext.testing(ownerID: ownerID)
        do {
            try await RecipePublicationAuthorizationPolicy.authorize(
                ownerID: ownerID,
                context: context,
                validator: { _ in false }
            )
            XCTFail("Expected invalidated account context to reject publication")
        } catch UserSessionError.accountChanged {
            // Expected.
        }
    }

    func testRecipeMutationBoundaryRejectsInvalidatedAccountContext() async {
        let ownerID = UUID()
        let service = RecipeCloudService(
            core: CloudKitCore(),
            publicationAuthorizer: { _ in false }
        )

        await assertAccountChanged {
            try await service.validateMutationAuthorization(
                ownerID: ownerID,
                context: .testing(ownerID: ownerID)
            )
        }
    }

    func testCollectionMutationBoundaryRejectsInvalidatedAccountContext() async {
        let ownerID = UUID()
        let service = CollectionCloudService(
            core: CloudKitCore(),
            publicationAuthorizer: { _ in false }
        )

        await assertAccountChanged {
            try await service.validateMutationAuthorization(
                ownerID: ownerID,
                context: .testing(ownerID: ownerID)
            )
        }
    }

    func testSavedReferenceMutationBoundaryRejectsInvalidatedAccountContext() async {
        let ownerID = UUID()
        let service = SavedReferenceCloudService(
            core: CloudKitCore(),
            publicationAuthorizer: { _ in false }
        )

        await assertAccountChanged {
            try await service.validateMutationAuthorization(
                ownerID: ownerID,
                context: .testing(ownerID: ownerID)
            )
        }
    }

    func testFirstSyncMigratesLegacyTombstoneBeforeCloudInventoryAndPreventsResurrection() async throws {
        let ownerID = UUID()
        let recipeID = UUID()
        let container = try TestModelContainer.create()
        let dependencies = makeDependencies(container: container)
        let defaultsName = "RecipeSyncAccountSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let context = ModelContext(container)
        context.insert(try RecipeModel.from(Recipe(
            id: recipeID,
            title: "Legacy deleted recipe",
            ingredients: [],
            steps: [],
            ownerId: nil
        )))
        context.insert(DeletedRecipeModel(recipeId: recipeID, deletedAt: Date(), cloudRecordName: nil))
        try context.save()

        let recorder = SyncRecorder()
        let cloudRecipe = Recipe(
            id: recipeID,
            title: "Stale cloud copy",
            ingredients: [],
            steps: [],
            ownerId: ownerID
        )
        let accountContext = VerifiedAccountMutationContext.testing(ownerID: ownerID)
        let service = RecipeSyncService(
            cloudKitCore: dependencies.core,
            recipeCloudService: dependencies.cloud,
            recipeRepository: dependencies.repository,
            deletedRecipeRepository: dependencies.deleted,
            imageManager: dependencies.images,
            accountContextProvider: { _ in accountContext },
            accountContextValidator: { _ in true },
            migrateLegacyOwnership: { id in
                guard let isolatedDefaults = UserDefaults(suiteName: defaultsName) else {
                    throw CocoaError(.fileReadUnknown)
                }
                try await dependencies.repository.migrateRecipeOwnership(currentUserId: id, defaults: isolatedDefaults)
                await recorder.record("migration")
            },
            cloudAvailability: { true },
            fetchCloudRecipes: { _ in
                await recorder.record("inventory")
                return [cloudRecipe]
            },
            fetchRemoteDeletedRecipes: { _ in [] },
            savePrivateRecipe: { _, _, _ in await recorder.record("private-save") },
            saveRemoteTombstone: { _ in await recorder.record("tombstone-save") },
            deletePrivateRecipe: { _ in },
            deletePublicRecipe: { _, _ in },
            fetchPublishedRecipes: { _ in [] }
        )

        try await service.performFullSync(for: ownerID)

        let events = await recorder.snapshot()
        XCTAssertLessThan(try XCTUnwrap(events.firstIndex(of: "migration")), try XCTUnwrap(events.firstIndex(of: "inventory")))
        XCTAssertTrue(events.contains("tombstone-save"))
        XCTAssertFalse(events.contains("private-save"))
        let remainingRecipe = try await dependencies.repository.fetch(id: recipeID, preferredOwnerId: ownerID)
        let remainsDeleted = try await dependencies.deleted.isDeleted(recipeId: recipeID, ownerId: ownerID)
        XCTAssertNil(remainingRecipe)
        XCTAssertTrue(remainsDeleted)
    }

    func testAccountSwitchDuringCloudInventoryStopsBeforeLocalOnlyRecipePublication() async throws {
        let ownerID = UUID()
        let container = try TestModelContainer.create()
        let dependencies = makeDependencies(container: container)
        let localRecipe = Recipe(title: "A only", ingredients: [], steps: [], ownerId: ownerID)
        let context = ModelContext(container)
        context.insert(try RecipeModel.from(localRecipe))
        try context.save()

        let gate = SyncAccountGate(context: .testing(ownerID: ownerID))
        let recorder = SyncRecorder()
        let service = RecipeSyncService(
            cloudKitCore: dependencies.core,
            recipeCloudService: dependencies.cloud,
            recipeRepository: dependencies.repository,
            deletedRecipeRepository: dependencies.deleted,
            imageManager: dependencies.images,
            accountContextProvider: { id in await gate.context(for: id) },
            accountContextValidator: { context in await gate.permits(context) },
            migrateLegacyOwnership: { _ in },
            cloudAvailability: { true },
            fetchCloudRecipes: { _ in
                await gate.invalidate()
                return []
            },
            fetchRemoteDeletedRecipes: { _ in [] },
            savePrivateRecipe: { _, _, _ in await recorder.record("private-save") },
            saveRemoteTombstone: { _ in },
            deletePrivateRecipe: { _ in },
            deletePublicRecipe: { _, _ in },
            fetchPublishedRecipes: { _ in [] }
        )

        do {
            try await service.performFullSync(for: ownerID)
            XCTFail("Expected account switch to abort sync")
        } catch UserSessionError.accountChanged {
            // Expected.
        }
        let events = await recorder.snapshot()
        XCTAssertFalse(events.contains("private-save"))
    }

    private func makeDependencies(container: ModelContainer) -> (
        core: CloudKitCore,
        cloud: RecipeCloudService,
        repository: RecipeRepository,
        deleted: DeletedRecipeRepository,
        images: RecipeImageManager
    ) {
        let core = CloudKitCore()
        let cloud = RecipeCloudService(core: core)
        let deleted = DeletedRecipeRepository(modelContainer: container)
        let images = RecipeImageManager(
            directoryName: "RecipeSyncAccountSafetyTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            uploadToCloudWithDatabase: nil,
            downloadFromCloudWithDatabase: nil
        )
        let repository = RecipeRepository(
            modelContainer: container,
            cloudKitCore: core,
            recipeCloudService: cloud,
            deletedRecipeRepository: deleted,
            imageManager: images,
            imageSyncManager: ImageSyncManager(),
            operationQueueService: OperationQueueService(),
            externalShareService: ExternalShareService(imageManager: images)
        )
        return (core, cloud, repository, deleted, images)
    }

    private func assertAccountChanged(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected invalidated account context", file: file, line: line)
        } catch UserSessionError.accountChanged {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

private actor SyncRecorder {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func snapshot() -> [String] { events }
}

private actor SyncAccountGate {
    let accountContext: VerifiedAccountMutationContext
    private var valid = true

    init(context: VerifiedAccountMutationContext) { self.accountContext = context }
    func context(for ownerID: UUID) -> VerifiedAccountMutationContext? {
        valid && accountContext.ownerID == ownerID ? accountContext : nil
    }
    func permits(_ context: VerifiedAccountMutationContext) -> Bool {
        valid && context == accountContext
    }
    func invalidate() { valid = false }
}
