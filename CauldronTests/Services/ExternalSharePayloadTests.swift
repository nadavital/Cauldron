import XCTest
@testable import Cauldron

@MainActor
final class ExternalSharePayloadTests: XCTestCase {
    func testPublicationResponseReportsWhetherSnapshotWasActuallyWritten() throws {
        let response = try JSONDecoder().decode(
            ShareResponse.self,
            from: Data(#"{"shareId":"recipe-id","shareUrl":"https://cauldron-f900a.web.app/recipe/recipe-id","published":true}"#.utf8)
        )

        XCTAssertEqual(response.published, true)
    }

    func testLegacyPublicationResponseStillDecodesForCompatibility() throws {
        let response = try JSONDecoder().decode(
            ShareResponse.self,
            from: Data(#"{"shareId":"recipe-id","shareUrl":"https://cauldron-f900a.web.app/recipe/recipe-id"}"#.utf8)
        )

        XCTAssertNil(response.published)
    }

    func testUnshareSuccessResponseMatchesBackendContract() throws {
        let response = try JSONDecoder().decode(
            UnshareResponse.self,
            from: Data(#"{"success":true}"#.utf8)
        )

        XCTAssertTrue(response.success)
    }

    func testCollectionShareResponseCarriesRecipeMembershipForDeepLinks() throws {
        let recipeID = UUID()
        let collectionID = UUID()
        let ownerID = UUID()
        let json = """
        {
          "success": true,
          "data": {
            "collectionId": "\(collectionID.uuidString)",
            "ownerId": "\(ownerID.uuidString)",
            "title": "Weeknight",
            "recipeIds": ["\(recipeID.uuidString)"]
          }
        }
        """

        let response = try JSONDecoder().decode(ShareData.self, from: Data(json.utf8))
        XCTAssertEqual(response.data.collectionId, collectionID.uuidString)
        XCTAssertEqual(response.data.recipeIds, [recipeID.uuidString])
    }

    func testProfileShareAndUnshareCarryTheSamePrivateCapability() throws {
        let userID = UUID(uuidString: "018F9344-54FF-42FC-83A8-C2A92E2D1B10")!
        let capability = String(repeating: "p", count: 43)
        let share = ShareMetadata.ProfileShare(
            userId: userID.uuidString,
            identityRecordName: "user_current-user-record",
            username: "nadav",
            displayName: "Nadav",
            profileEmoji: "🧑‍🍳",
            profileColor: "#FF9933",
            recipeCount: 12,
            capability: capability,
            shouldCreate: true
        )
        let unshare = ShareMetadata.ProfileUnshare(
            userId: userID.uuidString,
            identityRecordName: "user_current-user-record",
            username: "nadav",
            capability: capability
        )

        let shareObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(share)) as? [String: Any]
        )
        let unshareObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(unshare)) as? [String: Any]
        )
        XCTAssertEqual(shareObject["capability"] as? String, capability)
        XCTAssertEqual(shareObject["shouldCreate"] as? Bool, true)
        XCTAssertEqual(shareObject["recipeCount"] as? Int, 12)
        XCTAssertNil(shareObject["profileImageURL"])
        XCTAssertEqual(unshareObject["capability"] as? String, capability)
        XCTAssertEqual(unshareObject["userId"] as? String, userID.uuidString)
    }

    func testProfileMetadataRefreshCanPreserveExistingRecipeCount() throws {
        let share = ShareMetadata.ProfileShare(
            userId: UUID().uuidString,
            identityRecordName: "user_current-user-record",
            username: "nadav",
            displayName: "Nadav",
            profileEmoji: "🧑‍🍳",
            profileColor: "#FF9933",
            recipeCount: nil,
            capability: String(repeating: "p", count: 43),
            shouldCreate: false
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(share)) as? [String: Any]
        )
        XCTAssertNil(object["recipeCount"])
        XCTAssertNil(object["profileImageURL"])
    }

    func testCollectionPayloadNeverPublishesCoverImages() throws {
        let share = ShareMetadata.CollectionShare(
            collectionId: UUID().uuidString,
            ownerId: UUID().uuidString,
            identityRecordName: "user_current-user-record",
            title: "Weeknight",
            recipeCount: 1,
            recipeIds: [UUID().uuidString],
            capability: String(repeating: "c", count: 43),
            shouldCreate: true
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(share)) as? [String: Any]
        )
        XCTAssertNil(object["coverImageURL"])
    }

    func testRecipeSharePayloadContainsOnlyNonSensitiveWebSummary() throws {
        let recipeID = UUID(uuidString: "018F9344-54FF-42FC-83A8-C2A92E2D1B10")!
        let ownerID = UUID(uuidString: "9F082214-0C9E-4E30-94D7-072FC359D2F4")!
        let recipe = Recipe(
            id: recipeID,
            title: "Tomato Soup",
            ingredients: [
                Ingredient(
                    name: "tomatoes",
                    quantity: Quantity(value: 2, unit: .piece),
                    note: "ripe",
                    section: "Soup"
                )
            ],
            steps: [
                CookStep(index: 1, text: "Serve warm", section: "Finish"),
                CookStep(index: 0, text: "Simmer gently", section: "Cook")
            ],
            yields: "4 bowls",
            totalMinutes: 30,
            tags: [Tag(name: "Dinner")],
            sourceURL: URL(string: "https://user:password@example.com/soup?token=secret#method"),
            sourceTitle: "Family Soup",
            notes: "Freezes well. Source: https://user:password@example.com/soup?token=secret#method",
            imageURL: URL(string: "https://user:password@example.com/image.jpg?token=private"),
            visibility: .publicRecipe,
            ownerId: ownerID,
            originalCreatorName: "Grandma"
        )

        let payload = ShareMetadata.RecipeShare(
            recipe: recipe,
            identityRecordName: "user_current-user-record",
            capability: String(repeating: "a", count: 43)
        )

        XCTAssertEqual(payload.recipeId, recipeID.uuidString)
        XCTAssertEqual(payload.ownerId, ownerID.uuidString)
        XCTAssertEqual(payload.capability, String(repeating: "a", count: 43))
        XCTAssertTrue(payload.shouldCreate)

        let encoded = try JSONEncoder().encode(payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["title"] as? String, "Tomato Soup")
        XCTAssertEqual(object["totalMinutes"] as? Int, 30)
        XCTAssertEqual(object["tags"] as? [String], ["Dinner"])
        XCTAssertNil(object["imageURL"])
        XCTAssertNil(object["ingredientCount"])
        XCTAssertNil(object["ingredients"])
        XCTAssertNil(object["steps"])
        XCTAssertNil(object["yields"])
        XCTAssertNil(object["notes"])
        XCTAssertNil(object["sourceURL"])
        XCTAssertNil(object["sourceTitle"])
        XCTAssertNil(object["authorName"])
        XCTAssertNil(object["originalCreatorName"])
    }

    func testRecipeSharePayloadNeverPublishesImageURLs() throws {
        let recipe = Recipe(
            title: "Toast",
            ingredients: [Ingredient(name: "bread")],
            steps: [CookStep(index: 0, text: "Toast it")],
            imageURL: URL(string: "http://example.com/toast.jpg"),
            ownerId: UUID()
        )

        let payload = ShareMetadata.RecipeShare(
            recipe: recipe,
            identityRecordName: "user_current-user-record",
            capability: String(repeating: "a", count: 43)
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        XCTAssertNil(object["imageURL"])
    }
}
