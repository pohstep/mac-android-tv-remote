import XCTest
@testable import TvRemoteCore

final class SetupGuideTests: XCTestCase {
    func testSonyControlPathMatchesTheSet() {
        let card = TvSetupGuide.sonyControl
        XCTAssertEqual(card.steps.map(\.label), ["设置", "网络和互联网", "家庭网络", "IP控制", "认证", "预共享密钥"])
        XCTAssertTrue(card.steps[4].value.contains("普通和预共享密钥"))
        XCTAssertTrue(card.steps.allSatisfy { !$0.english.isEmpty })
    }

    func testSonyRemoteStartIsOnByApps() {
        let last = TvSetupGuide.sonyRemoteStart.steps.last
        XCTAssertEqual(last?.label, "远程启动")
        XCTAssertTrue(last?.value.contains("开（通过应用程序开机）") ?? false)
    }

    func testEveryRequiredStepStays() {
        let sony = TvSetupGuide.cards(phase: .sonyKey, brand: .sony, keyboardCapture: true).map(\.key)
        XCTAssertEqual(sony, ["guide.sony.control", "guide.sony.remotestart"])
        let debugging = TvSetupGuide.cards(phase: .debugging, brand: .generic, keyboardCapture: true).map(\.key)
        XCTAssertEqual(debugging, ["guide.android.developer", "guide.android.debugging"])
        XCTAssertEqual(TvSetupGuide.cards(phase: .pair, brand: .generic, keyboardCapture: true).map(\.key), ["guide.android.pair"])
        XCTAssertEqual(TvSetupGuide.cards(phase: .allow, brand: .sony, keyboardCapture: true).map(\.key), ["guide.android.allow"])
        XCTAssertEqual(TvSetupGuide.cards(phase: .done, brand: .sony, keyboardCapture: true).map(\.key), ["guide.mac.accessibility"])
        XCTAssertTrue(TvSetupGuide.cards(phase: .done, brand: .sony, keyboardCapture: false).isEmpty)
    }

    func testSuggestedKeyIsDigitsWithoutLeadingZero() {
        var feed = [0, 0, 4, 8, 2, 0, 1, 3]
        let key = TvSetupGuide.suggestedKey { feed.removeFirst() }
        XCTAssertEqual(key, "482013")
        for _ in 0..<50 {
            let random = TvSetupGuide.suggestedKey()
            XCTAssertEqual(random.count, 6)
            XCTAssertTrue(random.allSatisfy(\.isNumber))
            XCTAssertNotEqual(random.first, "0")
        }
    }

    func testTvSettingsKeyAndCommand() {
        XCTAssertEqual(AndroidKey.settings.rawValue, "KEYCODE_SETTINGS")
        XCTAssertEqual(AndroidKey.settings.code, 176)
        XCTAssertNil(SonyButton.forKey(.settings, isPlaying: false))
        XCTAssertEqual(
            AdbCommands.openSettings(serial: "192.168.1.20:5555"),
            ["-s", "192.168.1.20:5555", "shell", "am", "start", "-a", "android.settings.SETTINGS"]
        )
    }

    func testSonySettingsURIComesFromTheAppList() {
        let body = """
        {"result":[[{"title":"Netflix","uri":"com.sony.dtv.com.netflix.ninja.com.netflix.ninja.MainActivity"},{"title":"设置","uri":"com.sony.dtv.com.android.tv.settings.com.android.tv.settings.MainSettings"}]],"id":60}
        """
        XCTAssertEqual(
            AppIndex.sonySettingsURI(Data(body.utf8)),
            "com.sony.dtv.com.android.tv.settings.com.android.tv.settings.MainSettings"
        )
        XCTAssertNil(AppIndex.sonySettingsURI(Data(#"{"result":[[]]}"#.utf8)))
        XCTAssertFalse(AppIndex.parseSony(Data(body.utf8)).contains { $0.uri?.contains("tv.settings") ?? false })
    }

    func testSetupSentencesStayPlain() {
        for kind in [TvSwitch.sonyNetwork, .networkDebugging] {
            XCTAssertNil(PlainWords.hit(in: SwitchWatch(kind: kind).instruction))
        }
    }
}
