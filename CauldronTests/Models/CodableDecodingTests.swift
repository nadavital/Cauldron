//
//  CodableDecodingTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class CodableDecodingTests: XCTestCase {
    func testRecipeDecode_ThrowsWhenRequiredTitleIsMissing() {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "ingredients": [],
            "steps": [],
            "yields": "4 servings",
            "tags": [],
            "isFavorite": false,
            "visibility": RecipeVisibility.publicRecipe.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000)),
            "updatedAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_100))
        ]

        XCTAssertThrowsError(try decode(Recipe.self, from: json))
    }

    func testRecipeDecode_LegacyPayloadDefaultsNewSourceTrackingFields() throws {
        let recipeID = UUID()
        let ownerID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)

        let json: [String: Any] = [
            "id": recipeID.uuidString,
            "title": "Legacy Soup",
            "ingredients": [[
                "id": UUID().uuidString,
                "name": "Salt"
            ]],
            "steps": [[
                "id": UUID().uuidString,
                "index": 0,
                "text": "Stir",
                "timers": []
            ]],
            "yields": "4 servings",
            "tags": [],
            "isFavorite": false,
            "visibility": RecipeVisibility.publicRecipe.rawValue,
            "ownerId": ownerID.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: updatedAt),
            "originalRecipeId": UUID().uuidString,
            "savedAt": ISO8601DateFormatter().string(from: updatedAt)
        ]

        let decoded = try decode(Recipe.self, from: json)

        XCTAssertEqual(decoded.id, recipeID)
        XCTAssertEqual(decoded.relatedRecipeIds, [])
        XCTAssertFalse(decoded.isPreview)
        XCTAssertTrue(decoded.isFollowingSourceUpdates)
    }

    func testUserDecode_ThrowsWhenRequiredIdentityFieldsAreMissing() {
        let json: [String: Any] = [
            "id": UUID().uuidString,
            "displayName": "Alice Example",
            "createdAt": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_700_000_000))
        ]

        XCTAssertThrowsError(try decode(User.self, from: json))
    }

    func testQuantityDecode_ThrowsWhenRequiredValueIsMissing() {
        let json: [String: Any] = [
            "unit": UnitKind.cup.rawValue
        ]

        XCTAssertThrowsError(try decode(Quantity.self, from: json))
    }

    func testIngredientDecode_ThrowsWhenRequiredNameIsMissing() {
        let json: [String: Any] = [
            "id": UUID().uuidString
        ]

        XCTAssertThrowsError(try decode(Ingredient.self, from: json))
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: [String: Any]) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
