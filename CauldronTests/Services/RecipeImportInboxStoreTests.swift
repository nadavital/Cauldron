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
