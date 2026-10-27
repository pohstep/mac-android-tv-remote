import XCTest
@testable import TvRemoteCore

final class DemoTests: XCTestCase {
    func testOfferAppearsOnlyWhenNothingWasFound() {
        XCTAssertFalse(DemoOffer.showWhenNoneFound(searching: true, matchCount: 0))
        XCTAssertFalse(DemoOffer.showWhenNoneFound(searching: false, matchCount: 1))
        XCTAssertFalse(DemoOffer.showWhenNoneFound(searching: false, matchCount: 3))
        XCTAssertTrue(DemoOffer.showWhenNoneFound(searching: false, matchCount: 0))
    }

    func testDemoReturnsCannedResultsAndMakesNoCalls() throws {
        let commands = FakeRunner()
        let http = ScriptedHTTP()
        let wake = FakeWake()
        let demo = DemoSession(commands: commands, http: http, wake: wake)

        XCTAssertEqual(demo.press(.dpadCenter).title, "Sent.")
        XCTAssertFalse(demo.press(.home).isError)
        XCTAssertEqual(demo.type("hello").title, "Sent.")
        XCTAssertEqual(demo.type("https://example.com/show").title, "Sent.")
        XCTAssertEqual(demo.refresh(), .connected(serial: "Demo TV"))

        let file = demo.sendFile(at: "/tmp/clip.mp4")
        XCTAssertEqual(file.sentence, "The file is in Downloads. The TV needs a player to open it.")
        XCTAssertFalse(file.isError)

        let install = demo.installApk(at: "/tmp/app.apk", clearingCancel: true)
        XCTAssertEqual(install.sentence, "Installed.")
        XCTAssertFalse(install.isError)

        let shot = demo.captureScreenshot()
        XCTAssertFalse(shot.isError)
        XCTAssertEqual(shot.sentence, "Screenshot.")
        let png = try XCTUnwrap(shot.png)
        XCTAssertEqual(ScreenshotBytes.kind(png), .picture)
        XCTAssertEqual([UInt8](png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])

        XCTAssertTrue(commands.calls.isEmpty)
        XCTAssertEqual(commands.cancelCount, 0)
        XCTAssertTrue(http.calls.isEmpty)
        XCTAssertTrue(wake.sent.isEmpty)

        let copy = [
            DemoCopy.name, DemoCopy.mode, DemoCopy.leave, DemoCopy.tryIt, DemoCopy.noneFound,
            DemoCopy.sent, link.sentence, file.sentence, install.sentence, shot.sentence
        ].joined(separator: "\n")
        XCTAssertFalse(copy.contains("Android"))
        XCTAssertFalse(copy.contains("Sony Bravia"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("chinese"))
        XCTAssertFalse(copy.localizedCaseInsensitiveContains("emoji"))
    }
}
