import XCTest
@testable import Cauldron

final class RecipeImportInboxStoreTests: XCTestCase {
    private var directory: URL!
    private var store: RecipeImportInboxStore!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeImportInboxStoreTests-\(UUID().uuidString)")
        store = RecipeImportInboxStore(directoryURL: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripAndFIFOOrdering() async throws {
        let later = Date(timeIntervalSince1970: 20)
        let earlier = Date(timeIntervalSince1970: 10)
        let second = try await store.enqueue(source: .text("second"), now: later)
        let first = try await store.enqueue(source: .url("https://example.com"), now: earlier)

        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.map(\.id), [first.id, second.id])
    }

    func testShareTransportIngestionIsIdempotent() async throws {
        let item = ShareExtensionInboxItem(text: "Recipe")
        let first = try await store.ingest(item)
        let second = try await store.ingest(item)

        XCTAssertEqual(first.id, second.id)
        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.count, 1)
    }

    func testEquivalentPendingURLsAreEnqueuedOnce() async throws {
        let first = try await store.enqueueIfAbsent(
            source: .url("HTTPS://Example.COM:443/recipe?servings=4#ingredients")
        )
        let retry = try await store.enqueueIfAbsent(
            source: .url("https://example.com/recipe?servings=4#directions")
        )

        XCTAssertEqual(retry.id, first.id)
        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.count, 1)
    }

    func testURLCanonicalizationPreservesMeaningfulPathAndQueryDifferences() async throws {
        _ = try await store.enqueueIfAbsent(source: .url("https://example.com/recipe?servings=2"))
        _ = try await store.enqueueIfAbsent(source: .url("https://example.com/recipe?servings=4"))
        _ = try await store.enqueueIfAbsent(source: .url("https://example.com/recipe/"))

        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.count, 3)
    }

    func testEquivalentPendingTextIsEnqueuedOnce() async throws {
        let first = try await store.enqueueIfAbsent(source: .text("  Soup\r\n1 cup water  "))
        let retry = try await store.enqueueIfAbsent(source: .text("Soup\n1 cup water"))

        XCTAssertEqual(retry.id, first.id)
        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.count, 1)
    }

    func testCompletedEquivalentJobAllowsNewEnqueue() async throws {
        let first = try await store.enqueueIfAbsent(source: .text("Soup"))
        _ = try await store.transition(id: first.id, to: .completed)

        let second = try await store.enqueueIfAbsent(source: .text(" Soup "))

        XCTAssertNotEqual(second.id, first.id)
        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.count, 2)
    }

    func testEquivalentFailedJobIsAtomicallyResetForRetry() async throws {
        let first = try await store.enqueueIfAbsent(source: .text("Soup"))
        _ = try await store.transition(id: first.id, to: .failed, errorCategory: "parse")

        let retry = try await store.enqueueIfAbsentWithDisposition(
            source: .text(" Soup "),
            now: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(retry.job.id, first.id)
        XCTAssertEqual(retry.job.state, .received)
        XCTAssertEqual(retry.job.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(retry.job.lastErrorCategory)
        XCTAssertEqual(retry.disposition, .retried)

        let claimed = try await store.claimNext(now: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(claimed?.id, first.id)
        XCTAssertEqual(claimed?.state, .processing)
    }

    func testClaimAndRecoverInterruptedJob() async throws {
        let created = Date(timeIntervalSince1970: 10)
        let job = try await store.enqueue(source: .text("Recipe"), now: created)
        let claimed = try await store.claimNext(now: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(claimed?.id, job.id)
        XCTAssertEqual(claimed?.state, .processing)
        XCTAssertEqual(claimed?.attemptCount, 1)

        let recovered = try await store.recoverStaleProcessing(
            before: Date(timeIntervalSince1970: 30),
            now: Date(timeIntervalSince1970: 40)
        )
        XCTAssertEqual(recovered, 1)
        let restored = try await store.job(id: job.id)
        XCTAssertEqual(restored?.state, .received)
        XCTAssertEqual(restored?.lastErrorCategory, "interrupted")
    }

    func testInvalidTransitionIsRejected() async throws {
        let job = try await store.enqueue(source: .text("Recipe"))
        do {
            _ = try await store.transition(id: job.id, to: .ready)
            XCTFail("Expected invalid transition")
        } catch let error as RecipeImportInboxStore.StoreError {
            XCTAssertEqual(error, .invalidTransition)
        }
    }

    func testCorruptFilesAreQuarantinedWithoutDroppingValidJobs() async throws {
        let valid = try await store.enqueue(source: .text("Recipe"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))

        let jobs = try await store.jobs()
        XCTAssertEqual(jobs.map(\.id), [valid.id])
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Corrupt"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantined.count, 1)
    }

    func testOversizedJobFileIsQuarantinedWithoutLoadingIt() async throws {
        let valid = try await store.enqueue(source: .text("Recipe"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let oversizedURL = directory.appendingPathComponent("oversized.json")
        try Data(count: RecipeImportInboxStore.maximumJobFileBytes + 1).write(to: oversizedURL)

        let jobs = try await store.jobs()

        XCTAssertEqual(jobs.map(\.id), [valid.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oversizedURL.path))
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("Corrupt"),
            includingPropertiesForKeys: [.fileSizeKey]
        )
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(
            try quarantined[0].resourceValues(forKeys: [.fileSizeKey]).fileSize,
            RecipeImportInboxStore.maximumJobFileBytes + 1
        )
    }

    func testOversizedPreparedPayloadIsRejectedBeforePersistence() async throws {
        let oversizedPayload = Data(count: RecipeImportInboxStore.maximumPayloadBytes + 1)

        do {
            _ = try await store.enqueue(source: .prepared(oversizedPayload))
            XCTFail("Expected payload size validation")
        } catch let error as RecipeImportInboxStore.StoreError {
            XCTAssertEqual(
                error,
                .payloadTooLarge(maximumBytes: RecipeImportInboxStore.maximumPayloadBytes)
            )
        }

        let jobs = try await store.jobs()
        XCTAssertTrue(jobs.isEmpty)
    }

    func testFailedJobDoesNotStarveLaterReceivedJob() async throws {
        let failed = try await store.enqueue(
            source: .text("bad"),
            now: Date(timeIntervalSince1970: 1)
        )
        _ = try await store.claimNext(now: Date(timeIntervalSince1970: 2))
        _ = try await store.transition(id: failed.id, to: .failed, errorCategory: "parse")
        let later = try await store.enqueue(
            source: .text("good"),
            now: Date(timeIntervalSince1970: 3)
        )

        let claimed = try await store.claimNext()
        XCTAssertEqual(claimed?.id, later.id)
    }

    func testPersistsAcrossStoreRecreation() async throws {
        let job = try await store.enqueue(source: .text("Recipe"))
        let reopened = RecipeImportInboxStore(directoryURL: directory)
        let jobs = try await reopened.jobs()
        XCTAssertEqual(jobs.map(\.id), [job.id])
    }

    func testLegacySchemaOneJobWithoutNewerOptionalFieldsStillLoads() async throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 42)
        let legacyJob = RecipeImportJob(
            id: id,
            createdAt: createdAt,
            source: .text("Legacy recipe")
        )
        let encoded = try JSONEncoder().encode(legacyJob)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "updatedAt")
        object.removeValue(forKey: "state")
        object.removeValue(forKey: "attemptCount")

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(
            to: directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        )

        let jobs = try await store.jobs()
        let loaded = try XCTUnwrap(jobs.first)
        XCTAssertEqual(loaded.id, id)
        XCTAssertEqual(loaded.schemaVersion, RecipeImportJob.currentSchemaVersion)
        XCTAssertEqual(loaded.updatedAt, createdAt)
        XCTAssertEqual(loaded.state, .received)
        XCTAssertEqual(loaded.attemptCount, 0)
        XCTAssertEqual(loaded.source, .text("Legacy recipe"))
    }

    func testRetriedReceivedJobCanCompleteWithoutBeingOfferedAgain() async throws {
        let job = try await store.enqueue(source: .text("Recipe"))
        _ = try await store.transition(id: job.id, to: .failed, errorCategory: "parse")
        _ = try await store.transition(id: job.id, to: .received)

        try await store.complete(id: job.id)

        let completed = try await store.job(id: job.id)
        let jobs = try await store.jobs()
        XCTAssertNil(completed)
        XCTAssertTrue(jobs.isEmpty)
    }
}
