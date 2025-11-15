//
//  ConnectionRepositoryTests.swift
//  CauldronTests
//
//  Created on November 14, 2025.
//

import XCTest
import SwiftData
@testable import Cauldron

@MainActor
final class ConnectionRepositoryTests: XCTestCase {

    var repository: ConnectionRepository!
    var modelContainer: ModelContainer!
    var user1Id: UUID!
    var user2Id: UUID!
    var user3Id: UUID!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        modelContainer = try TestModelContainer.create(with: [ConnectionModel.self])

        // Initialize repository
        repository = ConnectionRepository(modelContainer: modelContainer)

        // Create test user IDs
        user1Id = UUID()
        user2Id = UUID()
        user3Id = UUID()
    }

    override func tearDown() async throws {
        repository = nil
        modelContainer = nil
        user1Id = nil
        user2Id = nil
        user3Id = nil
        try await super.tearDown()
    }

    // MARK: - Save Tests

    func testSave_CreatesNewConnection() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )

        // When
        try await repository.save(connection)

        // Then
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, connection.id)
        XCTAssertEqual(fetched?.fromUserId, user1Id)
        XCTAssertEqual(fetched?.toUserId, user2Id)
        XCTAssertEqual(fetched?.status, .pending)
    }

    func testSave_UpdatesExistingConnection() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )
        try await repository.save(connection)

        // When - Update status to accepted
        let updatedConnection = Connection(
            id: connection.id,
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .accepted,
            createdAt: connection.createdAt,
            updatedAt: Date()
        )
        try await repository.save(updatedConnection)

        // Then
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, connection.id)
        XCTAssertEqual(fetched?.status, .accepted)
    }

    func testSave_WithUserInfo() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending,
            fromUsername: "user1",
            fromDisplayName: "User One"
        )

        // When
        try await repository.save(connection)

        // Then
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)
        XCTAssertEqual(fetched?.fromUsername, "user1")
        XCTAssertEqual(fetched?.fromDisplayName, "User One")
        // Note: ConnectionModel only persists fromUsername/fromDisplayName for notifications
        // toUsername/toDisplayName are not persisted in SwiftData
    }

    // MARK: - Fetch Connection Tests

    func testFetchConnection_Found() async throws {
        // Given
        let connection = Connection(fromUserId: user1Id, toUserId: user2Id)
        try await repository.save(connection)

        // When
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)

        // Then
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, connection.id)
    }

    func testFetchConnection_NotFound() async throws {
        // When
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)

        // Then
        XCTAssertNil(fetched)
    }

    func testFetchConnection_BidirectionalSearch() async throws {
        // Given - Connection from user1 to user2
        let connection = Connection(fromUserId: user1Id, toUserId: user2Id)
        try await repository.save(connection)

        // When - Search in reverse direction (user2 to user1)
        let fetched = try await repository.fetchConnection(fromUserId: user2Id, toUserId: user1Id)

        // Then - Should still find the connection
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, connection.id)
    }

    // MARK: - Fetch Connections Tests

    func testFetchConnections_EmptyList() async throws {
        // When
        let connections = try await repository.fetchConnections(forUserId: user1Id)

        // Then
        XCTAssertEqual(connections.count, 0)
    }

    func testFetchConnections_ReturnsUserConnections() async throws {
        // Given
        let connection1 = Connection(fromUserId: user1Id, toUserId: user2Id)
        let connection2 = Connection(fromUserId: user3Id, toUserId: user1Id)
        let connection3 = Connection(fromUserId: user2Id, toUserId: user3Id)

        try await repository.save(connection1)
        try await repository.save(connection2)
        try await repository.save(connection3)

        // When
        let connections = try await repository.fetchConnections(forUserId: user1Id)

        // Then - Should find connections where user1 is either from or to
        XCTAssertEqual(connections.count, 2)
        XCTAssertTrue(connections.contains { $0.id == connection1.id })
        XCTAssertTrue(connections.contains { $0.id == connection2.id })
        XCTAssertFalse(connections.contains { $0.id == connection3.id })
    }

    // MARK: - Fetch Accepted Connections Tests

    func testFetchAcceptedConnections_OnlyReturnsAccepted() async throws {
        // Given
        let pendingConnection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )
        let acceptedConnection = Connection(
            fromUserId: user1Id,
            toUserId: user3Id,
            status: .accepted
        )

        try await repository.save(pendingConnection)
        try await repository.save(acceptedConnection)

        // When
        let accepted = try await repository.fetchAcceptedConnections(forUserId: user1Id)

        // Then
        XCTAssertEqual(accepted.count, 1)
        XCTAssertEqual(accepted.first?.id, acceptedConnection.id)
    }

    func testFetchAcceptedConnections_EmptyWhenNoneAccepted() async throws {
        // Given
        let pendingConnection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )
        try await repository.save(pendingConnection)

        // When
        let accepted = try await repository.fetchAcceptedConnections(forUserId: user1Id)

        // Then
        XCTAssertEqual(accepted.count, 0)
    }

    // MARK: - Fetch Sent Requests Tests

    func testFetchSentRequests_OnlyReturnsRequestsSentByUser() async throws {
        // Given
        let sentRequest = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )
        let receivedRequest = Connection(
            fromUserId: user3Id,
            toUserId: user1Id,
            status: .pending
        )
        let acceptedConnection = Connection(
            fromUserId: user1Id,
            toUserId: user3Id,
            status: .accepted
        )

        try await repository.save(sentRequest)
        try await repository.save(receivedRequest)
        try await repository.save(acceptedConnection)

        // When
        let sent = try await repository.fetchSentRequests(fromUserId: user1Id)

        // Then - Should only return pending requests FROM user1
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.id, sentRequest.id)
    }

    // MARK: - Fetch Received Requests Tests

    func testFetchReceivedRequests_OnlyReturnsRequestsReceivedByUser() async throws {
        // Given
        let receivedRequest = Connection(
            fromUserId: user2Id,
            toUserId: user1Id,
            status: .pending
        )
        let sentRequest = Connection(
            fromUserId: user1Id,
            toUserId: user3Id,
            status: .pending
        )
        let acceptedConnection = Connection(
            fromUserId: user3Id,
            toUserId: user1Id,
            status: .accepted
        )

        try await repository.save(receivedRequest)
        try await repository.save(sentRequest)
        try await repository.save(acceptedConnection)

        // When
        let received = try await repository.fetchReceivedRequests(forUserId: user1Id)

        // Then - Should only return pending requests TO user1
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.id, receivedRequest.id)
    }

    // MARK: - Are Connected Tests

    func testAreConnected_ReturnsTrueForAcceptedConnection() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .accepted
        )
        try await repository.save(connection)

        // When
        let areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)

        // Then
        XCTAssertTrue(areConnected)
    }

    func testAreConnected_ReturnsFalseForPendingConnection() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending
        )
        try await repository.save(connection)

        // When
        let areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)

        // Then
        XCTAssertFalse(areConnected)
    }

    func testAreConnected_ReturnsFalseWhenNoConnection() async throws {
        // When
        let areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)

        // Then
        XCTAssertFalse(areConnected)
    }

    func testAreConnected_BidirectionalCheck() async throws {
        // Given
        let connection = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .accepted
        )
        try await repository.save(connection)

        // When - Check in reverse order
        let areConnected = try await repository.areConnected(user1: user2Id, user2: user1Id)

        // Then
        XCTAssertTrue(areConnected)
    }

    // MARK: - Delete Tests

    func testDelete_RemovesConnection() async throws {
        // Given
        let connection = Connection(fromUserId: user1Id, toUserId: user2Id)
        try await repository.save(connection)

        // When
        try await repository.delete(connection)

        // Then
        let fetched = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)
        XCTAssertNil(fetched)
    }

    func testDelete_NonExistentConnection_DoesNotThrow() async throws {
        // Given
        let connection = Connection(fromUserId: user1Id, toUserId: user2Id)

        // When/Then - Should not throw
        try await repository.delete(connection)
    }

    func testDelete_OnlyRemovesSpecificConnection() async throws {
        // Given
        let connection1 = Connection(fromUserId: user1Id, toUserId: user2Id)
        let connection2 = Connection(fromUserId: user1Id, toUserId: user3Id)
        try await repository.save(connection1)
        try await repository.save(connection2)

        // When
        try await repository.delete(connection1)

        // Then
        let fetched1 = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user2Id)
        let fetched2 = try await repository.fetchConnection(fromUserId: user1Id, toUserId: user3Id)
        XCTAssertNil(fetched1)
        XCTAssertNotNil(fetched2)
    }

    // MARK: - Integration Tests

    func testConnectionWorkflow_SendAcceptDelete() async throws {
        // Step 1: User1 sends connection request to User2
        let request = Connection(
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .pending,
            fromUsername: "user1",
            fromDisplayName: "User One"
        )
        try await repository.save(request)

        // Verify request is pending
        var sentRequests = try await repository.fetchSentRequests(fromUserId: user1Id)
        XCTAssertEqual(sentRequests.count, 1)

        var receivedRequests = try await repository.fetchReceivedRequests(forUserId: user2Id)
        XCTAssertEqual(receivedRequests.count, 1)

        var areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)
        XCTAssertFalse(areConnected)

        // Step 2: User2 accepts the request
        let acceptedConnection = Connection(
            id: request.id,
            fromUserId: user1Id,
            toUserId: user2Id,
            status: .accepted,
            createdAt: request.createdAt,
            updatedAt: Date(),
            fromUsername: "user1",
            fromDisplayName: "User One"
        )
        try await repository.save(acceptedConnection)

        // Verify connection is accepted
        areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)
        XCTAssertTrue(areConnected)

        let accepted = try await repository.fetchAcceptedConnections(forUserId: user1Id)
        XCTAssertEqual(accepted.count, 1)

        // Step 3: Delete the connection
        try await repository.delete(acceptedConnection)

        // Verify connection is removed
        areConnected = try await repository.areConnected(user1: user1Id, user2: user2Id)
        XCTAssertFalse(areConnected)

        let connections = try await repository.fetchConnections(forUserId: user1Id)
        XCTAssertEqual(connections.count, 0)
    }
}
