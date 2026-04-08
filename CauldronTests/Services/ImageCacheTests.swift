//
//  ImageCacheTests.swift
//  CauldronTests
//

import XCTest
import CryptoKit
import UIKit
@testable import Cauldron

final class ImageCacheTests: XCTestCase {
    @MainActor
    func testGet_LoadsImageFromDiskCacheWhenMemoryCacheMisses() throws {
        let key = "image-cache-test-\(UUID().uuidString)"
        let fileURL = cacheFileURL(for: key)
        let image = makeImage()

        try? FileManager.default.removeItem(at: fileURL)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            XCTFail("Expected test image JPEG data")
            return
        }
        try data.write(to: fileURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: fileURL)
            ImageCache.shared.remove(key)
        }

        let cachedImage = ImageCache.shared.get(key)

        XCTAssertNotNil(cachedImage)
    }

    private func cacheFileURL(for key: String) -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let cacheDirectory = cachesDirectory.appendingPathComponent("ProfileImageCache", isDirectory: true)
        let digest = Insecure.MD5.hash(data: Data(key.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(filename).appendingPathExtension("jpg")
    }

    private func makeImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}
