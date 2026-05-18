//
//  ConnectionCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class ConnectionCloudServiceRecordMappingTests: XCTestCase {
    func testPopulateConnectionRecordClearsRemovedOptionalFields() async throws {
        let service = ConnectionCloudService(core: CloudKitCore())
        let connectionId = UUID()
        let fromUserId = UUID()
        let toUserId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_400)
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_500)
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.connection,
            recordID: CKRecord.ID(recordName: connectionId.uuidString)
        )
        record["fromUsername"] = "old-from" as CKRecordValue
        record["fromDisplayName"] = "Old From" as CKRecordValue
        record["toUsername"] = "old-to" as CKRecordValue
        record["toDisplayName"] = "Old To" as CKRecordValue

        let connection = Connection(
            id: connectionId,
            fromUserId: fromUserId,
            toUserId: toUserId,
            status: .accepted,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        await service.populateConnectionRecord(record, from: connection)
        let decoded = try await service.connectionFromRecord(record)

        XCTAssertEqual(decoded.id, connectionId)
        XCTAssertEqual(decoded.fromUserId, fromUserId)
        XCTAssertEqual(decoded.toUserId, toUserId)
        XCTAssertEqual(decoded.status, .accepted)
        XCTAssertEqual(decoded.createdAt, createdAt)
        XCTAssertEqual(decoded.updatedAt, updatedAt)
        XCTAssertNil(record["fromUsername"])
        XCTAssertNil(record["fromDisplayName"])
        XCTAssertNil(record["toUsername"])
        XCTAssertNil(record["toDisplayName"])
    }
}
