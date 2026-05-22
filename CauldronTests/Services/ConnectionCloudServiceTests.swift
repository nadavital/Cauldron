import XCTest
@testable import Cauldron

final class ConnectionCloudServiceTests: XCTestCase {
    func testCanonicalDuplicateConnectionKeepsAcceptedOverNewerPending() {
        let userA = UUID()
        let userB = UUID()
        let accepted = Connection(
            id: UUID(),
            fromUserId: userA,
            toUserId: userB,
            status: .accepted,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let newerPending = Connection(
            id: UUID(),
            fromUserId: userB,
            toUserId: userA,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let canonical = ConnectionCloudService.canonicalDuplicateConnection(from: [accepted, newerPending])

        XCTAssertEqual(canonical?.id, accepted.id)
    }

    func testCanonicalDuplicateConnectionUsesNewestWhenStatusesMatch() {
        let userA = UUID()
        let userB = UUID()
        let olderPending = Connection(
            id: UUID(),
            fromUserId: userA,
            toUserId: userB,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let newerPending = Connection(
            id: UUID(),
            fromUserId: userB,
            toUserId: userA,
            status: .pending,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300)
        )

        let canonical = ConnectionCloudService.canonicalDuplicateConnection(from: [olderPending, newerPending])

        XCTAssertEqual(canonical?.id, newerPending.id)
    }
}
