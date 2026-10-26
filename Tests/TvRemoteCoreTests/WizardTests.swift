import XCTest
@testable import TvRemoteCore

final class WizardTests: XCTestCase {
    func testSonySkipsDebuggingUnlessTypingIsWanted() {
        var wizard = SetupWizard()
        XCTAssertEqual(wizard.handle(.choose(.sony)), .none)
        XCTAssertEqual(wizard.phase, .find)
        let tv = DiscoveredTV(name: "Living Room", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, macAddress: "aa:bb:cc:dd:ee:ff", source: "sony-scan")
        XCTAssertEqual(wizard.handle(.pick(tv)), .none)
        XCTAssertEqual(wizard.phase, .sonyTyping)
        XCTAssertEqual(wizard.handle(.typing(false)), .none)
        XCTAssertEqual(wizard.phase, .sonyKey)
        XCTAssertEqual(wizard.handle(.continueAhead), .none)
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

    func testSonyTypingAsksForAPairingCode() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.sony))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Set", brand: .sony, host: "192.0.2.8", port: 5555, controlPort: 80, pairingPort: 37111, source: "scan")))
        XCTAssertEqual(wizard.handle(.typing(true)), .none)
        XCTAssertEqual(wizard.phase, .debugging)
        XCTAssertTrue(wizard.lines().contains { $0.key == "setup.sony.typing.1" })
        XCTAssertEqual(wizard.handle(.chooseWireless), .none)
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

    func testXiaomiGoesStraightToRemember() {
        var wizard = SetupWizard()
        _ = wizard.handle(.choose(.xiaomi))
        _ = wizard.handle(.pick(DiscoveredTV(name: "Den", brand: .xiaomi, host: "192.0.2.40", port: 6095, controlPort: 6095, source: "xiaomi-scan")))
        XCTAssertEqual(wizard.phase, .remember)
        XCTAssertEqual(wizard.lines().map(\.key), ["setup.xiaomi.1"])
        guard case .save(let saved) = wizard.handle(.remember(name: "Den")) else {
            return XCTFail("expected save")
        }
        XCTAssertEqual(saved.brand, .xiaomi)
        XCTAssertEqual(saved.port, 6095)
        XCTAssertFalse(saved.useDebugging)
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

    func testSetupCopyDoesNotNameTheForbiddenBrands() {
        let phases: [WizardPhase] = [.pickBrand, .find, .manual, .sonyTyping, .debugging, .pair, .allow, .sonyKey, .remember, .done]
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
}
