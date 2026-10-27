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

    func testPowerPollIsBetweenThreeAndFiveSeconds() {
        XCTAssertGreaterThanOrEqual(RefreshCadence.whileOpen, 3)
        XCTAssertLessThanOrEqual(RefreshCadence.whileOpen, 5)
    }

    func testAsleepConnectionIsNotShownAsOn() {
        XCTAssertEqual(PowerMerge.choose(adbDump: "mWakefulness=Asleep", sony: .on), .off)
        XCTAssertEqual(PowerMerge.choose(adbDump: "mWakefulness=Dozing", sony: nil), .off)
        XCTAssertEqual(PowerMerge.choose(adbDump: "mWakefulness=Awake", sony: .off), .on)
        XCTAssertEqual(PowerMerge.choose(adbDump: nil, sony: .on), .on)
        XCTAssertEqual(PowerMerge.choose(adbDump: nil, sony: .off), .off)
        XCTAssertEqual(PowerMerge.choose(adbDump: "no wake line", sony: .reachableOnly), .unknown)
        XCTAssertEqual(PowerMerge.choose(adbDump: nil, sony: nil), .unknown)
        XCTAssertFalse(PowerChrome.showsOn(.off))
        XCTAssertFalse(PowerChrome.showsOn(.unknown))
        XCTAssertFalse(PowerChrome.showsOn(.reachableOnly))
        XCTAssertTrue(PowerChrome.showsOn(.on))
        XCTAssertEqual(MacSources.subnetBroadcast(host: "192.168.50.57", configured: "255.255.255.255"), "192.168.50.255")
        XCTAssertEqual(MacSources.addressFile("aa:bb:cc:dd:ee:ff\n"), "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(
            MacSources.neighbour("? (192.168.50.57) at aa:bb:cc:dd:ee:ff on en0", host: "192.168.50.57"),
            "AA:BB:CC:DD:EE:FF"
        )
    }

    func testTurnOnFallsThroughOnceThenRecoversTheButton() {
        let transport = ScriptedPower()
        transport.adbCanPressPower = true
        transport.sonyCanPressPower = true
        transport.canWakeOnLan = true
        transport.readings = Array(repeating: .off, count: 20)
        let clock = FlowClock()
        let failed = PowerActions.turnOn(transport: transport, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(failed.tried, [.adbWake, .sonyOn])
        XCTAssertEqual(failed.report.title, PowerActions.didNotRespond)
        XCTAssertTrue(failed.report.isError)
        XCTAssertTrue(failed.buttonEnabled)
        XCTAssertEqual(failed.power, .off)

        let waking = ScriptedPower()
        waking.adbCanPressPower = true
        waking.sonyCanPressPower = true
        waking.readings = [.off, .on]
        let woke = PowerActions.turnOn(transport: waking, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(woke.tried, [.adbWake])
        XCTAssertEqual(woke.power, .on)
        XCTAssertFalse(woke.report.isError)

        let second = ScriptedPower()
        second.adbCanPressPower = true
        second.sonyCanPressPower = true
        second.readings = Array(repeating: .off, count: 8) + [.on]
        let recovered = PowerActions.turnOn(transport: second, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(recovered.tried, [.adbWake, .sonyOn])
        XCTAssertEqual(recovered.power, .on)

        let off = ScriptedPower()
        off.adbCanPressPower = true
        off.readings = [.on, .off]
        let slept = PowerActions.turnOff(transport: off, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(slept.tried, [.adbSleep])
        XCTAssertEqual(slept.power, .off)
        XCTAssertFalse(slept.report.isError)

        let none = ScriptedPower()
        let missing = PowerActions.turnOn(transport: none, sleep: clock.sleep, now: clock.now)
        XCTAssertTrue(missing.tried.isEmpty)
        XCTAssertTrue(missing.report.detail.contains("Wake-on-LAN"))
        XCTAssertTrue(missing.buttonEnabled)
    }

    func testConnectedAsleepPictureIsOff() {
        let fake = FakeRunner()
        fake.handler = { arguments in
            if arguments.contains("connect") {
                return .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: ""))
            }
            if arguments.contains("devices") {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("dumpsys") && arguments.contains("power") {
                return .success(CommandResult(status: 0, stdout: "mWakefulness=Asleep", stderr: ""))
            }
            if arguments.contains("dumpsys") && arguments.contains("window") {
                return .success(CommandResult(status: 0, stdout: "mCurrentFocus=Window{aa u0 com.netflix.ninja/.Main}", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        _ = session.refresh()
        let picture = session.refreshPicture()
        XCTAssertEqual(picture.power, .off)
        XCTAssertFalse(PowerChrome.showsOn(picture.power))
        XCTAssertEqual(picture.foregroundPackage, "com.netflix.ninja")
    }
}

private final class FlowClock {
    var stamp = Date(timeIntervalSince1970: 1_700_000_000)
    func now() -> Date { stamp }
    func sleep(_ interval: TimeInterval) { stamp = stamp.addingTimeInterval(interval) }
}

private final class ScriptedPower: PowerTransport {
    var adbCanPressPower = false
    var sonyCanPressPower = false
    var canWakeOnLan = false
    var readings: [PowerReading] = [.unknown]
    var ran: [PowerStep] = []

    func readPower() -> PowerReading {
        if readings.isEmpty { return .unknown }
        return readings.removeFirst()
    }

    func run(_ step: PowerStep) -> Bool {
        ran.append(step)
        return true
    }
}
