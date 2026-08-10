import XCTest
@testable import Cauldron

@MainActor
final class SearchHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SearchHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRecordTrimsCollapsesDeduplicatesAndMovesNewestFirst() {
        let store = SearchHistoryStore(defaults: defaults, limit: 10)

        store.record("  chicken   soup ")
        store.record("Pasta")
        store.record("CHICKEN SOUP")

        XCTAssertEqual(store.entries, ["CHICKEN SOUP", "Pasta"])
    }

    func testHistoryIsBoundedAndPersistsAcrossStoreRecreation() {
        let key = "bounded"
        let store = SearchHistoryStore(defaults: defaults, key: key, limit: 3)
        store.record("one")
        store.record("two")
        store.record("three")
        store.record("four")

        let restored = SearchHistoryStore(defaults: defaults, key: key, limit: 3)
        XCTAssertEqual(restored.entries, ["four", "three", "two"])
    }

    func testEmptyQueriesAreIgnoredAndRemoveAndClearPersist() {
        let key = "remove"
        let store = SearchHistoryStore(defaults: defaults, key: key)
        store.record("   ")
        store.record("Crème brûlée")
        store.record("Soup")
        store.remove("creme brulee")

        XCTAssertEqual(store.entries, ["Soup"])
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNil(defaults.object(forKey: "\(key).anonymous"))
    }

    func testAccountSwitchesUseIndependentNamespaces() {
        let firstUserID = UUID()
        let secondUserID = UUID()
        let store = SearchHistoryStore(
            defaults: defaults,
            key: "accounts",
            ownerID: firstUserID
        )

        store.record("family soup")
        store.selectOwner(secondUserID)
        XCTAssertTrue(store.entries.isEmpty)

        store.record("private dessert")
        store.selectOwner(firstUserID)
        XCTAssertEqual(store.entries, ["family soup"])

        store.selectOwner(secondUserID)
        XCTAssertEqual(store.entries, ["private dessert"])
    }
}
