//
//  EntityImageManagerDatabaseCacheTests.swift
//  CauldronTests
//
//  Regression coverage for database-aware recipe-image fallback cache keys.
//

import XCTest
import UIKit
@testable import Cauldron

final class EntityImageManagerDatabaseCacheTests: XCTestCase {

    func testInjectedFixtureDirectoryIsRemovedWhenManagerIsReleased() {
        let directoryName = "ProfileImageCleanupTests-\(UUID().uuidString)"
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        var manager: ProfileImageManagerV2? = ProfileImageManagerV2(
            directoryName: directoryName,
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true
        )

        XCTAssertNotNil(manager)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directoryURL.path))

        manager = nil

        XCTAssertFalse(FileManager.default.fileExists(atPath: directoryURL.path))
    }

    func testPrivateRecordNameLookupIsNotBlockedByUuidPrivateMissCache() async throws {
        let recipeId = UUID()
        let legacyRecordName = "legacy-\(recipeId.uuidString)"
        let imageData = try makeImageData()
        let calls = DownloadCallRecorder()

        let manager = RecipeImageManager(
            directoryName: "RecipeImageDatabaseCacheTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            downloadFromCloudWithDatabase: { id, fromPublic, privateRecordName in
                await calls.record(id: id, fromPublic: fromPublic, privateRecordName: privateRecordName)
                guard id == recipeId,
                      !fromPublic,
                      privateRecordName == legacyRecordName else {
                    return nil
                }
                return imageData
            }
        )

        let uuidPrivateMiss = try await manager.downloadImageFromCloud(
            recipeId: recipeId,
            fromPublic: false
        )
        XCTAssertNil(uuidPrivateMiss)

        let legacyPrivateHit = try await manager.downloadImageFromCloud(
            recipeId: recipeId,
            fromPublic: false,
            privateRecordName: legacyRecordName
        )

        XCTAssertNotNil(legacyPrivateHit)
        let observedPrivateRecordNames = await calls.privateRecordNames
        XCTAssertEqual(observedPrivateRecordNames, [nil, legacyRecordName])
    }

    func testCloudDownloadDoesNotOverwriteLocalImageSavedWhileSuspended() async throws {
        let userID = UUID()
        let downloadStarted = ImageDownloadGate()
        let allowDownload = ImageDownloadGate()
        let cloudData = try makeImageData(color: .systemOrange)
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageRaceTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            downloadFromCloud: { _ in
                await downloadStarted.open()
                await allowDownload.wait()
                return cloudData
            }
        )

        async let cloudURL = manager.downloadImageFromCloud(userId: userID)
        await downloadStarted.wait()
        let localImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let localURL = try await manager.saveImage(localImage, userId: userID)
        let localData = try Data(contentsOf: localURL)
        await allowDownload.open()

        do {
            _ = try await cloudURL
            XCTFail("A stale CloudKit download must fail its conditional save")
        } catch {
            XCTAssertEqual(try Data(contentsOf: localURL), localData)
        }
    }

    func testStaleSavedImageTokenCannotDeleteNewerReplacement() async throws {
        let userID = UUID()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageRollbackTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000
        )
        let firstImage = makeImage(color: .systemOrange)
        let replacementImage = makeImage(color: .systemBlue)

        let staleSave = try await manager.saveImageWithToken(firstImage, userId: userID)
        let replacementURL = try await manager.saveImage(replacementImage, userId: userID)
        let replacementData = try Data(contentsOf: replacementURL)

        await manager.deleteImageIfUnchanged(
            userId: userID,
            savedFile: staleSave.file
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: replacementURL.path))
        XCTAssertEqual(try Data(contentsOf: replacementURL), replacementData)
    }

    func testTransactionalReplacementRollbackRestoresPriorBytesAndGeneration() async throws {
        let userID = UUID()
        let uploadedData = UploadedImageRecorder()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageTransactionTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            uploadToCloud: { _, data in
                await uploadedData.record(data)
                return "profile-record"
            }
        )
        let original = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )
        let originalData = try Data(contentsOf: original.url)
        let preparedReplacement = try await manager.prepareImageData(
            makeImage(color: .systemBlue)
        )
        let replacement = try await manager.commitPreparedImageData(
            preparedReplacement,
            userId: userID,
            knownPreviousGeneration: original.file.generation
        )

        await manager.rollbackImageReplacementIfUnchanged(
            replacement,
            userId: userID
        )
        let uploadOutcome = try await manager.uploadImageToCloud(
            userId: userID,
            expectedGeneration: original.file.generation,
            authorization: { true }
        )
        let recordedData = await uploadedData.data

        guard case .uploaded(let recordName) = uploadOutcome else {
            return XCTFail("Expected the restored generation to upload")
        }
        XCTAssertEqual(recordName, "profile-record")
        XCTAssertEqual(try Data(contentsOf: original.url), originalData)
        XCTAssertEqual(recordedData, originalData)
    }

    func testPreparedReplacementCannotStackOnUncommittedGeneration() async throws {
        let userID = UUID()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageCASTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000
        )
        let original = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )
        let preparedA = try await manager.prepareImageData(makeImage(color: .systemBlue))
        let preparedB = try await manager.prepareImageData(makeImage(color: .systemGreen))
        let replacementA = try await manager.commitPreparedImageData(
            preparedA,
            userId: userID,
            knownPreviousGeneration: original.file.generation
        )

        do {
            _ = try await manager.commitPreparedImageData(
                preparedB,
                userId: userID,
                knownPreviousGeneration: original.file.generation
            )
            XCTFail("A second replacement must not stack on an uncommitted generation")
        } catch {
            // Expected CAS rejection.
        }

        await manager.rollbackImageReplacementIfUnchanged(replacementA, userId: userID)
        _ = try await manager.commitPreparedImageData(
            preparedB,
            userId: userID,
            knownPreviousGeneration: original.file.generation
        )
    }

    @MainActor
    func testStagedReplacementCanBeReplayedAfterRollback() async throws {
        let userID = UUID()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageStagingTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000
        )
        let original = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )
        let originalData = try Data(contentsOf: original.url)
        let prepared = try await manager.prepareImageData(makeImage(color: .systemBlue))
        let staged = try await manager.stagePreparedImageData(prepared, userId: userID)
        let stagedURL = staged.url
        let stagedGeneration = staged.generation

        XCTAssertEqual(try Data(contentsOf: original.url), originalData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagedURL.path))

        let firstPromotion = try await manager.promoteStagedImage(
            staged,
            userId: userID,
            knownPreviousGeneration: original.file.generation
        )
        let firstPromotionGeneration = firstPromotion.file.generation
        let firstPromotionData = try Data(contentsOf: firstPromotion.url)
        XCTAssertEqual(firstPromotionGeneration, stagedGeneration)
        XCTAssertEqual(firstPromotionData, prepared)

        await manager.rollbackImageReplacementIfUnchanged(firstPromotion, userId: userID)
        XCTAssertEqual(try Data(contentsOf: original.url), originalData)

        let replayedPromotion = try await manager.promoteStagedImage(
            staged,
            userId: userID,
            knownPreviousGeneration: original.file.generation
        )
        let replayedGeneration = replayedPromotion.file.generation
        let replayedData = try Data(contentsOf: replayedPromotion.url)
        XCTAssertEqual(replayedGeneration, stagedGeneration)
        XCTAssertEqual(replayedData, prepared)
        await manager.deleteStagedImage(staged, userId: userID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagedURL.path))
    }

    func testGenerationBoundUploadsSerializeAndNewestBytesWin() async throws {
        let userID = UUID()
        let uploadStarted = ImageDownloadGate()
        let allowFirstUpload = ImageDownloadGate()
        let uploads = UploadedImageSequenceRecorder()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageUploadOrderingTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            uploadToCloud: { _, data in
                let index = await uploads.recordAndReturnIndex(data)
                if index == 0 {
                    await uploadStarted.open()
                    await allowFirstUpload.wait()
                }
                return "profile-record-\(index)"
            }
        )
        let first = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )
        let firstData = try Data(contentsOf: first.url)

        async let firstOutcome = manager.uploadImageToCloud(
            userId: userID,
            expectedGeneration: first.file.generation,
            authorization: { true }
        )
        await uploadStarted.wait()

        let preparedSecond = try await manager.prepareImageData(makeImage(color: .systemBlue))
        let second = try await manager.commitPreparedImageData(
            preparedSecond,
            userId: userID,
            knownPreviousGeneration: first.file.generation
        )
        async let secondOutcome = manager.uploadImageToCloud(
            userId: userID,
            expectedGeneration: second.file.generation,
            authorization: { true }
        )

        await allowFirstUpload.open()
        let outcomes = try await (firstOutcome, secondOutcome)
        let recordedUploads = await uploads.data

        guard case .staleAfterUpload = outcomes.0 else {
            return XCTFail("The first upload must observe the newer local generation")
        }
        guard case .uploaded(let recordName) = outcomes.1 else {
            return XCTFail("The newest generation must upload after the stale request")
        }
        XCTAssertEqual(recordName, "profile-record-1")
        XCTAssertEqual(recordedUploads, [firstData, preparedSecond])
    }

    func testRemoteDeleteSerializesAheadOfInvalidatedUpload() async throws {
        let userID = UUID()
        let deleteStarted = ImageDownloadGate()
        let allowDelete = ImageDownloadGate()
        let cloudMutations = CloudMutationRecorder()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageDeleteOrderingTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            uploadToCloud: { _, _ in
                await cloudMutations.record("upload")
                return "profile-record"
            },
            deleteFromCloud: { _ in
                await cloudMutations.record("delete")
                await deleteStarted.open()
                await allowDelete.wait()
            }
        )
        let saved = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )
        await manager.deleteImage(userId: userID)

        async let deletion: Void = manager.deleteImageFromCloud(
            userId: userID,
            authorization: { true }
        )
        await deleteStarted.wait()
        async let uploadOutcome = manager.uploadImageToCloud(
            userId: userID,
            expectedGeneration: saved.file.generation,
            authorization: { true }
        )
        await allowDelete.open()

        try await deletion
        let outcome = try await uploadOutcome
        let mutations = await cloudMutations.events
        guard case .staleBeforeUpload = outcome else {
            return XCTFail("The locally invalidated generation must not upload after deletion")
        }
        XCTAssertEqual(mutations, ["delete"])
    }

    func testQueuedCloudMutationReauthorizesAfterLockWait() async throws {
        let userID = UUID()
        let firstUploadStarted = ImageDownloadGate()
        let allowFirstUpload = ImageDownloadGate()
        let authorization = CloudAuthorizationState(isAllowed: true)
        let uploads = UploadedImageSequenceRecorder()
        let manager = ProfileImageManagerV2(
            directoryName: "ProfileImageAuthorizationTests-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            maxDimension: 32,
            targetSizeBytes: 20_000,
            uploadToCloud: { _, data in
                let index = await uploads.recordAndReturnIndex(data)
                if index == 0 {
                    await firstUploadStarted.open()
                    await allowFirstUpload.wait()
                }
                return "profile-record-\(index)"
            }
        )
        let saved = try await manager.saveImageWithToken(
            makeImage(color: .systemOrange),
            userId: userID
        )

        async let firstOutcome = manager.uploadImageToCloud(
            userId: userID,
            expectedGeneration: saved.file.generation,
            authorization: { true }
        )
        await firstUploadStarted.wait()
        let queuedUpload = Task {
            try await manager.uploadImageToCloud(
                userId: userID,
                expectedGeneration: saved.file.generation,
                authorization: { await authorization.isAllowed }
            )
        }
        await authorization.setAllowed(false)
        await allowFirstUpload.open()

        guard case .uploaded = try await firstOutcome else {
            return XCTFail("The lock-holding upload should complete")
        }
        do {
            _ = try await queuedUpload.value
            XCTFail("The queued mutation must be rejected after authorization changes")
        } catch is CancellationError {
            // Expected account-boundary cancellation.
        }
        let uploadCount = await uploads.data.count
        XCTAssertEqual(uploadCount, 1)
    }

    private func makeImageData(color: UIColor = .systemOrange) throws -> Data {
        try XCTUnwrap(makeImage(color: color).pngData())
    }

    private func makeImage(color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

private actor UploadedImageRecorder {
    private(set) var data: Data?

    func record(_ data: Data) {
        self.data = data
    }
}

private actor UploadedImageSequenceRecorder {
    private(set) var data: [Data] = []

    func recordAndReturnIndex(_ value: Data) -> Int {
        data.append(value)
        return data.count - 1
    }
}

private actor CloudMutationRecorder {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

private actor CloudAuthorizationState {
    private(set) var isAllowed: Bool

    init(isAllowed: Bool) {
        self.isAllowed = isAllowed
    }

    func setAllowed(_ value: Bool) {
        isAllowed = value
    }
}

private actor ImageDownloadGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor DownloadCallRecorder {
    private var calls: [(id: UUID, fromPublic: Bool, privateRecordName: String?)] = []

    var privateRecordNames: [String?] {
        calls.map(\.privateRecordName)
    }

    func record(id: UUID, fromPublic: Bool, privateRecordName: String?) {
        calls.append((id: id, fromPublic: fromPublic, privateRecordName: privateRecordName))
    }
}
