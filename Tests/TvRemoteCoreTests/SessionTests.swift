import XCTest
@testable import TvRemoteCore

final class FakeRunner: CommandRunning {
    struct Call: Equatable {
        var executable: String
        var arguments: [String]
        var environment: [String: String] = [:]
        var timeout: TimeInterval = 0
    }

    var calls: [Call] = []
    var script: [Result<CommandResult, Error>] = []
    var handler: (([String]) -> Result<CommandResult, Error>)?
    var cancelCount = 0

    func cancel() {
        cancelCount += 1
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) throws -> CommandResult {
        try run(executable, arguments: arguments, timeout: timeout, environment: [:])
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments, environment: environment, timeout: timeout))
        if let handler {
            return try handler(arguments).get()
        }
        if script.isEmpty {
            return CommandResult(status: 0, stdout: "", stderr: "")
        }
        return try script.removeFirst().get()
    }
}

final class FakeWake: WakeOnLanSending {
    var sent: [(mac: String, host: String, port: UInt16)] = []
    var error: Error?

    func send(mac: String, broadcastHost: String, port: UInt16) throws {
        if let error { throw error }
        sent.append((mac, broadcastHost, port))
    }
}

final class SessionTests: XCTestCase {
    func testRefreshReportsAdbMissingWithHomebrewHint() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        let session = RemoteSession(
            settings: settings,
            runner: FakeRunner(),
            fileExists: { _ in false },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        let status = session.refresh()
        guard case .adbMissing(let message) = status else {
            return XCTFail("expected adb missing, got \(status)")
        }
        XCTAssertEqual(message, Copy.helperMissing)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("homebrew"))
        XCTAssertFalse(message.contains("android-platform-tools"))
    }

    func testRefreshReportsRefusal() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        let fake = FakeRunner()
        fake.script = [
            .success(CommandResult(status: 1, stdout: "", stderr: "cannot connect to 192.0.2.20:5555: Connection refused")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        let status = session.refresh()
        guard case .refused(let serial, let detail) = status else {
            return XCTFail("expected refused, got \(status)")
        }
        XCTAssertEqual(serial, "192.0.2.20:5555")
        XCTAssertTrue(detail.contains("refused"))
        XCTAssertTrue(detail.contains("192.0.2.20:5555"))
        XCTAssertEqual(fake.calls.first?.arguments, ["-P", "5037", "connect", "192.0.2.20:5555"])
    }

    func testRefreshReportsUnreachableWhenTheConnectIsNotARefusal() {
        let blocked = [
            "failed to connect to 192.0.2.20:5555: Operation timed out",
            "cannot connect to 192.0.2.20:5555: No route to host",
            "cannot connect to 192.0.2.20:5555"
        ]
        for stderr in blocked {
            let status = refresh(stderr: stderr)
            guard case .unreachable(let serial) = status else {
                return XCTFail("expected unreachable for \(stderr), got \(status)")
            }
            XCTAssertEqual(serial, "192.0.2.20:5555")
            XCTAssertEqual(status.title, "Couldn't reach the TV")
            XCTAssertEqual(status.detail, Copy.unreachable(serial: serial))
            XCTAssertFalse(status.detail.localizedCaseInsensitiveContains("refused"))
            XCTAssertFalse(status.detail.contains("Local Network"))
        }

        let timedOut = refresh(error: RemoteError.timedOut("/usr/local/bin/adb"))
        guard case .unreachable(let serial) = timedOut else {
            return XCTFail("expected unreachable for a timeout, got \(timedOut)")
        }
        XCTAssertEqual(timedOut.detail, Copy.unreachable(serial: serial))
    }

    func testRefreshReportsHelperDownWhenTheDaemonDoesNotStart() {
        let outputs = [
            "cannot start server on remote host\nfailed to connect to 127.0.0.1:5038",
            "cannot connect to daemon",
            "cannot start server on remote host: Connection refused"
        ]
        for stderr in outputs {
            let status = refresh(stderr: stderr)
            guard case .helperDown = status else {
                return XCTFail("expected helper down for \(stderr), got \(status)")
            }
            XCTAssertEqual(status.detail, Copy.helperDidNotStart)
            XCTAssertEqual(status.detail, "Zapbar's helper couldn't start. Quit and reopen Zapbar.")
            XCTAssertEqual(status.title, "Helper didn't start")
            XCTAssertNotEqual(status.title, "The TV refused the connection")
            XCTAssertFalse(status.detail.localizedCaseInsensitiveContains("refused"))
            XCTAssertNotEqual(status, .unreachable(serial: "192.0.2.20:5555"))
        }

        let thrown = refresh(error: RemoteError.commandFailed("cannot connect to daemon"))
        guard case .helperDown = thrown else {
            return XCTFail("expected helper down for a thrown daemon error, got \(thrown)")
        }
        XCTAssertEqual(thrown.detail, Copy.helperDidNotStart)
    }

    private func refresh(stderr: String) -> LinkStatus {
        refresh(connect: .success(CommandResult(status: 1, stdout: "", stderr: stderr)))
    }

    private func refresh(error: Error) -> LinkStatus {
        refresh(connect: .failure(error))
    }

    private func refresh(connect: Result<CommandResult, Error>) -> LinkStatus {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        let fake = FakeRunner()
        fake.script = [
            connect,
            .success(CommandResult(status: 0, stdout: "List of devices attached\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        return session.refresh()
    }

    func testAllowWaitPollsATelevisionThatAuthorizesItself() {
        let fake = allowRunner(states: ["device"])
        let session = allowSession(fake)
        var slept: [TimeInterval] = []
        let status = session.reconnectUntilAuthorized(sleep: { slept.append($0) }, now: { Date(timeIntervalSince1970: 0) })
        guard case .connected(let serial) = status else {
            return XCTFail("expected a connection, got \(status)")
        }
        XCTAssertEqual(serial, "192.0.2.20:5555")
        XCTAssertTrue(slept.isEmpty)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("disconnect") })
    }

    func testAllowWaitDisconnectsAndConnectsUntilAuthorized() {
        let fake = allowRunner(states: ["unauthorized", "unauthorized", "device"])
        let session = allowSession(fake)
        var clock = Date(timeIntervalSince1970: 0)
        var slept: [TimeInterval] = []
        let status = session.reconnectUntilAuthorized(
            timeout: AllowReconnect.timeout,
            interval: AllowReconnect.interval,
            sleep: { amount in
                slept.append(amount)
                clock = clock.addingTimeInterval(amount)
            },
            now: { clock }
        )
        guard case .connected = status else {
            return XCTFail("expected a connection after reconnect, got \(status)")
        }
        XCTAssertEqual(slept, [AllowReconnect.interval])
        let serialCalls = fake.calls.map(\.arguments)
        XCTAssertEqual(
            serialCalls.filter { $0.contains("disconnect") },
            [["-P", "5037", "disconnect", "192.0.2.20:5555"]]
        )
        XCTAssertEqual(
            serialCalls.filter { $0.contains("connect") },
            [["-P", "5037", "connect", "192.0.2.20:5555"]]
        )
    }

    func testAllowWaitStopsAtTheCommandTimeout() {
        let fake = allowRunner(states: Array(repeating: "unauthorized", count: 20))
        let session = allowSession(fake)
        var clock = Date(timeIntervalSince1970: 0)
        var slept: [TimeInterval] = []
        let status = session.reconnectUntilAuthorized(
            timeout: 9,
            interval: 3,
            sleep: { amount in
                slept.append(amount)
                clock = clock.addingTimeInterval(amount)
            },
            now: { clock }
        )
        guard case .unauthorized(let serial) = status else {
            return XCTFail("expected to stay unauthorized, got \(status)")
        }
        XCTAssertEqual(serial, "192.0.2.20:5555")
        XCTAssertEqual(slept, [3, 3, 3])
        XCTAssertEqual(fake.calls.filter { $0.arguments.contains("disconnect") }.count, 3)
        XCTAssertEqual(AllowReconnect.timeout, 12)
        XCTAssertEqual(AllowReconnect.interval, 3)
    }

    func testRefreshReportsUnauthorized() {
        var settings = Settings.factoryDefaults()
        settings.host = "tv.tailnet.ts.net"
        let fake = FakeRunner()
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to tv.tailnet.ts.net:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\ntv.tailnet.ts.net:5555\tunauthorized\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        let status = session.refresh()
        guard case .unauthorized(let serial) = status else {
            return XCTFail("expected unauthorized, got \(status)")
        }
        XCTAssertEqual(serial, "tv.tailnet.ts.net:5555")
        XCTAssertTrue(status.detail.contains("isn't allowed yet"))
    }

    func testPowerSendsWakeKeyWhenConnectedAndMagicPacketWhenNot() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.macAddress = "aa-bb-cc-dd-ee-ff"
        let fake = FakeRunner()
        fake.handler = { arguments in
            if arguments.contains("connect") {
                return .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: ""))
            }
            if arguments.contains("devices") {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("dumpsys") && arguments.contains("power") {
                return .success(CommandResult(status: 0, stdout: "mWakefulness=Awake", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let wake = FakeWake()
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            wol: wake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        _ = session.refresh()
        armFastPower(session)
        let wakeReport = session.pressPower()
        XCTAssertEqual(wakeReport.title, "Turned on.")
        XCTAssertEqual(wakeReport.detail, "adb wake")
        XCTAssertTrue(fake.calls.contains { $0.arguments.contains("KEYCODE_WAKEUP") })
        XCTAssertTrue(wake.sent.isEmpty)

        let asleep = RemoteSession(settings: settings, runner: FakeRunner(), wol: wake, fileExists: { _ in false })
        XCTAssertTrue(asleep.canWakeOnLan)
        armFastPower(asleep)
        let packet = asleep.pressPower()
        XCTAssertEqual(packet.title, PowerActions.didNotRespond)
        XCTAssertTrue(packet.isError)
        XCTAssertTrue(wake.sent.contains { $0.mac == "aa-bb-cc-dd-ee-ff" && $0.host == "192.0.2.255" && $0.port == 9 })
        XCTAssertTrue(wake.sent.contains { $0.host == "192.0.2.20" && $0.port == 7 })
    }

    func testPowerWithoutMacExplainsStandby() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        let session = RemoteSession(settings: settings, runner: FakeRunner(), fileExists: { _ in true })
        XCTAssertFalse(session.canWakeOnLan)
        let report = session.pressPower()
        XCTAssertEqual(report.title, "The TV isn't reachable")
        XCTAssertTrue(report.detail.contains("Wake-on-LAN"))
        XCTAssertTrue(report.isError)
    }

    func testSleepRequiresAConnection() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.macAddress = "aa:bb:cc:dd:ee:ff"
        let session = RemoteSession(settings: settings, runner: FakeRunner(), fileExists: { _ in false })
        let report = session.pressSleep()
        XCTAssertTrue(report.isError)
        XCTAssertTrue(report.detail.contains("Sleep needs a live adb connection"))
    }

    func testLaunchDoesNotCallAdbForABadPackage() {
        let fake = FakeRunner()
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        session.replaceSettings(settings)
        // Force a connected status through a scripted refresh.
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
        ]
        _ = session.refresh()
        let before = fake.calls.count
        let report = session.launch(TvApp(id: "x", name: "Nope", packageName: "not a package"))
        XCTAssertTrue(report.isError)
        XCTAssertEqual(fake.calls.count, before)
    }

    func testReconnectBackoff() {
        let policy = ReconnectPolicy()
        XCTAssertEqual(policy.delay(for: .connected(serial: "a:5555"), failures: 4), 15)
        XCTAssertEqual(policy.delay(for: .refused(serial: "a:5555", detail: "no"), failures: 0), 5)
        XCTAssertEqual(policy.delay(for: .refused(serial: "a:5555", detail: "no"), failures: 1), 10)
        XCTAssertEqual(policy.delay(for: .refused(serial: "a:5555", detail: "no"), failures: 3), 30)
        XCTAssertEqual(policy.delay(for: .unreachable(serial: "a:5555"), failures: 0), 5)
        XCTAssertEqual(policy.delay(for: .adbMissing(message: "x"), failures: 9), 10)
    }

    func testUnreachableCopy() {
        let serial = "192.0.2.8:5555"
        XCTAssertEqual(
            Copy.unreachable(serial: serial),
            "Couldn't reach the TV at \(serial). Check that it is on and on the same network, then try again."
        )
        XCTAssertFalse(Copy.unreachable(serial: serial).contains("Local Network"))
        XCTAssertFalse(Copy.unreachable(serial: serial).localizedCaseInsensitiveContains("android"))
    }

    func testDefaultApps() {
        let names = TvApp.defaults.map(\.packageName)
        XCTAssertEqual(names, [
            "org.smarttube.stable",
            "com.netflix.ninja",
            "com.disney.disneyplus",
            "org.videolan.vlc",
            "com.spotify.tv.android",
            "com.phlox.tvwebbrowser"
        ])
    }

    private func allowSession(_ fake: FakeRunner) -> RemoteSession {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        return RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
    }

    private func allowRunner(states: [String]) -> FakeRunner {
        let fake = FakeRunner()
        let script = DeviceScript(states)
        fake.handler = { arguments in
            if arguments.contains("disconnect") {
                return .success(CommandResult(status: 0, stdout: "disconnected 192.0.2.20:5555", stderr: ""))
            }
            if arguments.contains("connect") {
                return .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: ""))
            }
            if arguments.contains("devices") {
                let state = script.next()
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\t\(state)\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        return fake
    }

    func testTypeStopsWhenNoFieldIsReady() {
        let fake = FakeRunner()
        let session = connected(fake)
        fake.handler = { arguments in
            if arguments.contains("dumpsys") && arguments.contains("input_method") {
                return .success(CommandResult(status: 0, stdout: "mServedView=null\nmInputShown=false", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let report = session.type("hello")
        XCTAssertEqual(report.detail, TypingReadiness.notReady)
        XCTAssertTrue(report.isError)
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("text") && $0.arguments.contains("input") })
    }

    func testSonyRouteRefusesAHiddenKeyboard() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.brand = .sony
        let fake = FakeRunner()
        let http = ScriptedHTTP()
        fake.handler = { arguments in
            if arguments.contains("connect") {
                return .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: ""))
            }
            if arguments.contains("devices") {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("input_method") {
                return .success(CommandResult(status: 0, stdout: "mServedView=com.netflix.ninja/.Main\nmInputShown=false", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            http: http,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        session.setPreSharedKey("secret")
        _ = session.refresh()
        let report = session.type("你好")
        XCTAssertEqual(report.detail, TypingReadiness.notReady)
        XCTAssertTrue(http.calls.isEmpty)
    }

    func testUrlIsTypedAsPlainText() {
        let fake = FakeRunner()
        let session = connected(fake)
        fake.handler = { arguments in
            if arguments.contains("dumpsys") && arguments.contains("input_method") {
                return .success(CommandResult(status: 0, stdout: "mInputShown=true", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let report = session.type("https://example.com/watch")
        XCTAssertFalse(report.isError)
        XCTAssertTrue(fake.calls.contains { $0.arguments.contains("input") && $0.arguments.contains("text") })
        XCTAssertFalse(fake.calls.contains { $0.arguments.contains("android.intent.action.VIEW") })
    }

    private func connected(_ fake: FakeRunner) -> RemoteSession {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        _ = session.refresh()
        fake.script = []
        return session
    }
}

private final class PowerClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)
}

func armFastPower(_ session: RemoteSession) {
    let clock = PowerClock()
    session.powerNow = { clock.now }
    session.powerSleep = { interval in clock.now = clock.now.addingTimeInterval(interval) }
}

private final class DeviceScript {
    private var states: [String]
    init(_ states: [String]) { self.states = states }
    func next() -> String {
        guard !states.isEmpty else { return "unauthorized" }
        return states.removeFirst()
    }
}
