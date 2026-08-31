//
//  UserCloudServiceRecordMappingTests.swift
//  CauldronTests
//

import CloudKit
import XCTest
@testable import Cauldron

@MainActor
final class UserCloudServiceRecordMappingTests: XCTestCase {
    func testCapabilityRegistrationAcceptsNewerGeneration() {
        XCTAssertEqual(
            UserCloudService.capabilityRegistrationDecision(
                registeredGeneration: 2,
                registeredHash: "old",
                incomingGeneration: 3,
                incomingHash: "new"
            ),
            .accept
        )
    }

    func testCapabilityRegistrationRejectsStaleGeneration() {
        XCTAssertEqual(
            UserCloudService.capabilityRegistrationDecision(
                registeredGeneration: 3,
                registeredHash: "new",
                incomingGeneration: 2,
                incomingHash: "old"
            ),
            .stale
        )
    }

    func testCapabilityRegistrationDetectsSameGenerationConflict() {
        XCTAssertEqual(
            UserCloudService.capabilityRegistrationDecision(
                registeredGeneration: 3,
                registeredHash: "first",
                incomingGeneration: 3,
                incomingHash: "second"
            ),
            .conflict
        )
    }

    func testCapabilityRegistrationRecognizesIdempotentRegistration() {
        XCTAssertEqual(
            UserCloudService.capabilityRegistrationDecision(
                registeredGeneration: 3,
                registeredHash: "same",
                incomingGeneration: 3,
                incomingHash: "same"
            ),
            .alreadyRegistered
        )
    }

    func testUsernameClaimAcceptsMatchingCreatorIdentity() {
        XCTAssertTrue(UserCloudService.usernameClaimBelongsToUser(
            recordType: CloudKitCore.RecordType.usernameClaim,
            claimedUserID: "user-id",
            claimedUsername: "chef",
            claimedIdentityRecordName: "icloud-id",
            creatorRecordName: "icloud-id",
            expectedUserID: "user-id",
            expectedUsername: "chef",
            expectedIdentityRecordName: "icloud-id"
        ))
    }

    func testUsernameClaimAcceptsCurrentUserCreatorAliasWithMatchingConcreteIdentity() {
        XCTAssertTrue(UserCloudService.usernameClaimBelongsToUser(
            recordType: CloudKitCore.RecordType.usernameClaim,
            claimedUserID: "user-id",
            claimedUsername: "chef",
            claimedIdentityRecordName: "icloud-id",
            creatorRecordName: CKCurrentUserDefaultName,
            expectedUserID: "user-id",
            expectedUsername: "chef",
            expectedIdentityRecordName: "icloud-id"
        ))
    }

    func testUsernameClaimRejectsCurrentUserAliasWhenConcreteIdentityDiffers() {
        XCTAssertFalse(UserCloudService.usernameClaimBelongsToUser(
            recordType: CloudKitCore.RecordType.usernameClaim,
            claimedUserID: "user-id",
            claimedUsername: "chef",
            claimedIdentityRecordName: "other-icloud-id",
            creatorRecordName: CKCurrentUserDefaultName,
            expectedUserID: "user-id",
            expectedUsername: "chef",
            expectedIdentityRecordName: "icloud-id"
        ))
    }

    func testUsernameClaimRejectsWritableIdentityWhenCreatorDiffers() {
        XCTAssertFalse(UserCloudService.usernameClaimBelongsToUser(
            recordType: CloudKitCore.RecordType.usernameClaim,
            claimedUserID: "user-id",
            claimedUsername: "chef",
            claimedIdentityRecordName: "icloud-id",
            creatorRecordName: "server-owner",
            expectedUserID: "user-id",
            expectedUsername: "chef",
            expectedIdentityRecordName: "icloud-id"
        ))
    }

    func testUsernameClaimRejectsDifferentIdentityOrAccount() {
        XCTAssertFalse(UserCloudService.usernameClaimBelongsToUser(
            recordType: CloudKitCore.RecordType.usernameClaim,
            claimedUserID: "other-user",
            claimedUsername: "chef",
            claimedIdentityRecordName: "other-icloud-id",
            creatorRecordName: "other-icloud-id",
            expectedUserID: "user-id",
            expectedUsername: "chef",
            expectedIdentityRecordName: "icloud-id"
        ))
    }

    func testHistoricalUsernameClaimsRemainReservedUntilAccountDeletion() {
        XCTAssertFalse(UserCloudService.shouldReleaseUsernameClaims(keeping: "current_name"))
        XCTAssertTrue(UserCloudService.shouldReleaseUsernameClaims(keeping: nil))
    }

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

    func testUserFromLegacyConflictingRecordPrefersEmojiAndDropsPhotoMetadata() async throws {
        let service = UserCloudService(core: CloudKitCore())
        let record = CKRecord(
            recordType: CloudKitCore.RecordType.user,
            recordID: CKRecord.ID(recordName: "user_conflicting_avatar")
        )
        record["userId"] = UUID().uuidString as CKRecordValue
        record["username"] = "legacy" as CKRecordValue
        record["displayName"] = "Legacy" as CKRecordValue
        record["profileEmoji"] = "🍲" as CKRecordValue
        record["profileColor"] = "#FF8800" as CKRecordValue
        record["cloudProfileImageRecordName"] = "stale-photo" as CKRecordValue
        record["profileImageModifiedAt"] = Date(timeIntervalSince1970: 10) as CKRecordValue

        let user = try await service.userFromRecord(record)

        XCTAssertEqual(user.avatarRepresentation, .emoji(value: "🍲", colorHex: "#FF8800"))
        XCTAssertNil(user.cloudProfileImageRecordName)
        XCTAssertNil(user.profileImageModifiedAt)
    }
}
