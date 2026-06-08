//
//  ImageSyncManagerScopingTests.swift
//  CauldronTests
//
//  Regression tests for per-database scoping of pending image uploads.
//  Previously the pending-upload set was keyed only by recipe id, so a
//  successful private-database upload could clear a still-needed public-database
//  upload retry (and vice-versa). Uploads are now tracked per ImageUploadScope.
//

import XCTest
@testable import Cauldron

final class ImageSyncManagerScopingTests: XCTestCase {

    /// A private-DB success must NOT clear a still-pending public-DB upload.
    func testRemovingPrivateUploadKeepsPublicPending() async {
        let manager = ImageSyncManager()
        await manager.clearAll()
        let recipeId = UUID()

        await manager.addPendingUpload(recipeId, scope: .privateDB)
        await manager.addPendingUpload(recipeId, scope: .publicDB)

        // Private upload succeeds → clear only the private scope.
        await manager.removePendingUpload(recipeId, scope: .privateDB)

        let privatePending = await manager.pendingPrivateUploads
        let publicPending = await manager.pendingPublicUploads
        XCTAssertFalse(privatePending.contains(recipeId), "Private pending should be cleared")
        XCTAssertTrue(publicPending.contains(recipeId), "Public pending must survive a private success")

        // The recipe is still considered to have a pending operation overall.
        let hasPending = await manager.hasPendingOperation(for: recipeId)
        XCTAssertTrue(hasPending)
        let union = await manager.pendingUploads
        XCTAssertTrue(union.contains(recipeId))
    }

    /// Symmetric: a public-DB success must NOT clear a still-pending private-DB upload.
    func testRemovingPublicUploadKeepsPrivatePending() async {
        let manager = ImageSyncManager()
        await manager.clearAll()
        let recipeId = UUID()

        await manager.addPendingUpload(recipeId, scope: .privateDB)
        await manager.addPendingUpload(recipeId, scope: .publicDB)

        await manager.removePendingUpload(recipeId, scope: .publicDB)

        let privatePending = await manager.pendingPrivateUploads
        let publicPending = await manager.pendingPublicUploads
        XCTAssertTrue(privatePending.contains(recipeId), "Private pending must survive a public success")
        XCTAssertFalse(publicPending.contains(recipeId), "Public pending should be cleared")
    }

    /// removeAllPendingUploads clears both scopes (delete / no-local-image paths).
    func testRemoveAllClearsBothScopes() async {
        let manager = ImageSyncManager()
        await manager.clearAll()
        let recipeId = UUID()

        await manager.addPendingUpload(recipeId, scope: .privateDB)
        await manager.addPendingUpload(recipeId, scope: .publicDB)

        await manager.removeAllPendingUploads(recipeId)

        let privatePending = await manager.pendingPrivateUploads
        let publicPending = await manager.pendingPublicUploads
        XCTAssertFalse(privatePending.contains(recipeId))
        XCTAssertFalse(publicPending.contains(recipeId))
        let hasPending = await manager.hasPendingOperation(for: recipeId)
        XCTAssertFalse(hasPending)
    }

    /// The combined `pendingUploads` view reflects either scope.
    func testPendingUploadsUnionReflectsBothScopes() async {
        let manager = ImageSyncManager()
        await manager.clearAll()
        let privateOnly = UUID()
        let publicOnly = UUID()

        await manager.addPendingUpload(privateOnly, scope: .privateDB)
        await manager.addPendingUpload(publicOnly, scope: .publicDB)

        let union = await manager.pendingUploads
        XCTAssertTrue(union.contains(privateOnly))
        XCTAssertTrue(union.contains(publicOnly))
    }

    /// Independent recipes in different scopes don't interfere on removal.
    func testIndependentRecipesAcrossScopes() async {
        let manager = ImageSyncManager()
        await manager.clearAll()
        let recipeA = UUID()
        let recipeB = UUID()

        await manager.addPendingUpload(recipeA, scope: .privateDB)
        await manager.addPendingUpload(recipeB, scope: .publicDB)

        await manager.removePendingUpload(recipeA, scope: .privateDB)

        let privatePending = await manager.pendingPrivateUploads
        let publicPending = await manager.pendingPublicUploads
        XCTAssertFalse(privatePending.contains(recipeA))
        XCTAssertTrue(publicPending.contains(recipeB), "Unrelated public pending must be untouched")
    }
}
