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

    func testPrivateRecordNameLookupIsNotBlockedByUuidPrivateMissCache() async throws {
        let recipeId = UUID()
        let legacyRecordName = "legacy-\(recipeId.uuidString)"
        let imageData = try makeImageData()
        let calls = DownloadCallRecorder()

        let manager = RecipeImageManager(
            directoryName: "RecipeImages",
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

    private func makeImageData() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }

        return try XCTUnwrap(image.pngData())
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
