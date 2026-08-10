import XCTest
@testable import Cauldron

final class ShareExtensionImportContractTests: XCTestCase {
    private var testFallbackLockURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        testFallbackLockURL = temporaryFallbackLockURL()
    }

    override func tearDownWithError() throws {
        if let testFallbackLockURL {
            try? FileManager.default.removeItem(at: testFallbackLockURL)
        }
        testFallbackLockURL = nil
        try super.tearDownWithError()
    }

    func testAtomicFileInboxPersistsItemBeforeReturningSuccess() throws {
        let directory = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ShareExtensionInboxItem(text: "Soup\nIngredients\n1 cup stock")

        try ShareExtensionInboxFiles.enqueue(item, directoryURL: directory)

        let persistedURL = directory
            .appendingPathComponent(item.id.uuidString)
            .appendingPathExtension("json")
        let persisted = try JSONDecoder().decode(
            ShareExtensionInboxItem.self,
            from: Data(contentsOf: persistedURL)
        )
        XCTAssertEqual(persisted, item)
    }

    func testAtomicPublicationCannotRecreateMirrorsAfterInterleavedAcknowledgement() throws {
        let directory = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeIsolatedDefaults()
        let item = ShareExtensionInboxItem(
            urlString: "https://example.com/race",
            text: "Race recipe"
        )

        let method = try ShareExtensionInboxFiles.publish(
            item,
            directoryURL: directory,
            fallbackDefaults: defaults,
            afterAtomicEnqueue: {
                // Simulate the app ingesting and acknowledging immediately
                // after the atomic file becomes visible to the other process.
                let url = directory
                    .appendingPathComponent(item.id.uuidString)
                    .appendingPathExtension("json")
                try? FileManager.default.removeItem(at: url)
            }
        )

        XCTAssertEqual(method, .atomicFile)
        XCTAssertTrue(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ).isEmpty
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
        XCTAssertNil(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey))
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty
        )
    }

    func testDefaultsInboxIsUsedOnlyWhenAtomicStorageIsUnavailable() throws {
        let defaults = try makeIsolatedDefaults()
        let lockURL = temporaryFallbackLockURL()
        defer { try? FileManager.default.removeItem(at: lockURL) }
        let item = ShareExtensionInboxItem(text: "Fallback recipe")

        let method = try ShareExtensionInboxFiles.publish(
            item,
            directoryURL: nil,
            fallbackDefaults: defaults,
            fallbackLockURL: lockURL
        )

        XCTAssertEqual(method, .defaultsInboxFallback)
        XCTAssertEqual(
            ShareExtensionImportStore.inbox(in: defaults, fallbackLockURL: lockURL),
            [item]
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
    }

    func testFallbackPublicationAndAcknowledgementCannotLoseOrResurrectItemsWhenInterleaved() throws {
        let defaults = try makeIsolatedDefaults()
        let lockURL = temporaryFallbackLockURL()
        defer { try? FileManager.default.removeItem(at: lockURL) }
        let acknowledged = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 1),
            text: "Already ingested"
        )
        let arriving = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 2),
            text: "Arriving concurrently"
        )
        defaults.set(
            try JSONEncoder().encode([acknowledged]),
            forKey: ShareExtensionImportContract.inboxKey
        )

        let fallbackRead = DispatchSemaphore(value: 0)
        let allowPublication = DispatchSemaphore(value: 0)
        let acknowledgementStarted = DispatchSemaphore(value: 0)
        let acknowledgementFinished = DispatchSemaphore(value: 0)
        let publicationFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = try? ShareExtensionInboxFiles.publish(
                arriving,
                directoryURL: nil,
                fallbackDefaults: defaults,
                fallbackLockURL: lockURL,
                afterFallbackInboxRead: {
                    fallbackRead.signal()
                    allowPublication.wait()
                }
            )
            publicationFinished.signal()
        }

        XCTAssertEqual(fallbackRead.wait(timeout: .now() + 2), .success)
        DispatchQueue.global().async {
            acknowledgementStarted.signal()
            ShareExtensionImportStore.acknowledgeTransportItem(
                id: acknowledged.id,
                in: defaults,
                fallbackLockURL: lockURL
            )
            acknowledgementFinished.signal()
        }

        XCTAssertEqual(acknowledgementStarted.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(
            acknowledgementFinished.wait(timeout: .now() + 0.05),
            .timedOut,
            "Acknowledgement must wait for the publisher's fallback transaction"
        )
        allowPublication.signal()
        XCTAssertEqual(publicationFinished.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(acknowledgementFinished.wait(timeout: .now() + 2), .success)

        XCTAssertEqual(
            ShareExtensionImportStore.inbox(in: defaults, fallbackLockURL: lockURL),
            [arriving]
        )
    }

    func testAtomicFileInboxThrowsWhenSharedContainerIsUnavailable() throws {
        let item = ShareExtensionInboxItem(text: "Recipe")

        XCTAssertThrowsError(
            try ShareExtensionInboxFiles.enqueue(item, directoryURL: nil)
        ) { error in
            XCTAssertEqual(
                error as? ShareExtensionInboxFiles.InboxError,
                .unavailableContainer
            )
        }
    }

    func testAtomicFileInboxRejectsNewItemAtCapacityWithoutDeletingExistingItems() throws {
        let directory = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var existingFiles: [URL: Data] = [:]
        for index in 0..<ShareExtensionImportContract.maximumInboxItemCount {
            let item = ShareExtensionInboxItem(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                text: "Recipe \(index)"
            )
            let data = try JSONEncoder().encode(item)
            let url = directory
                .appendingPathComponent(item.id.uuidString)
                .appendingPathExtension("json")
            try data.write(to: url, options: .atomic)
            existingFiles[url] = data
        }

        let overflow = ShareExtensionInboxItem(text: "Recipe 21")
        XCTAssertThrowsError(
            try ShareExtensionInboxFiles.enqueue(overflow, directoryURL: directory)
        ) { error in
            XCTAssertEqual(
                error as? ShareExtensionInboxFiles.InboxError,
                .inboxFull(maximumItemCount: ShareExtensionImportContract.maximumInboxItemCount)
            )
        }

        let filesAfterFailure = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        XCTAssertEqual(filesAfterFailure.count, ShareExtensionImportContract.maximumInboxItemCount)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent(overflow.id.uuidString)
                    .appendingPathExtension("json")
                    .path
            )
        )
        for (url, expectedData) in existingFiles {
            XCTAssertEqual(try Data(contentsOf: url), expectedData)
        }
    }

    func testAtomicFileInboxPropagatesWriteFailure() throws {
        let parent = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fileInsteadOfDirectory = parent.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: fileInsteadOfDirectory)

        XCTAssertThrowsError(
            try ShareExtensionInboxFiles.enqueue(
                ShareExtensionInboxItem(text: "Recipe"),
                directoryURL: fileInsteadOfDirectory
            )
        )
    }

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
        XCTAssertEqual(decoded.notes, payload.notes)

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
        XCTAssertEqual(ShareExtensionImportContract.inboxKey, "shareExtension.inbox.v1")
    }

    func testQueuedSharesAreReadAndAcknowledgedInFIFOOrder() throws {
        let defaults = try makeIsolatedDefaults()
        let first = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 1),
            urlString: "https://example.com/first"
        )
        let second = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 2),
            text: "Second recipe text"
        )
        defaults.set(try JSONEncoder().encode([first, second]), forKey: ShareExtensionImportContract.inboxKey)

        XCTAssertEqual(
            ShareExtensionImportStore.pendingRecipeURL(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            URL(string: "https://example.com/first")
        )
        XCTAssertNil(
            ShareExtensionImportStore.pendingRecipeText(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )

        ShareExtensionImportStore.acknowledgeTransportItem(
            id: first.id,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertEqual(
            ShareExtensionImportStore.pendingRecipeText(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            "Second recipe text"
        )
        ShareExtensionImportStore.acknowledgeTransportItem(
            id: second.id,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        XCTAssertTrue(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ).isEmpty
        )
    }

    func testLegacyAcknowledgementsNeverConsumeIdenticalNewDurableShares() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Repeated Soup",
            ingredients: ["Stock"],
            steps: ["Warm"]
        )
        let payloadData = try JSONEncoder().encode(payload)
        let urlString = "https://example.com/repeated"
        let text = "Repeated recipe text"
        let items = [
            ShareExtensionInboxItem(createdAt: Date(timeIntervalSince1970: 1), urlString: urlString),
            ShareExtensionInboxItem(createdAt: Date(timeIntervalSince1970: 2), text: text),
            ShareExtensionInboxItem(createdAt: Date(timeIntervalSince1970: 3), preparedPayload: payloadData)
        ]
        defaults.set(try JSONEncoder().encode(items), forKey: ShareExtensionImportContract.inboxKey)
        defaults.set(urlString, forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set(text, forKey: ShareExtensionImportContract.pendingRecipeTextKey)
        defaults.set(payloadData, forKey: ShareExtensionImportContract.preparedRecipePayloadKey)

        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: urlString),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        ShareExtensionImportStore.acknowledgePendingRecipeText(
            matching: text,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        ShareExtensionImportStore.acknowledgePreparedRecipe(
            matching: payloadData,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertEqual(
            ShareExtensionImportStore.inbox(in: defaults, fallbackLockURL: testFallbackLockURL).map(\.id),
            items.map(\.id)
        )
    }

    func testUnavailableFallbackLockDoesNotSurfaceOrAcknowledgeLegacyMirrors() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Stale Soup",
            ingredients: ["Stock"],
            steps: ["Warm"]
        )
        let payloadData = try JSONEncoder().encode(payload)
        defaults.set("https://example.com/stale", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("stale text", forKey: ShareExtensionImportContract.pendingRecipeTextKey)
        defaults.set(payloadData, forKey: ShareExtensionImportContract.preparedRecipePayloadKey)

        XCTAssertNil(ShareExtensionImportStore.pendingRecipeURL(in: defaults, fallbackLockURL: nil))
        XCTAssertNil(ShareExtensionImportStore.pendingRecipeText(in: defaults, fallbackLockURL: nil))
        XCTAssertNil(ShareExtensionImportStore.pendingPreparedRecipe(in: defaults, fallbackLockURL: nil))

        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: "https://example.com/stale"),
            in: defaults,
            fallbackLockURL: nil
        )
        ShareExtensionImportStore.acknowledgePendingRecipeText(
            matching: "stale text",
            in: defaults,
            fallbackLockURL: nil
        )
        ShareExtensionImportStore.acknowledgePreparedRecipe(
            matching: payloadData,
            in: defaults,
            fallbackLockURL: nil
        )

        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey), "https://example.com/stale")
        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey), "stale text")
        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey), payloadData)
    }

    func testUnopenableFallbackLockDoesNotConsumeLegacyMirrors() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("stale text", forKey: ShareExtensionImportContract.pendingRecipeTextKey)
        let parentFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareExtensionInboxLockParent-\(UUID().uuidString)")
        try Data("occupied".utf8).write(to: parentFile)
        defer { try? FileManager.default.removeItem(at: parentFile) }
        let unopenableLock = parentFile.appendingPathComponent("fallback.lock")

        XCTAssertNil(
            ShareExtensionImportStore.consumePendingRecipeText(
                in: defaults,
                fallbackLockURL: unopenableLock
            )
        )
        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey), "stale text")
    }

    func testCorruptFallbackInboxDoesNotFallThroughToLegacyMirrors() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set(Data("not an inbox".utf8), forKey: ShareExtensionImportContract.inboxKey)
        defaults.set("https://example.com/stale", forKey: ShareExtensionImportContract.pendingRecipeURLKey)

        XCTAssertEqual(ShareExtensionInboxFiles.fallbackInboxState(in: defaults), .corrupt)
        XCTAssertNil(
            ShareExtensionImportStore.pendingRecipeURL(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )
        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: "https://example.com/stale"),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.inboxKey), Data("not an inbox".utf8))
        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey), "https://example.com/stale")
    }

    func testConfirmedEmptyFallbackInboxPreservesLegacyCompatibility() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("https://example.com/legacy", forKey: ShareExtensionImportContract.pendingRecipeURLKey)

        XCTAssertEqual(
            ShareExtensionImportStore.pendingRecipeURL(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            URL(string: "https://example.com/legacy")
        )
        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: "https://example.com/legacy"),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
    }

    func testTransportAcknowledgementClearsOnlyMatchingLegacyURLMirror() throws {
        let defaults = try makeIsolatedDefaults()
        let item = ShareExtensionInboxItem(urlString: "https://example.com/completed")
        defaults.set(
            try JSONEncoder().encode([item]),
            forKey: ShareExtensionImportContract.inboxKey
        )
        defaults.set(
            "https://example.com/completed",
            forKey: ShareExtensionImportContract.pendingRecipeURLKey
        )
        defaults.set("newer text", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        ShareExtensionImportStore.acknowledgeTransportItem(
            id: item.id,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertTrue(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ).isEmpty
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertEqual(
            defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey),
            "newer text"
        )
    }

    func testTransportAcknowledgementClearsOnlyMatchingLegacyTextMirror() throws {
        let defaults = try makeIsolatedDefaults()
        let item = ShareExtensionInboxItem(text: "Completed recipe text")
        defaults.set(
            try JSONEncoder().encode([item]),
            forKey: ShareExtensionImportContract.inboxKey
        )
        defaults.set(
            "Completed recipe text",
            forKey: ShareExtensionImportContract.pendingRecipeTextKey
        )
        defaults.set(
            "https://example.com/newer",
            forKey: ShareExtensionImportContract.pendingRecipeURLKey
        )

        ShareExtensionImportStore.acknowledgeTransportItem(
            id: item.id,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertTrue(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ).isEmpty
        )
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
        XCTAssertEqual(
            defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey),
            "https://example.com/newer"
        )
    }

    func testTransportAcknowledgementClearsOnlyMatchingLegacyPreparedMirror() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Completed Soup",
            ingredients: ["Stock"],
            steps: ["Warm"]
        )
        let payloadData = try JSONEncoder().encode(payload)
        let item = ShareExtensionInboxItem(preparedPayload: payloadData)
        defaults.set(
            try JSONEncoder().encode([item]),
            forKey: ShareExtensionImportContract.inboxKey
        )
        defaults.set(payloadData, forKey: ShareExtensionImportContract.preparedRecipePayloadKey)
        defaults.set(
            "https://example.com/newer",
            forKey: ShareExtensionImportContract.pendingRecipeURLKey
        )

        ShareExtensionImportStore.acknowledgeTransportItem(
            id: item.id,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertTrue(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ).isEmpty
        )
        XCTAssertNil(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey))
        XCTAssertEqual(
            defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey),
            "https://example.com/newer"
        )
    }

    func testQueuedPreparedPayloadDoesNotMixWithNewerLegacyKeys() throws {
        let defaults = try makeIsolatedDefaults()
        let payload = PreparedShareRecipePayload(
            title: "Queued Soup",
            ingredients: ["Stock"],
            steps: ["Warm"]
        )
        let payloadData = try JSONEncoder().encode(payload)
        let item = ShareExtensionInboxItem(preparedPayload: payloadData)
        defaults.set(try JSONEncoder().encode([item]), forKey: ShareExtensionImportContract.inboxKey)
        defaults.set("https://example.com/newer-legacy", forKey: ShareExtensionImportContract.pendingRecipeURLKey)

        let pending = try XCTUnwrap(
            ShareExtensionImportStore.pendingPreparedRecipe(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )
        XCTAssertEqual(pending.preparedRecipe.recipe.title, "Queued Soup")
        XCTAssertEqual(pending.inboxID, item.id)
    }

    func testMalformedAndEmptyDefaultsInboxHeadsArePreservedAndBlockLegacyFallback() throws {
        let defaults = try makeIsolatedDefaults()
        let malformed = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 1),
            preparedPayload: Data("not-json".utf8)
        )
        let empty = ShareExtensionInboxItem(createdAt: Date(timeIntervalSince1970: 2))
        let invalidURL = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 3),
            urlString: "not a URL"
        )
        let valid = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 4),
            urlString: "https://example.com/recovered"
        )
        defaults.set(
            try JSONEncoder().encode([malformed, empty, invalidURL, valid]),
            forKey: ShareExtensionImportContract.inboxKey
        )
        defaults.set(
            "https://example.com/stale-legacy",
            forKey: ShareExtensionImportContract.pendingRecipeURLKey
        )

        XCTAssertNil(
            ShareExtensionImportStore.pendingRecipeURL(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )
        XCTAssertEqual(
            ShareExtensionImportStore.inbox(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            [malformed, empty, invalidURL, valid]
        )
        XCTAssertNotNil(defaults.data(forKey: ShareExtensionImportContract.inboxKey))
    }

    func testCorruptAtomicInboxIsPreservedAndBlocksStaleDefaultsFallback() throws {
        let directory = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corruptURL = directory.appendingPathComponent("corrupt.json")
        let corruptData = Data("not-an-inbox-item".utf8)
        try corruptData.write(to: corruptURL, options: .atomic)

        let defaults = try makeIsolatedDefaults()
        let stale = ShareExtensionInboxItem(text: "stale defaults recipe")
        defaults.set(
            try JSONEncoder().encode([stale]),
            forKey: ShareExtensionImportContract.inboxKey
        )

        XCTAssertNil(
            ShareExtensionImportStore.pendingTransportItem(
                directoryURL: directory,
                defaults: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )
        XCTAssertEqual(try Data(contentsOf: corruptURL), corruptData)
        if case .corrupt(let URLs) = ShareExtensionInboxFiles.atomicInboxState(
            directoryURL: directory
        ) {
            XCTAssertEqual(
                URLs.map { $0.resolvingSymlinksInPath().standardizedFileURL },
                [corruptURL.resolvingSymlinksInPath().standardizedFileURL]
            )
        } else {
            XCTFail("Expected the corrupt authoritative queue to fail closed")
        }
    }

    func testUnreadableExistingAtomicInboxBlocksDefaultsFallback() throws {
        let parent = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let fileInsteadOfDirectory = parent.appendingPathComponent("inbox")
        let authoritativeBytes = Data("authoritative-storage".utf8)
        try authoritativeBytes.write(to: fileInsteadOfDirectory)

        let defaults = try makeIsolatedDefaults()
        let fallback = ShareExtensionInboxItem(text: "newer fallback")
        defaults.set(
            try JSONEncoder().encode([fallback]),
            forKey: ShareExtensionImportContract.inboxKey
        )

        XCTAssertNil(
            ShareExtensionImportStore.pendingTransportItem(
                directoryURL: fileInsteadOfDirectory,
                defaults: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )
        XCTAssertEqual(try Data(contentsOf: fileInsteadOfDirectory), authoritativeBytes)
    }

    func testAtomicAndFallbackTransportsAreMergedByGlobalFIFOOrder() throws {
        let directory = temporaryInboxDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try makeIsolatedDefaults()
        let olderFallback = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 1),
            text: "older fallback"
        )
        let newerAtomic = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 2),
            text: "newer atomic"
        )
        try ShareExtensionInboxFiles.enqueue(newerAtomic, directoryURL: directory)
        defaults.set(
            try JSONEncoder().encode([olderFallback]),
            forKey: ShareExtensionImportContract.inboxKey
        )

        XCTAssertEqual(
            ShareExtensionImportStore.pendingTransportItem(
                directoryURL: directory,
                defaults: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            olderFallback
        )

        try FileManager.default.removeItem(at: directory)
        let newerFallback = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 4),
            text: "newer fallback"
        )
        let olderAtomic = ShareExtensionInboxItem(
            createdAt: Date(timeIntervalSince1970: 3),
            text: "older atomic"
        )
        try ShareExtensionInboxFiles.enqueue(olderAtomic, directoryURL: directory)
        defaults.set(
            try JSONEncoder().encode([newerFallback]),
            forKey: ShareExtensionImportContract.inboxKey
        )

        XCTAssertEqual(
            ShareExtensionImportStore.pendingTransportItem(
                directoryURL: directory,
                defaults: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
            olderAtomic
        )
    }

    func testPendingRecipeTextConsumption_LeavesPendingURLForCallerToSupersedeExplicitly() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("https://example.com/old-recipe", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("1 cup flour\nBake until done", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        XCTAssertEqual(
            ShareExtensionImportStore.consumePendingRecipeText(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            ),
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

        let prepared = try XCTUnwrap(
            ShareExtensionImportStore.consumePreparedRecipe(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )

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

        let pending = try XCTUnwrap(
            ShareExtensionImportStore.pendingPreparedRecipe(
                in: defaults,
                fallbackLockURL: testFallbackLockURL
            )
        )

        XCTAssertEqual(pending.preparedRecipe.recipe.title, "Durable Soup")
        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey), data)

        ShareExtensionImportStore.acknowledgePreparedRecipe(
            matching: Data("new payload".utf8),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        XCTAssertEqual(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey), data)

        ShareExtensionImportStore.acknowledgePreparedRecipe(
            matching: pending.payloadData,
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        XCTAssertNil(defaults.data(forKey: ShareExtensionImportContract.preparedRecipePayloadKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey))
        XCTAssertNil(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey))
    }

    func testPendingURLAndTextAcknowledgement_OnlyClearsMatchingPayload() throws {
        let defaults = try makeIsolatedDefaults()
        defaults.set("https://example.com/recipe", forKey: ShareExtensionImportContract.pendingRecipeURLKey)
        defaults.set("1 cup flour", forKey: ShareExtensionImportContract.pendingRecipeTextKey)

        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: "https://example.com/other"),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        ShareExtensionImportStore.acknowledgePendingRecipeText(
            matching: "other text",
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeURLKey), "https://example.com/recipe")
        XCTAssertEqual(defaults.string(forKey: ShareExtensionImportContract.pendingRecipeTextKey), "1 cup flour")

        ShareExtensionImportStore.acknowledgePendingRecipeURL(
            matching: URL(string: "https://example.com/recipe"),
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )
        ShareExtensionImportStore.acknowledgePendingRecipeText(
            matching: "1 cup flour",
            in: defaults,
            fallbackLockURL: testFallbackLockURL
        )

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

    private func temporaryInboxDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareExtensionInboxTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func temporaryFallbackLockURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareExtensionInboxTests-\(UUID().uuidString).lock")
    }
}
