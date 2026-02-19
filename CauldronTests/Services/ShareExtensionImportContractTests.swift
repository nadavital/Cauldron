import XCTest
@testable import Cauldron

final class ShareExtensionImportContractTests: XCTestCase {
    func testPreparedShareRecipePayload_RoundTripsCanonicalJSONShape() throws {
        let payload = PreparedShareRecipePayload(
            title: "Lemon Pasta",
            ingredients: ["8 oz pasta", "2 tbsp olive oil"],
            steps: ["Boil pasta", "Toss with oil"],
            yields: "2 servings",
            totalMinutes: 15,
            sourceURL: "https://example.com/lemon-pasta",
            sourceTitle: "Example",
            imageURL: "https://example.com/image.jpg"
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PreparedShareRecipePayload.self, from: data)

        XCTAssertEqual(decoded.title, payload.title)
        XCTAssertEqual(decoded.ingredients, payload.ingredients)
        XCTAssertEqual(decoded.steps, payload.steps)
        XCTAssertEqual(decoded.yields, payload.yields)
        XCTAssertEqual(decoded.totalMinutes, payload.totalMinutes)
        XCTAssertEqual(decoded.sourceURL, payload.sourceURL)
        XCTAssertEqual(decoded.sourceTitle, payload.sourceTitle)
        XCTAssertEqual(decoded.imageURL, payload.imageURL)

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(raw["title"] as? String, "Lemon Pasta")
        XCTAssertEqual(raw["ingredients"] as? [String], ["8 oz pasta", "2 tbsp olive oil"])
        XCTAssertEqual(raw["steps"] as? [String], ["Boil pasta", "Toss with oil"])
        XCTAssertEqual(raw["yields"] as? String, "2 servings")
        XCTAssertEqual(raw["totalMinutes"] as? Int, 15)
        XCTAssertEqual(raw["sourceURL"] as? String, "https://example.com/lemon-pasta")
        XCTAssertEqual(raw["sourceTitle"] as? String, "Example")
        XCTAssertEqual(raw["imageURL"] as? String, "https://example.com/image.jpg")
    }

    func testImportContract_UsesExpectedAppGroupAndStorageKeys() {
        XCTAssertEqual(ShareExtensionImportContract.appGroupID, "group.Nadav.Cauldron")
        XCTAssertEqual(ShareExtensionImportContract.pendingRecipeURLKey, "shareExtension.pendingRecipeURL")
        XCTAssertEqual(ShareExtensionImportContract.preparedRecipePayloadKey, "shareExtension.preparedRecipePayload")
    }
}
