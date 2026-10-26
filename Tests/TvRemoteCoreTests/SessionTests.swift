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
        XCTAssertTrue(message.contains("adb isn't installed"))
        XCTAssertTrue(message.contains("brew install android-platform-tools"))
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
        XCTAssertEqual(fake.calls.first?.arguments, ["connect", "192.0.2.20:5555"])
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
        XCTAssertTrue(status.detail.contains("Accept the debugging prompt"))
    }

    func testPowerSendsWakeKeyWhenConnectedAndMagicPacketWhenNot() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.wolEnabled = true
        settings.macAddress = "aa-bb-cc-dd-ee-ff"
        let fake = FakeRunner()
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: "")),
            .success(CommandResult(status: 0, stdout: "", stderr: ""))
        ]
        let wake = FakeWake()
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            wol: wake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester"
        )
        _ = session.refresh()
        let wakeReport = session.pressPower()
        XCTAssertEqual(wakeReport.title, "Sent wake")
        XCTAssertEqual(fake.calls.last?.arguments, AdbCommands.keyEvent(serial: "192.0.2.20:5555", key: .wakeup))
        XCTAssertTrue(wake.sent.isEmpty)

        let asleep = RemoteSession(settings: settings, runner: FakeRunner(), wol: wake, fileExists: { _ in false })
        let packet = asleep.pressPower()
        XCTAssertEqual(packet.title, "Sent Wake-on-LAN")
        XCTAssertEqual(wake.sent.first?.mac, "aa-bb-cc-dd-ee-ff")
        XCTAssertEqual(wake.sent.first?.host, "255.255.255.255")
        XCTAssertEqual(wake.sent.first?.port, 9)
    }

    func testPowerWithoutMacExplainsStandby() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        let session = RemoteSession(settings: settings, runner: FakeRunner(), fileExists: { _ in true })
        let report = session.pressPower()
        XCTAssertEqual(report.title, "The TV isn't reachable")
        XCTAssertTrue(report.detail.contains("Wake-on-LAN"))
        XCTAssertTrue(report.isError)
    }

    func testSleepRequiresAConnection() {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.wolEnabled = true
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
        XCTAssertEqual(policy.delay(for: .adbMissing(message: "x"), failures: 9), 10)
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
}
