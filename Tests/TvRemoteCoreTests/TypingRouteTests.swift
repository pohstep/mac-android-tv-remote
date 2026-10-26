import XCTest
@testable import TvRemoteCore

final class TypingRouteTests: XCTestCase {
    func testASCIIPrefersDebugging() {
        XCTAssertEqual(
            TypingRoute.choose(text: "hello", brand: .generic, sonyAvailable: false, adbAvailable: true),
            .adb
        )
        XCTAssertEqual(
            TypingRoute.choose(text: "hello", brand: .sony, sonyAvailable: true, adbAvailable: false),
            .sony
        )
    }

    func testChineseUsesSonyWhenAFieldCanTakeIt() {
        XCTAssertFalse(TypingRoute.isASCII("你好"))
        XCTAssertEqual(
            TypingRoute.choose(text: "你好", brand: .sony, sonyAvailable: true, adbAvailable: true),
            .sony
        )
        guard case .unsupported(let message) = TypingRoute.choose(text: "你好", brand: .generic, sonyAvailable: false, adbAvailable: true) else {
            return XCTFail("expected a clear error")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("android"))
    }

    func testXiaomiCannotType() {
        guard case .unsupported(let message) = TypingRoute.choose(text: "hi", brand: .xiaomi, sonyAvailable: false, adbAvailable: true) else {
            return XCTFail("expected unsupported")
        }
        XCTAssertEqual(message, "This TV can't type from the remote.")
    }

    func testMissingRouteExplainsWhatIsNeeded() {
        guard case .unsupported(let message) = TypingRoute.choose(text: "hi", brand: .generic, sonyAvailable: false, adbAvailable: false) else {
            return XCTFail("expected unsupported")
        }
        XCTAssertTrue(message.contains("network debugging") || message.contains("text field"))
    }
}
