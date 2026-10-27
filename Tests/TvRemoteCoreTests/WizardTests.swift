import XCTest
@testable import TvRemoteCore

final class WizardTests: XCTestCase {
    func testSonySkipsDebuggingUnlessTypingIsWanted() {
        var wizard = SetupWizard()
        XCTAssertEqual(wizard.handle(.choose(.sony)), .none)
        XCTAssertEqual(wizard.phase, .find)
        let tv = DiscoveredTV(name: "Living Room", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, macAddress: "aa:bb:cc:dd:ee:ff", source: "ssdp-scalar", model: "KD-55X80L")
        XCTAssertEqual(wizard.handle(.pick(tv)), .none)
        XCTAssertEqual(wizard.phase, .sonyKey)
        XCTAssertTrue(wizard.lines().contains { $0.key == "setup.sony.ip.1" })
        XCTAssertEqual(wizard.handle(.testKey("")), .none)
        XCTAssertEqual(wizard.message, "Enter the pre-shared key from the TV.")
        XCTAssertEqual(
            wizard.handle(.testKey("secret")),
            .testSony(host: "192.0.2.8", port: 80, psk: "secret")
        )
        XCTAssertEqual(wizard.handle(.testSucceeded), .none)
        XCTAssertEqual(wizard.phase, .sonyTyping)
        XCTAssertEqual(wizard.handle(.typing(false)), .none)
        XCTAssertEqual(wizard.phase, .remember)
        guard case .save(let saved) = wizard.handle(.remember(name: "Living Room")) else {
            return XCTFail("expected save")
        }
        XCTAssertEqual(wizard.phase, .done)
        XCTAssertEqual(saved.brand, .sony)
        XCTAssertEqual(saved.host, "192.0.2.8")
        XCTAssertEqual(saved.controlPort, 80)
        XCTAssertFalse(saved.useDebugging)
        XCTAssertEqual(saved.name, "Living Room")
    }

    func testSonyKeyRefusalStaysOnTheKeyStep() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")))
        _ = wizard.handle(.testKey("nope"))
        XCTAssertEqual(wizard.handle(.testFailed("That key was refused. Check the pre-shared key on the TV.")), .none)
        XCTAssertEqual(wizard.phase, .sonyKey)
        XCTAssertEqual(wizard.message, "That key was refused. Check the pre-shared key on the TV.")
        XCTAssertEqual(wizard.handle(.continueAhead), .none)
        XCTAssertEqual(wizard.phase, .sonyTyping)
    }

    func testSonyTypingAsksForAPairingCode() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, pairingPort: 37111, source: "scan")))
        XCTAssertEqual(wizard.phase, .sonyKey)
        XCTAssertEqual(wizard.handle(.continueAhead), .none)
        XCTAssertEqual(wizard.phase, .sonyTyping)
        XCTAssertEqual(wizard.handle(.typing(true)), .none)
        XCTAssertEqual(wizard.phase, .pair)
        XCTAssertEqual(wizard.handle(.submitPair(port: "12", code: "abc")), .none)
        XCTAssertEqual(wizard.message, "Enter the pairing port and the 6-digit code.")
        let effect = wizard.handle(.submitPair(port: "37111", code: "123456"))
        XCTAssertEqual(effect, .pairAndConnect(host: "192.0.2.8", pairPort: 37111, code: "123456", connectPort: 5555))
        XCTAssertEqual(wizard.handle(.pairSucceeded), .none)
        XCTAssertEqual(wizard.phase, .remember)
        guard case .save(let saved) = wizard.handle(.remember(name: "")) else {
            return XCTFail("expected save")
        }
        XCTAssertTrue(saved.useDebugging)
        XCTAssertEqual(saved.name, "192.0.2.8")
    }

    func testSonyTypingUsesPort5555WhenItIsOpen() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        let tv = DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar", legacyAdbPort: 5555)
        _ = wizard.handle(.pick(tv))
        _ = wizard.handle(.testSucceeded)
        XCTAssertEqual(wizard.handle(.typing(true)), .connectLegacy(host: "192.0.2.8", port: 5555))
        XCTAssertEqual(wizard.phase, .allow)
        XCTAssertTrue(wizard.wantsTyping)
    }

    func testSonyTypingWithoutAHelperStaysOnRemoteKeys() {
        var wizard = SetupWizard()
        wizard.setAdbReady(false)
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")))
        _ = wizard.handle(.continueAhead)
        XCTAssertEqual(wizard.handle(.typing(true)), .none)
        XCTAssertEqual(wizard.phase, .sonyTyping)
        XCTAssertFalse(wizard.wantsTyping)
        XCTAssertEqual(wizard.message, "Typing needs the built-in helper, and this copy does not have it. Remote keys still work.")
    }

    func testSonyWithoutAKnownDebugPortStillShowsTheDebuggingSteps() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, source: "ssdp-scalar")))
        _ = wizard.handle(.continueAhead)
        XCTAssertEqual(wizard.handle(.typing(true)), .none)
        XCTAssertEqual(wizard.phase, .debugging)
        XCTAssertTrue(wizard.lines().contains { $0.key == "setup.sony.typing.1" })
    }

    func testOtherTelevisionOffersWirelessPairingAndPort5555() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.generic))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Other", brand: .generic, host: "192.0.2.10", port: 43210, controlPort: 43210, source: "bonjour")))
        XCTAssertEqual(wizard.phase, .debugging)
        XCTAssertEqual(
            wizard.handle(.chooseLegacy),
            .connectLegacy(host: "192.0.2.10", port: 5555)
        )
        XCTAssertEqual(wizard.phase, .allow)
        XCTAssertEqual(wizard.handle(.allowAccepted), .none)
        XCTAssertEqual(wizard.phase, .remember)

        var wireless = SetupWizard()
        _ = wireless.handle(.choose(.generic))
        _ = wireless.handle(.wantManual)
        XCTAssertEqual(wireless.phase, .manual)
        XCTAssertEqual(wireless.handle(.submitManual(host: "not_a_host", port: nil)), .none)
        XCTAssertEqual(wireless.message, "Enter an IP address or a hostname.")
        XCTAssertEqual(wireless.phase, .manual)
        XCTAssertEqual(wireless.handle(.submitManual(host: "tv.example:5555", port: nil)), .none)
        XCTAssertEqual(wireless.phase, .debugging)
        XCTAssertEqual(wireless.host, "tv.example")
        let effect = wireless.handle(.chooseWireless)
        XCTAssertEqual(effect, .none)
        XCTAssertEqual(
            wireless.handle(.submitPair(port: "40000", code: "654321")),
            .pairAndConnect(host: "tv.example", pairPort: 40000, code: "654321", connectPort: 5555)
        )
    }

    func testXiaomiChecksThenRemembers() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.xiaomi))
        let effect = wizard.handle(.pick(DiscoveredTV(name: "Den", brand: .xiaomi, host: "192.0.2.40", port: 6095, controlPort: 6095, source: "ssdp-xiaomi")))
        XCTAssertEqual(effect, .testXiaomi(host: "192.0.2.40", port: 6095))
        XCTAssertEqual(wizard.phase, .xiaomiCheck)
        XCTAssertEqual(wizard.lines().map(\.key), ["setup.xiaomi.check.1"])
        XCTAssertEqual(wizard.handle(.testSucceeded), .none)
        XCTAssertEqual(wizard.phase, .remember)
        XCTAssertEqual(wizard.lines().map(\.key), ["setup.xiaomi.1"])
        guard case .save(let saved) = wizard.handle(.remember(name: "Den")) else {
            return XCTFail("expected save")
        }
        XCTAssertEqual(saved.brand, .xiaomi)
        XCTAssertEqual(saved.port, 6095)
        XCTAssertFalse(saved.useDebugging)
    }

    func testXiaomiCanBeSavedWhenTheCheckFails() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.xiaomi))
        _ = wizard.handle(.wantManual)
        _ = wizard.handle(.submitManual(host: "192.0.2.40", port: nil))
        XCTAssertEqual(wizard.phase, .xiaomiCheck)
        XCTAssertEqual(wizard.handle(.testFailed("This TV did not answer on port 6095. You can save it and try again later.")), .none)
        XCTAssertEqual(wizard.phase, .xiaomiCheck)
        XCTAssertEqual(wizard.handle(.continueAhead), .none)
        XCTAssertEqual(wizard.phase, .remember)
    }

    func testLegacyDebuggingSkipsTheChoiceScreen() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.generic))
        let effect = wizard.handle(.pick(DiscoveredTV(
            name: "Den",
            brand: .generic,
            host: "192.0.2.10",
            port: 5555,
            controlPort: 5555,
            source: DiscoveryService.legacyAdbType,
            legacyAdbPort: 5555
        )))
        XCTAssertEqual(effect, .connectLegacy(host: "192.0.2.10", port: 5555))
        XCTAssertEqual(wizard.phase, .allow)
    }

    func testPairingAdvertisementOpensTheCodeScreen() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.generic))
        XCTAssertEqual(wizard.handle(.pick(DiscoveredTV(
            name: "Other",
            brand: .generic,
            host: "192.0.2.10",
            port: 43210,
            controlPort: 43210,
            pairingPort: 37111,
            source: DiscoveryService.connectType
        ))), .none)
        XCTAssertEqual(wizard.phase, .pair)
        XCTAssertEqual(wizard.pairingPortHint, 37111)
    }

    func testBackWalksTheStack() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.wantManual)
        XCTAssertEqual(wizard.phase, .manual)
        XCTAssertEqual(wizard.handle(.back), .none)
        XCTAssertEqual(wizard.phase, .find)
        XCTAssertEqual(wizard.handle(.back), .none)
        XCTAssertEqual(wizard.phase, .pickBrand)
        XCTAssertEqual(wizard.handle(.back), .none)
        XCTAssertEqual(wizard.phase, .pickBrand)
    }

    func testSonyConnectCheckReadsPowerAndARefusedKey() {
        let on = #"{"result":[{"status":"active"}],"id":1}"#
        XCTAssertEqual(SonyConnectCheck.verdict(status: 200, body: on), .connected(.on))
        let off = #"{"result":[{"status":"standby"}],"id":1}"#
        XCTAssertEqual(SonyConnectCheck.verdict(status: 200, body: off), .connected(.off))
        XCTAssertEqual(SonyConnectCheck.verdict(status: 403, body: ""), .rejected)
        let forbidden = #"{"error":[403,"Forbidden"],"id":1}"#
        XCTAssertEqual(SonyConnectCheck.verdict(status: 200, body: forbidden), .rejected)
        XCTAssertEqual(SonyConnectCheck.verdict(status: 500, body: on), .unanswered)
        XCTAssertEqual(SonyConnectCheck.verdict(status: 0, body: ""), .unanswered)
    }

    func testSetupCopyDoesNotNameTheForbiddenBrands() {
        let phases: [WizardPhase] = [.pickBrand, .find, .manual, .sonyTyping, .debugging, .pair, .allow, .sonyKey, .xiaomiCheck, .remember, .done]
        let brands: [TvBrand?] = [nil, .sony, .generic, .xiaomi]
        for phase in phases {
            for brand in brands {
                for line in SetupCopy.lines(phase: phase, brand: brand, wantsTyping: true) {
                    XCTAssertFalse(line.text.localizedCaseInsensitiveContains("android"), line.text)
                    XCTAssertFalse(line.text.contains("Sony Bravia"), line.text)
                }
            }
        }
    }

    /// Blocked product names are assembled in scripts/check-copy.sh.
    func testSourcesOmitBlockedNames() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/check-copy.sh").path
        let result = try ShellRunner().run("/bin/sh", arguments: [script], timeout: 30)
        XCTAssertEqual(result.status, 0, result.stdout + result.stderr)
    }

    func testCopyScriptSkipsBuiltBundles() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = "land" + "Sca" + "pe"
        let files = [
            root.appendingPathComponent("out/note.txt"),
            root.appendingPathComponent("Fixture.app/Contents/Resources/Licenses/adb-NOTICE.txt"),
            root.appendingPathComponent("Licenses/adb-NOTICE.txt")
        ]
        let hit = root.appendingPathComponent("zapbar-copy-probe.txt")
        defer {
            try? FileManager.default.removeItem(at: root.appendingPathComponent("out"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("Fixture.app"))
            try? FileManager.default.removeItem(at: root.appendingPathComponent("Licenses"))
            try? FileManager.default.removeItem(at: hit)
        }
        for url in files {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try probe.write(to: url, atomically: true, encoding: .utf8)
        }
        let script = root.appendingPathComponent("scripts/check-copy.sh").path
        let skipped = try ShellRunner().run("/bin/sh", arguments: [script], timeout: 30)
        XCTAssertEqual(skipped.status, 0, skipped.stdout + skipped.stderr)

        try probe.write(to: hit, atomically: true, encoding: .utf8)
        let caught = try ShellRunner().run("/bin/sh", arguments: [script], timeout: 30)
        XCTAssertNotEqual(caught.status, 0)
        XCTAssertTrue(caught.stdout.contains("zapbar-copy-probe.txt"), caught.stdout)
    }
}
