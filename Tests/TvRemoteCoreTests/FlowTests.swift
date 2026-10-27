import XCTest
@testable import TvRemoteCore

final class FlowTests: XCTestCase {
    func testTypingReadinessAndEditMenu() {
        XCTAssertEqual(TypingReadiness.reading("mInputShown=true"), .ready)
        XCTAssertEqual(TypingReadiness.reading("mServedView=null"), .notReady)
        XCTAssertEqual(TypingReadiness.reading("mServedView=com.android.tv/.Search"), .ready)
        XCTAssertEqual(TypingReadiness.reading("mInputShown=false"), .notReady)
        XCTAssertEqual(TypingReadiness.reading("no field here"), .unknown)
        XCTAssertEqual(
            TypingReadiness.notReady,
            "Nothing on the TV is ready for typing. Open a search or text box on the TV, then Send again."
        )
        XCTAssertEqual(StandardEditMenu.items.map(\.keyEquivalent), ["x", "c", "v", "a"])
        XCTAssertEqual(StandardEditMenu.items.map(\.action), ["cut:", "copy:", "paste:", "selectAll:"])
        XCTAssertEqual(DroppedText.plain("  https://example.com/a \n"), "https://example.com/a")
    }
}
