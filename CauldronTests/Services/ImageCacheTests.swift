//
//  ImageCacheTests.swift
//  CauldronTests
//

import XCTest
import UIKit
import CryptoKit
@testable import Cauldron

@MainActor
final class ImageCacheTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        ImageCache.shared.clear()
        await ImageCache.shared.waitForPendingDiskOperations()
    }

    override func tearDown() async throws {
        ImageCache.shared.clear()
        await ImageCache.shared.waitForPendingDiskOperations()
        try await super.tearDown()
    }

    func testGetFromDiskReturnsSavedImage() async throws {
        let key = "test-image-cache-key"
        let image = makeImage(color: .systemOrange)

        try writeDiskImage(image, for: key)

        let diskImage = await ImageCache.shared.getFromDisk(key)

        XCTAssertNotNil(diskImage)
        XCTAssertEqual(diskImage?.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(diskImage?.cgImage?.height, image.cgImage?.height)
    }

    func testEnsureProfileImagesInCachePromotesDiskOnlyProfileImageToMemory() async throws {
        let user = User(
            id: UUID(),
            username: "disk-user",
            displayName: "Disk User",
            cloudProfileImageRecordName: "cloud-profile-record"
        )
        guard case .photo(let photo) = user.avatarRepresentation else {
            return XCTFail("Expected a photo avatar")
        }
        let cacheKey = ImageCache.profileImageKey(for: photo)
        let image = makeImage(color: .systemBlue)

        try writeDiskImage(image, for: cacheKey)

        XCTAssertNil(ImageCache.shared.get(cacheKey))

        await EntityImageLoader.shared.ensureProfileImagesInCache(users: [user])

        let cachedImage = ImageCache.shared.get(cacheKey)
        XCTAssertNotNil(cachedImage)
        XCTAssertEqual(cachedImage?.cgImage?.width, image.cgImage?.width)
        XCTAssertEqual(cachedImage?.cgImage?.height, image.cgImage?.height)
    }

    func testEmojiAvatarNeverReadsLegacyPhotoCache() async {
        let user = User(
            id: UUID(),
            username: "emoji-user",
            displayName: "Emoji User",
            profileEmoji: "🍲",
            profileColor: "#FF9900"
        )
        let legacyKey = ImageCache.profileImageKey(userId: user.id)
        ImageCache.shared.set(legacyKey, image: makeImage(color: .systemRed))

        let result = await EntityImageLoader.shared.loadProfileImage(for: user, dependencies: nil)

        XCTAssertNil(result.image)
    }

    func testPhotoCacheKeyChangesWithCloudRevision() {
        let ownerID = UUID()
        let first = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            cloudProfileImageRecordName: "profile-image",
            profileImageModifiedAt: Date(timeIntervalSince1970: 10)
        )
        let second = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            cloudProfileImageRecordName: "profile-image",
            profileImageModifiedAt: Date(timeIntervalSince1970: 20)
        )
        guard case .photo(let firstPhoto) = first.avatarRepresentation,
              case .photo(let secondPhoto) = second.avatarRepresentation else {
            return XCTFail("Expected photo avatars")
        }

        XCTAssertNotEqual(
            ImageCache.profileImageKey(for: firstPhoto),
            ImageCache.profileImageKey(for: secondPhoto)
        )
    }

    func testCloudPhotoCacheKeySurvivesLocalHydration() {
        let ownerID = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 20)
        let cloudOnly = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            cloudProfileImageRecordName: "profile-image",
            profileImageModifiedAt: modifiedAt
        )
        let hydrated = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            profileImageURL: URL(fileURLWithPath: "/tmp/profile-image.jpg"),
            cloudProfileImageRecordName: "profile-image",
            profileImageModifiedAt: modifiedAt,
            profileImageLocalRevision: UUID()
        )
        guard case .photo(let cloudPhoto) = cloudOnly.avatarRepresentation,
              case .photo(let hydratedPhoto) = hydrated.avatarRepresentation else {
            return XCTFail("Expected photo avatars")
        }

        XCTAssertEqual(
            ImageCache.profileImageKey(for: cloudPhoto),
            ImageCache.profileImageKey(for: hydratedPhoto)
        )
    }

    func testPendingLocalReplacementDoesNotReusePreviousCloudPhotoKey() {
        let ownerID = UUID()
        let previous = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            cloudProfileImageRecordName: "profile-image",
            profileImageModifiedAt: Date(timeIntervalSince1970: 20)
        )
        let pendingReplacement = User(
            id: ownerID,
            username: "photo-user",
            displayName: "Photo User",
            profileImageURL: URL(fileURLWithPath: "/tmp/new-profile-image.jpg"),
            cloudProfileImageRecordName: nil,
            profileImageModifiedAt: nil,
            profileImageLocalRevision: UUID()
        )
        guard case .photo(let previousPhoto) = previous.avatarRepresentation,
              case .photo(let replacementPhoto) = pendingReplacement.avatarRepresentation else {
            return XCTFail("Expected photo avatars")
        }

        XCTAssertNotEqual(
            ImageCache.profileImageKey(for: previousPhoto),
            ImageCache.profileImageKey(for: replacementPhoto)
        )
    }

    func testSavingProfileImageInvalidatesIdBasedCacheEntry() async throws {
        let userId = UUID()
        let cacheKey = ImageCache.profileImageKey(userId: userId)
        ImageCache.shared.set(cacheKey, image: makeImage(color: .systemRed))
        let manager = ProfileImageManagerV2(
            directoryName: "TestProfileImages-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            cacheKeyGenerator: { ImageCache.profileImageKey(userId: $0) }
        )

        _ = try await manager.saveImage(makeImage(color: .systemGreen), userId: userId)

        XCTAssertNil(ImageCache.shared.get(cacheKey))
    }

    func testSavingCollectionImageInvalidatesIdBasedCacheEntry() async throws {
        let collectionId = UUID()
        let cacheKey = ImageCache.collectionImageKey(collectionId: collectionId)
        ImageCache.shared.set(cacheKey, image: makeImage(color: .systemRed))
        let manager = CollectionImageManagerV2(
            directoryName: "TestCollectionImages-\(UUID().uuidString)",
            baseDirectoryURL: FileManager.default.temporaryDirectory,
            removesDirectoryOnDeinit: true,
            cacheKeyGenerator: { ImageCache.collectionImageKey(collectionId: $0) }
        )

        _ = try await manager.saveImage(makeImage(color: .systemGreen), collectionId: collectionId)

        XCTAssertNil(ImageCache.shared.get(cacheKey))
    }

    private func makeImage(color: UIColor) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }

    private func writeDiskImage(_ image: UIImage, for key: String) throws {
        let fileURL = diskCacheURL(for: key)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Failed to create JPEG data for test image")
            return
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func diskCacheURL(for key: String) -> URL {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return cachesDir
            .appendingPathComponent("ProfileImageCache", isDirectory: true)
            .appendingPathComponent(md5Hash(key))
            .appendingPathExtension("jpg")
    }

    private func md5Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.MD5.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
