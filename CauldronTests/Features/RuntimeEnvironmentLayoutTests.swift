//
//  RuntimeEnvironmentLayoutTests.swift
//  CauldronTests
//

import SwiftUI
import XCTest
@testable import Cauldron

final class RuntimeEnvironmentLayoutTests: XCTestCase {
    func testDesktopWorkspaceIsUsedForCatalyst() {
        XCTAssertTrue(RuntimeEnvironment.prefersDesktopWorkspace(
            isMacCatalystApp: true,
            isiOSAppOnMac: false
        ))
    }

    func testDesktopWorkspaceIsUsedForIOSAppOnMac() {
        XCTAssertTrue(RuntimeEnvironment.prefersDesktopWorkspace(
            isMacCatalystApp: false,
            isiOSAppOnMac: true
        ))
    }

    func testDesktopWorkspaceIsNotUsedForIPad() {
        XCTAssertFalse(RuntimeEnvironment.prefersDesktopWorkspace(
            isMacCatalystApp: false,
            isiOSAppOnMac: false
        ))
    }

    func testSelectingDesktopFriendsSectionClearsPushedDestination() {
        var state = FriendsDesktopRouteState()
        state.path.append(FriendsTabDestination.connections)

        state.select(.connections)

        XCTAssertEqual(state.section, .connections)
        XCTAssertEqual(state.path.count, 0)
    }
}
