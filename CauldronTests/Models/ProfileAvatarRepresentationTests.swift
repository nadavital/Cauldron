import XCTest
@testable import Cauldron

final class ProfileAvatarRepresentationTests: XCTestCase {
    func testLegacyConflictDeterministicallyPrefersExplicitEmoji() {
        let user = User(
            username: "legacy",
            displayName: "Legacy User",
            profileEmoji: "🥘",
            profileColor: "#FF8800",
            profileImageURL: URL(fileURLWithPath: "/tmp/stale.jpg"),
            cloudProfileImageRecordName: "stale-photo",
            profileImageModifiedAt: Date(timeIntervalSince1970: 20),
            profileImageLocalRevision: UUID()
        )

        XCTAssertEqual(user.profileEmoji, "🥘")
        XCTAssertNil(user.profileImageURL)
        XCTAssertNil(user.cloudProfileImageRecordName)
        XCTAssertNil(user.profileImageModifiedAt)
        XCTAssertNil(user.profileImageLocalRevision)
        XCTAssertEqual(user.avatarRepresentation, .emoji(value: "🥘", colorHex: "#FF8800"))
    }

    func testCloudOnlyPhotoHasCanonicalPhotoRepresentation() {
        let modifiedAt = Date(timeIntervalSince1970: 30)
        let user = User(
            username: "cloud-photo",
            displayName: "Cloud Photo",
            cloudProfileImageRecordName: "profile-cloud-photo",
            profileImageModifiedAt: modifiedAt
        )

        guard case .photo(let photo) = user.avatarRepresentation else {
            return XCTFail("Cloud-only metadata must represent a photo avatar")
        }
        XCTAssertNil(photo.localURL)
        XCTAssertEqual(photo.cloudRecordName, "profile-cloud-photo")
        XCTAssertEqual(photo.modifiedAt, modifiedAt)
        XCTAssertEqual(AvatarType.initialSelection(for: user), .photo)
    }

    func testInitialsRemainCanonicalWhenNoExplicitAvatarExists() {
        let user = User(
            username: "initials",
            displayName: "Julia Child",
            profileColor: "#CC6600"
        )

        XCTAssertEqual(user.avatarRepresentation, .initials(value: "JC", colorHex: "#CC6600"))
    }

    func testCodableRoundTripNormalizesLegacyConflict() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "username": "legacy",
          "displayName": "Legacy",
          "createdAt": 0,
          "profileEmoji": "🍳",
          "profileImageURL": "file:///tmp/stale.jpg",
          "cloudProfileImageRecordName": "stale"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let user = try decoder.decode(User.self, from: json)

        XCTAssertEqual(user.avatarRepresentation, .emoji(value: "🍳", colorHex: nil))
        XCTAssertNil(user.profileImageURL)
        XCTAssertNil(user.cloudProfileImageRecordName)
    }
}
