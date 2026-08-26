import XCTest
@testable import Cauldron

@MainActor
final class WhatsNewContentVersionTests: XCTestCase {
    func testSiriVisualSearchUpdateUsesANewContentGate() {
        XCTAssertEqual(ContentView.whatsNewContentVersion, "2.0")
        XCTAssertNotEqual(ContentView.whatsNewContentVersion, "1.8.4")
    }
}
