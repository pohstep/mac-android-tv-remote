import XCTest
@testable import TvRemoteCore

final class PanelLayoutTests: XCTestCase {
    func testHeightFollowsContentUntilTheScreen() {
        XCTAssertEqual(PanelLayout.width, 376)
        XCTAssertEqual(PanelLayout.height(content: 820, visibleScreen: 1000), 820)
        XCTAssertEqual(PanelLayout.height(content: 1100, visibleScreen: 900), 888)
        XCTAssertEqual(PanelLayout.height(content: 40, visibleScreen: 1000), 200)
    }

    func testTryDemoStaysOnTheFindStepAndInSettings() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let wizard = try String(contentsOf: root.appendingPathComponent("macos/PohstepRemote/SetupWizardView.swift"), encoding: .utf8)
        let settings = try String(contentsOf: root.appendingPathComponent("macos/PohstepRemote/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(wizard.contains("DemoOffer.showWhenNoneFound"))
        XCTAssertTrue(wizard.contains("DemoCopy.tryIt"))
        XCTAssertTrue(settings.contains("DemoCopy.tryIt"))
    }
}
