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
            imageURL: "https://example.com/image.jpg",
            tagNames: ["Dinner", "Pasta"]
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
        XCTAssertEqual(decoded.tagNames, payload.tagNames)

        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(raw["title"] as? String, "Lemon Pasta")
        XCTAssertEqual(raw["ingredients"] as? [String], ["8 oz pasta", "2 tbsp olive oil"])
        XCTAssertEqual(raw["steps"] as? [String], ["Boil pasta", "Toss with oil"])
        XCTAssertEqual(raw["yields"] as? String, "2 servings")
        XCTAssertEqual(raw["totalMinutes"] as? Int, 15)
        XCTAssertEqual(raw["sourceURL"] as? String, "https://example.com/lemon-pasta")
        XCTAssertEqual(raw["sourceTitle"] as? String, "Example")
        XCTAssertEqual(raw["imageURL"] as? String, "https://example.com/image.jpg")
        XCTAssertEqual(raw["tagNames"] as? [String], ["Dinner", "Pasta"])
    }

    func testPreparedShareRecipePayload_DecodesLegacyPayloadWithoutTags() throws {
        let legacyJSON = """
        {
          "title": "Legacy Soup",
          "ingredients": ["1 cup stock"],
          "steps": ["Warm stock"]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PreparedShareRecipePayload.self, from: legacyJSON)

        XCTAssertEqual(decoded.title, "Legacy Soup")
        XCTAssertEqual(decoded.tagNames, [])
    }

    func testImportContract_UsesExpectedAppGroupAndStorageKeys() {
        XCTAssertEqual(ShareExtensionImportContract.appGroupID, "group.Nadav.Cauldron")
        XCTAssertEqual(ShareExtensionImportContract.pendingRecipeURLKey, "shareExtension.pendingRecipeURL")
        XCTAssertEqual(ShareExtensionImportContract.pendingRecipeTextKey, "shareExtension.pendingRecipeText")
        XCTAssertEqual(ShareExtensionImportContract.preparedRecipePayloadKey, "shareExtension.preparedRecipePayload")
    }

    func testPendingRecipeTextConsumption_LeavesPendingURLForCallerToSupersedeExplicitly() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("https://example.com/old-recipe", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("1 cup flour\nBake until done", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        XCTAssertEqual(
            ShareExtensionImportStore.consumePendingRecipeText(in: defaults),
            "1 cup flour\nBake until done"
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
        XCTAssertEqual(
            defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey),
            "https://example.com/old-recipe"
        )
    }

    func testPreparedRecipeConsumption_SupersedesPendingURLAndText() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Prepared Soup",
            ingredients: ["1 cup stock"],
            steps: ["Warm stock"],
            sourceURL: "https://example.com/prepared-soup"
        )
        defaults.set(try JSONEncoder().encode(payload), forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
        defaults.set("https://example.com/old-recipe", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("old text", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        let prepared = try XCTUnwrap(ShareExtensionImportStore.consumePreparedRecipe(in: defaults))

        XCTAssertEqual(prepared.recipe.title, "Prepared Soup")
        XCTAssertNil(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
    }

    func testPendingPreparedRecipeRead_DoesNotConsumePayloadBeforeAcknowledgement() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Durable Soup",
            ingredients: ["1 cup stock"],
            steps: ["Warm stock"]
        )
        let data = try JSONEncoder().encode(payload)
        defaults.set(data, forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
        defaults.set("https://example.com/durable-soup", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("old text", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        let pending = try XCTUnwrap(ShareExtensionImportStore.pendingPreparedRecipe(in: defaults))

        XCTAssertEqual(pending.preparedRecipe.recipe.title, "Durable Soup")
        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey), data)

        ShareExtensionImportStore.acknowledgePreparedRecipe(matching: Data("new payload".utf8), in: defaults)
        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey), data)

        ShareExtensionImportStore.acknowledgePreparedRecipe(matching: pending.payloadData, in: defaults)
        XCTAssertNil(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
    }

    func testPendingURLAndTextAcknowledgement_OnlyClearsMatchingPayload() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("https://example.com/recipe", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("1 cup flour", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        ShareExtensionImportStore.acknowledgePendingRecipeURL(matching: URL(string: "https://example.com/other"), in: defaults)
        ShareExtensionImportStore.acknowledgePendingRecipeText(matching: "other text", in: defaults)

        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey), "https://example.com/recipe")
        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey), "1 cup flour")

        ShareExtensionImportStore.acknowledgePendingRecipeURL(matching: URL(string: "https://example.com/recipe"), in: defaults)
        ShareExtensionImportStore.acknowledgePendingRecipeText(matching: "1 cup flour", in: defaults)

        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
    }

    func testPlainRecipeTextWithSourceURLTakesPrecedenceOverURLImport() {
        let text = """
        Ingredients
        1 cup flour
        2 tbsp olive oil

        Instructions
        Mix everything and bake until golden.

        Source: https://example.com/flatbread
        """

        XCTAssertTrue(ShareExtensionImportStore.plainTextRecipeShouldTakePrecedenceOverURL(text))
        XCTAssertEqual(
            ShareExtensionImportStore.firstHTTPURL(in: text),
            URL(string: "https://example.com/flatbread")
        )
    }

    func testBareSharedURLDoesNotTakeTextPrecedence() {
        let text = "https://example.com/recipe"

        XCTAssertFalse(ShareExtensionImportStore.plainTextRecipeShouldTakePrecedenceOverURL(text))
        XCTAssertEqual(
            ShareExtensionImportStore.firstHTTPURL(in: text),
            URL(string: "https://example.com/recipe")
        )
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "CauldronTests.ShareExtensionImportContract.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
