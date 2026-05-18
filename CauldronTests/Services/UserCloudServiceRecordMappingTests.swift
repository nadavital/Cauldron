//
//  UserCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class UserCloudServiceRecordMappingTests: XCTestCase {
    func testPopulateUserRecordClearsRemovedOptionalFields() async throws {
        let service = UserCloudService(core: CloudKitCore())
        let userId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_300)
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.user,
            recordID: CKRecord.ID(recordName: "user_test")
        )
        record["referralCode"] = "ABC123" as CKRecordValue
        record["email"] = "old@example.com" as CKRecordValue
        record["profileEmoji"] = ":pan:" as CKRecordValue
        record["profileColor"] = "#FF9900" as CKRecordValue
        record["cloudProfileImageRecordName"] = "profileImage_old" as CKRecordValue
        record["profileImageModifiedAt"] = createdAt as CKRecordValue

        let user = User(
            id: userId,
            username: "  ChefUser  ",
            displayName: "  Chef User  ",
            email: nil,
            referralCode: nil,
            createdAt: createdAt,
            profileEmoji: nil,
            profileColor: nil,
            cloudProfileImageRecordName: nil,
            profileImageModifiedAt: nil
        )

        await service.populateUserRecord(record, from: user)

        XCTAssertEqual(record["userId"] as? String, userId.uuidString)
        XCTAssertEqual(record["username"] as? String, "chefuser")
        XCTAssertEqual(record["displayName"] as? String, "Chef User")
        XCTAssertEqual(record["createdAt"] as? Date, createdAt)
        XCTAssertNil(record["referralCode"])
        XCTAssertNil(record["email"])
        XCTAssertNil(record["profileEmoji"])
        XCTAssertNil(record["profileColor"])
        XCTAssertNil(record["cloudProfileImageRecordName"])
        XCTAssertNil(record["profileImageModifiedAt"])
    }
}
