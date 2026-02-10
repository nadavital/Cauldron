//
//  PeopleDiscoveryStateMappingTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

@MainActor
final class PeopleDiscoveryStateMappingTests: XCTestCase {
    func testSearchAndPeopleSheet_useSameStateMappingForSameManagedConnection() {
        let currentUserId = UUID()
        let otherUserId = UUID()

        let managedConnection = ManagedConnection(
            connection: Connection(
                fromUserId: otherUserId,
                toUserId: currentUserId,
                status: .pending
            ),
            syncState: .synced
        )

        let searchState = ConnectionRelationshipState.from(
            managedConnection: managedConnection,
            currentUserId: currentUserId,
            otherUserId: otherUserId
        )
        let peopleSheetState = ConnectionRelationshipState.from(
            managedConnection: managedConnection,
            currentUserId: currentUserId,
            otherUserId: otherUserId
        )

        XCTAssertEqual(searchState, .pendingIncoming)
        XCTAssertEqual(peopleSheetState, .pendingIncoming)
        XCTAssertEqual(searchState, peopleSheetState)
    }
}
