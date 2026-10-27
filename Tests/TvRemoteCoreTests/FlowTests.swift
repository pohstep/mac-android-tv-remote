import XCTest
@testable import TvRemoteCore

final class FlowTests: XCTestCase {
    func testTypingReadinessAndEditMenu() {
        XCTAssertEqual(TypingReadiness.reading("mInputShown=true"), .ready)
        XCTAssertEqual(TypingReadiness.reading("mServedView=null"), .notReady)
        XCTAssertEqual(TypingReadiness.reading("mServedView=com.android.tv/.Search"), .notReady)
        XCTAssertEqual(
            TypingReadiness.reading("mServedView=com.netflix.ninja/.Main\nmInputShown=false"),
            .notReady
        )
        XCTAssertEqual(
            TypingReadiness.reading("mServedView=com.netflix.ninja/.Main\n  mServedView=null"),
            .notReady
        )
        XCTAssertEqual(
            TypingReadiness.reading("mInputShown=true\nmServedView=com.android.tv/.Search"),
            .ready
        )
        XCTAssertEqual(TypingReadiness.reading("mInputShown=false"), .notReady)
        XCTAssertEqual(TypingReadiness.reading("no field here"), .unknown)
        XCTAssertEqual(
            TypingReadiness.notReady,
            "No text field is focused on the TV. Open a search or text box on the TV, then press Retry."
        )
        XCTAssertEqual(TypingReadiness.empty, "Type something to send.")
        XCTAssertTrue(TypingReadiness.showRetry(failed: true))
        XCTAssertFalse(TypingReadiness.showRetry(failed: false))
        XCTAssertTrue(TypingReadiness.showSetup(failed: true, connected: false))
        XCTAssertFalse(TypingReadiness.showSetup(failed: true, connected: true))
        XCTAssertEqual(StandardEditMenu.items.map(\.keyEquivalent), ["x", "c", "v", "a"])
        XCTAssertEqual(StandardEditMenu.items.map(\.action), ["cut:", "copy:", "paste:", "selectAll:"])
        XCTAssertEqual(DroppedText.plain("  https://example.com/a \n"), "https://example.com/a")
        XCTAssertEqual(DroppedText.append("hello", "https://example.com"), "hello https://example.com")
        XCTAssertEqual(DroppedText.append("hello\n", "more"), "hello\nmore")
        XCTAssertEqual(DroppedText.append("", "  hi  "), "hi")
        XCTAssertTrue(DroppedText.isFileDrop(["public.file-url"]))
        XCTAssertFalse(DroppedText.isFileDrop(["public.url", "public.plain-text"]))
    }

    func testScreenshotNameAndStartFolder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 20, minute: 15, second: 3))!
        XCTAssertEqual(
            ScreenshotSave.fileName(at: date, timeZone: TimeZone(secondsFromGMT: 0)!),
            "Zapbar Screenshot 2026-10-27 at 20.15.03.png"
        )
        let desktop = URL(fileURLWithPath: "/Users/tester/Desktop")
        let pictures = URL(fileURLWithPath: "/Users/tester/Pictures")
        XCTAssertEqual(ScreenshotSave.startDirectory(desktop: desktop, pictures: pictures), desktop)
        XCTAssertEqual(ScreenshotSave.startDirectory(desktop: nil, pictures: pictures), pictures)
    }

    func testLoginItemStatusWords() {
        XCTAssertEqual(LoginItemMapping.present(.enabled), LoginItemPresentation(isOn: true, message: "", showsOpenSettings: false))
        let approval = LoginItemMapping.present(.requiresApproval)
        XCTAssertFalse(approval.isOn)
        XCTAssertTrue(approval.showsOpenSettings)
        XCTAssertEqual(approval.message, "macOS needs approval before Zapbar can open at login.")
        let missing = LoginItemMapping.present(.notFound)
        XCTAssertFalse(missing.isOn)
        XCTAssertFalse(missing.showsOpenSettings)
        XCTAssertEqual(missing.message, "Zapbar isn't set to open at login. Turn the switch on again.")
        XCTAssertEqual(LoginItemMapping.present(.notRegistered), LoginItemPresentation(isOn: false, message: "", showsOpenSettings: false))
        let failed = LoginItemMapping.withChangeFailure(LoginItemMapping.present(.enabled))
        XCTAssertTrue(failed.isOn)
        XCTAssertTrue(failed.showsOpenSettings)
        XCTAssertEqual(failed.message, LoginItemMapping.changeFailed)
        XCTAssertTrue(failed.message.contains("Open Login Items"))
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
        transport.readings = Array(repeating: .off, count: 40)
        let clock = FlowClock()
        let failed = PowerActions.turnOn(transport: transport, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(failed.tried, [.adbWake, .sonyOn, .wakeOnLan(port: 9), .wakeOnLan(port: 7)])
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
        off.sonyCanPressPower = true
        off.readings = [.on, .off]
        let slept = PowerActions.turnOff(transport: off, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(slept.tried, [.adbSleep])
        XCTAssertEqual(slept.power, .off)
        XCTAssertEqual(slept.report.title, "Turned off.")
        XCTAssertFalse(slept.report.isError)

        let dropped = ScriptedPower()
        dropped.adbCanPressPower = true
        dropped.sonyCanPressPower = true
        dropped.readings = [.unknown]
        let silent = PowerActions.turnOff(transport: dropped, sleep: clock.sleep, now: clock.now)
        XCTAssertEqual(silent.tried, [.adbSleep])
        XCTAssertEqual(silent.report.title, "Turned off. The TV stopped answering.")
        XCTAssertFalse(silent.report.isError)

        let none = ScriptedPower()
        let missing = PowerActions.turnOn(transport: none, sleep: clock.sleep, now: clock.now)
        XCTAssertTrue(missing.tried.isEmpty)
        XCTAssertTrue(missing.report.detail.contains("Wake-on-LAN"))
        XCTAssertTrue(missing.buttonEnabled)
    }

    func testOnePowerButtonAndPlainWords() {
        let samples: [(PowerReading, Bool, Bool)] = [
            (.on, false, true),
            (.off, false, true),
            (.unknown, false, true),
            (.reachableOnly, false, true),
            (.off, true, true),
            (.unknown, false, false)
        ]
        for sample in samples {
            let button = PowerButtonModel.make(power: sample.0, busy: sample.1, supported: sample.2)
            XCTAssertEqual(button.actions.count, 1, "\(sample)")
        }
        XCTAssertEqual(PowerButtonModel.make(power: .on, busy: false, supported: true).label, "Turn off")
        XCTAssertEqual(PowerButtonModel.make(power: .off, busy: false, supported: true).label, "Turn on")
        let checking = PowerButtonModel.make(power: .unknown, busy: false, supported: true, checking: true)
        XCTAssertEqual(checking.label, "Checking…")
        XCTAssertFalse(checking.enabled)
        let safest = PowerButtonModel.make(power: .unknown, busy: false, supported: true, checking: false)
        XCTAssertEqual(safest.label, "Turn on")
        XCTAssertTrue(safest.enabled)
        XCTAssertEqual(safest.actions.count, 1)
        let unsupported = PowerButtonModel.make(power: .unknown, busy: false, supported: false)
        XCTAssertEqual(unsupported.label, PowerButtonModel.unsupportedLabel)
        XCTAssertFalse(unsupported.enabled)
        XCTAssertEqual(unsupported.actions.count, 1)
        let banned = ["wake", "magic", "packet", "sony", "adb", "wake-on-lan"]
        for line in PowerButtonModel.userFacingLines {
            let lower = line.lowercased()
            for word in banned {
                XCTAssertFalse(lower.contains(word), "\(line) contains \(word)")
            }
        }
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
