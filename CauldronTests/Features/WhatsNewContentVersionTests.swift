import XCTest
@testable import Cauldron

@MainActor
final class WhatsNewContentVersionTests: XCTestCase {
    func testSiriVisualSearchUpdateUsesANewContentGate() {
        XCTAssertEqual(ContentView.whatsNewContentVersion, "1.8.4")
        XCTAssertNotEqual(ContentView.whatsNewContentVersion, "1.8.3")
    }
}
