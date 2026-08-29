import XCTest
@testable import Cauldron

@MainActor
final class ExternalSharePayloadTests: XCTestCase {
    func testCapabilityRegistrationRotatesAfterSameGenerationConflict() async throws {
        let original = UserCloudService.WebShareCredential(capability: "original", generation: 1)
        let replacement = UserCloudService.WebShareCredential(capability: "replacement", generation: 2)
        var events: [String] = []

        let credential = try await WebShareCapabilityRegistrationWorkflow.recover {
            events.append("resolve")
            return original
        } rotate: {
            events.append("rotate")
            return replacement
        } register: { candidate in
            events.append("register-\(candidate.generation)")
            if candidate == original {
                throw CloudKitError.webShareCapabilityConflict
            }
            return true
        }

        XCTAssertEqual(credential, replacement)
        XCTAssertEqual(events, ["resolve", "register-1", "rotate", "register-2"])
    }

    func testCapabilityRegistrationReResolvesAfterStaleGeneration() async throws {
        let original = UserCloudService.WebShareCredential(capability: "original", generation: 1)
        let refreshed = UserCloudService.WebShareCredential(capability: "refreshed", generation: 2)
        var resolveCount = 0
        var rotateCount = 0

        let credential = try await WebShareCapabilityRegistrationWorkflow.recover {
            resolveCount += 1
            return resolveCount == 1 ? original : refreshed
        } rotate: {
            rotateCount += 1
            return refreshed
        } register: { candidate in
            candidate == refreshed
        }

        XCTAssertEqual(credential, refreshed)
        XCTAssertEqual(resolveCount, 2)
        XCTAssertEqual(rotateCount, 0)
    }

    func testCapabilityRegistrationDoesNotRotateForUnrelatedErrors() async {
        let original = UserCloudService.WebShareCredential(capability: "original", generation: 1)
        var rotateCount = 0

        do {
            _ = try await WebShareCapabilityRegistrationWorkflow.recover {
                original
            } rotate: {
                rotateCount += 1
                return original
            } register: { _ in
                throw CloudKitError.permissionDenied
            }
            XCTFail("Expected permissionDenied")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .permissionDenied)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(rotateCount, 0)
    }

    func testCapabilityRegistrationDoesNotRotateForSaveContention() async {
        let original = UserCloudService.WebShareCredential(capability: "original", generation: 1)
        var rotateCount = 0

        do {
            _ = try await WebShareCapabilityRegistrationWorkflow.recover {
                original
            } rotate: {
                rotateCount += 1
                return original
            } register: { _ in
                throw CloudKitError.syncConflict
            }
            XCTFail("Expected syncConflict")
        } catch let error as CloudKitError {
            XCTAssertEqual(error, .syncConflict)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(rotateCount, 0)
    }

    func testOwnerMutationCoordinatorKeepsRecoveredCredentialCurrentThroughPublication() async throws {
        let ownerID = UUID()
        let coordinator = WebShareOwnerMutationCoordinator()
        var generation: Int64 = 1
        var currentCapability = "original"
        var events: [String] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let firstReachedPublication = expectation(description: "first reached publication")
        let secondAttemptedAcquisition = expectation(description: "second attempted acquisition")

        let first = Task { @MainActor in
            try await coordinator.perform(ownerID: ownerID) {
                var registrationAttempts = 0
                let credential = try await WebShareCapabilityRegistrationWorkflow.recover {
                    UserCloudService.WebShareCredential(
                        capability: currentCapability,
                        generation: generation
                    )
                } rotate: {
                    generation += 1
                    currentCapability = "capability-\(generation)"
                    events.append("rotate-\(generation)")
                    return UserCloudService.WebShareCredential(
                        capability: currentCapability,
                        generation: generation
                    )
                } register: { candidate in
                    registrationAttempts += 1
                    if registrationAttempts == 1 {
                        throw CloudKitError.webShareCapabilityConflict
                    }
                    currentCapability = candidate.capability
                    return true
                }

                firstReachedPublication.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                }
                XCTAssertEqual(credential.capability, currentCapability)
                events.append("publish-\(credential.generation)")
            }
        }

        await fulfillment(of: [firstReachedPublication], timeout: 1)
        let second = Task { @MainActor in
            secondAttemptedAcquisition.fulfill()
            try await coordinator.perform(ownerID: ownerID) {
                var registrationAttempts = 0
                let credential = try await WebShareCapabilityRegistrationWorkflow.recover {
                    UserCloudService.WebShareCredential(
                        capability: currentCapability,
                        generation: generation
                    )
                } rotate: {
                    generation += 1
                    currentCapability = "capability-\(generation)"
                    events.append("rotate-\(generation)")
                    return UserCloudService.WebShareCredential(
                        capability: currentCapability,
                        generation: generation
                    )
                } register: { candidate in
                    registrationAttempts += 1
                    if registrationAttempts == 1 {
                        throw CloudKitError.webShareCapabilityConflict
                    }
                    currentCapability = candidate.capability
                    return true
                }

                XCTAssertEqual(credential.capability, currentCapability)
                events.append("publish-\(credential.generation)")
            }
        }

        await fulfillment(of: [secondAttemptedAcquisition], timeout: 1)
        while coordinator.queuedMutationCount(for: ownerID) < 1 {
            await Task.yield()
        }
        XCTAssertEqual(events, ["rotate-2"])
        releaseFirst?.resume()
        try await first.value
        try await second.value
        XCTAssertEqual(events, ["rotate-2", "publish-2", "rotate-3", "publish-3"])
    }

    func testOwnerMutationCoordinatorSkipsCancelledWaiterAndAdvancesQueue() async throws {
        let ownerID = UUID()
        let coordinator = WebShareOwnerMutationCoordinator()
        var releaseFirst: CheckedContinuation<Void, Never>?
        var cancelledOperationRan = false
        var finalOperationRan = false
        let firstStarted = expectation(description: "first started")

        let first = Task { @MainActor in
            try await coordinator.perform(ownerID: ownerID) {
                firstStarted.fulfill()
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                }
            }
        }
        await fulfillment(of: [firstStarted], timeout: 1)

        let cancelled = Task { @MainActor in
            try await coordinator.perform(ownerID: ownerID) {
                cancelledOperationRan = true
            }
        }
        while coordinator.queuedMutationCount(for: ownerID) < 1 {
            await Task.yield()
        }
        cancelled.cancel()

        let final = Task { @MainActor in
            try await coordinator.perform(ownerID: ownerID) {
                finalOperationRan = true
            }
        }
        while coordinator.queuedMutationCount(for: ownerID) < 2 {
            await Task.yield()
        }
        releaseFirst?.resume()

        try await first.value
        do {
            try await cancelled.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        try await final.value
        XCTAssertFalse(cancelledOperationRan)
        XCTAssertTrue(finalOperationRan)
    }

    func testPublicationResponseReportsWhetherSnapshotWasActuallyWritten() throws {
        let response = try JSONDecoder().decode(
            ShareResponse.self,
            from: Data(#"{"shareId":"recipe-id","shareUrl":"https://cauldronrecipes.com/recipe/recipe-id","published":true}"#.utf8)
        )

        XCTAssertEqual(response.published, true)
    }

    func testLegacyPublicationResponseStillDecodesForCompatibility() throws {
        let response = try JSONDecoder().decode(
            ShareResponse.self,
            from: Data(#"{"shareId":"recipe-id","shareUrl":"https://cauldronrecipes.com/recipe/recipe-id"}"#.utf8)
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
