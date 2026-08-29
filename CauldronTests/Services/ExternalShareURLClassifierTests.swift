//
//  ExternalShareURLClassifierTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class ExternalShareURLClassifierTests: XCTestCase {
    func testExternalShareURLClassifier_AcceptsLegacyRoutesAndUserRoutes() throws {
        let accepted = [
            "https://cauldronrecipes.com/recipe/abc123",
            "https://cauldronrecipes.com/profile/nadav",
            "https://cauldronrecipes.com/collection/collection-id",
            "https://cauldronrecipes.com/u/nadav",
            "https://cauldronrecipes.com/u/nadav/recipe-id",
            "https://cauldron-f900a.web.app/recipe/abc123",
            "https://cauldron-f900a.web.app/profile/nadav",
            "https://cauldron-f900a.web.app/collection/collection-id",
            "https://cauldron-f900a.web.app/u/nadav",
            "https://cauldron-f900a.web.app/u/nadav/recipe-id",
            "https://cauldron-f900a.firebaseapp.com/recipe/recipe-id"
        ]

        for rawURL in accepted {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertTrue(ExternalShareURLClassifier.isExternalShareURL(url), rawURL)
        }
    }

    func testExternalShareURLClassifier_RejectsNonShareHostsAndIncompleteRoutes() throws {
        let rejected = [
            "https://example.com/u/nadav",
            "https://cauldron-prod.web.app/u/nadav",
            "https://cauldron-prod.firebaseapp.com/u/nadav/recipe-id",
            "https://evilweb.app.attacker.com/u/nadav",
            "https://cauldron-f900a.web.app.evil.com/u/nadav",
            "https://cauldron-f900a.web.app/u",
            "https://cauldron-f900a.web.app/u/nadav/recipe-id/extra",
            "https://cauldron-f900a.web.app/settings/account",
            "https://cauldron-f900a.web.app/recipe/abc123/extra",
            "http://cauldron-f900a.web.app/recipe/abc123",
            "ftp://cauldron-f900a.web.app/recipe/abc123",
            "cauldron://import/recipe/abc123"
        ]

        for rawURL in rejected {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertFalse(ExternalShareURLClassifier.isExternalShareURL(url), rawURL)
        }
    }

    func testReferralInviteLinkAcceptsOnlyOwnedHostingDomains() throws {
        let accepted = [
            "https://cauldronrecipes.com/invite/ABC123",
            "https://cauldron-f900a.web.app/invite/ABC123",
            "https://cauldron-f900a.firebaseapp.com/invite/ABC123",
            "cauldron://invite?code=ABC123",
        ]
        for rawURL in accepted {
            XCTAssertEqual(
                ReferralInviteLink.referralCode(from: try XCTUnwrap(URL(string: rawURL))),
                "ABC123",
                rawURL
            )
        }

        let rejected = [
            "https://cauldron-prod.web.app/invite/ABC123",
            "https://attacker.web.app/invite/ABC123",
            "https://cauldron-f900a.web.app.attacker.test/invite/ABC123",
            "http://cauldron-f900a.web.app/invite/ABC123",
            "ftp://cauldron-f900a.web.app/invite/ABC123",
        ]
        for rawURL in rejected {
            XCTAssertNil(
                ReferralInviteLink.referralCode(from: try XCTUnwrap(URL(string: rawURL))),
                rawURL
            )
        }
    }

    func testShareRouteParserCoversCanonicalLegacyAliasAndCustomSchemeRoutes() throws {
        let cases: [(String, ExternalShareURLClassifier.Route)] = [
            ("https://cauldronrecipes.com/u/nadav", .profile("nadav")),
            ("https://cauldronrecipes.com/recipe/recipe-id", .recipe("recipe-id")),
            ("https://cauldronrecipes.com/collection/collection-id", .collection("collection-id")),
            ("https://cauldron-f900a.web.app/u/nadav", .profile("nadav")),
            ("https://cauldron-f900a.web.app/u/nadav/recipe-id", .recipe("recipe-id")),
            ("https://cauldron-f900a.web.app/profile/user-id", .profile("user-id")),
            ("https://cauldron-f900a.web.app/recipe/recipe-id", .recipe("recipe-id")),
            ("https://cauldron-f900a.web.app/collection/collection-id", .collection("collection-id")),
            ("https://cauldron-f900a.firebaseapp.com/u/nadav/recipe-id", .recipe("recipe-id")),
            ("cauldron://import/recipe/recipe-id", .recipe("recipe-id")),
            ("cauldron://import/profile/nadav", .profile("nadav")),
            ("cauldron://import/collection/collection-id", .collection("collection-id")),
        ]
        for (rawURL, expected) in cases {
            XCTAssertEqual(
                ExternalShareURLClassifier.route(from: try XCTUnwrap(URL(string: rawURL))),
                expected,
                rawURL
            )
        }
    }

    func testShareRouteParserRejectsUnownedAndMalformedRoutes() throws {
        for rawURL in [
            "https://example.com/recipe/recipe-id",
            "http://cauldron-f900a.web.app/recipe/recipe-id",
            "https://cauldron-f900a.web.app/u/nadav/recipe-id/extra",
            "cauldron://evil/recipe/recipe-id",
            "cauldron://import/recipe/recipe-id/extra",
        ] {
            XCTAssertNil(
                ExternalShareURLClassifier.route(from: try XCTUnwrap(URL(string: rawURL))),
                rawURL
            )
        }
    }
}
