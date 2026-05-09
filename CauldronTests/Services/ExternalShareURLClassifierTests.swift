//
//  ExternalShareURLClassifierTests.swift
//  CauldronTests
//

import XCTest
@testable import Cauldron

final class ExternalShareURLClassifierTests: XCTestCase {
    func testExternalShareURLClassifier_AcceptsLegacyRoutesAndUserRoutes() throws {
        let accepted = [
            "https://cauldron.app/recipe/abc123",
            "https://cauldron.app/profile/nadav",
            "https://cauldron.app/collection/collection-id",
            "https://cauldron.app/u/nadav",
            "https://cauldron.app/u/nadav/recipe-id",
            "https://cauldron-prod.web.app/u/nadav",
            "https://cauldron-prod.firebaseapp.com/u/nadav/recipe-id"
        ]

        for rawURL in accepted {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertTrue(ExternalShareURLClassifier.isExternalShareURL(url), rawURL)
        }
    }

    func testExternalShareURLClassifier_RejectsNonShareHostsAndIncompleteRoutes() throws {
        let rejected = [
            "https://example.com/u/nadav",
            "https://evilweb.app.attacker.com/u/nadav",
            "https://cauldron-f900a.web.app.evil.com/u/nadav",
            "https://cauldron.app/u",
            "https://cauldron.app/u/nadav/recipe-id/extra",
            "https://cauldron.app/settings/account",
            "https://cauldron.app/recipe/abc123/extra",
            "cauldron://import/recipe/abc123"
        ]

        for rawURL in rejected {
            let url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertFalse(ExternalShareURLClassifier.isExternalShareURL(url), rawURL)
        }
    }
}
