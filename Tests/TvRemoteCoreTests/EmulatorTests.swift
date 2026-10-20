import XCTest
@testable import TvRemoteCore

/// Talks only to an Android TV emulator. A serial that is not `emulator-*`
/// or `127.0.0.1` is refused, so this never drives a real television.
final class EmulatorTests: XCTestCase {
    private var adb: String = ""
    private var serial: String = ""

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["POHSTEP_EMULATOR"] == "1")
        let runner = ShellRunner()
        adb = try XCTUnwrap(resolveAdb(runner: runner))
        let listed = try runner.run(adb, arguments: ["devices"], timeout: 15)
        serial = try XCTUnwrap(firstEmulator(in: listed.stdout))
        try assertNoForeignDevices(listed.stdout)
        try disableInputMethods(runner)
    }

    func testKeyeventsTextAndAppLaunchOnTheEmulator() throws {
        let runner = ShellRunner()
        let client = AdbClient(runner: runner, adbPath: adb, timeout: 45)
        try installProbe(runner: runner)

        try shell(runner, ["am", "force-stop", "app.pohstep.inputprobe"])
        _ = try shell(runner, ["logcat", "-c"])
        let started = try shell(
            runner,
            ["am", "start", "-n", "app.pohstep.inputprobe/.ProbeActivity"]
        )
        XCTAssertFalse(AdbOutput.outputIndicatesFailure(started, status: 0), started)
        try waitUntilProbeFocused(runner)

        try client.inputText("hello world", serial: serial)
        XCTAssertTrue(waitForLog(runner, needle: "TEXT=hello world"), logSnippet(runner))

        try shell(runner, ["am", "force-stop", "app.pohstep.inputprobe"])
        _ = try shell(runner, ["logcat", "-c"])
        _ = try shell(runner, ["am", "start", "-n", "app.pohstep.inputprobe/.ProbeActivity"])
        try waitUntilProbeFocused(runner)
        try client.inputText("it's 100%", serial: serial)
        XCTAssertTrue(waitForLog(runner, needle: "TEXT=it's 100%"), logSnippet(runner))

        _ = try shell(runner, ["logcat", "-c"])
        Thread.sleep(forTimeInterval: 1.0)
        let keys: [AndroidKey] = [.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .dpadCenter, .mediaPlayPause, .volumeMute, .wakeup]
        for key in keys {
            try client.keyEvent(key, serial: serial)
        }
        Thread.sleep(forTimeInterval: 2.0)
        let log = logSnippet(runner)
        for key in [AndroidKey.dpadUp, .dpadDown, .dpadLeft, .dpadRight, .dpadCenter] {
            XCTAssertTrue(log.contains("KEY=\(key.code)"), "missing \(key.rawValue) in\n\(log)")
        }
        let systemLog = try shell(runner, ["logcat", "-d", "-t", "500"])
        let playSeen = log.contains("KEY=\(AndroidKey.mediaPlayPause.code)")
            || systemLog.contains(AndroidKey.mediaPlayPause.rawValue)
            || systemLog.contains("keyCode=\(AndroidKey.mediaPlayPause.code)")
        XCTAssertTrue(playSeen, "missing play/pause in\n\(log)")
        let muteSeen = log.contains("KEY=\(AndroidKey.volumeMute.code)")
            || systemLog.contains("mute_changed")
            || systemLog.contains("STREAM_MUTE")
            || systemLog.contains(AndroidKey.volumeMute.rawValue)
        XCTAssertTrue(muteSeen, "missing mute in probe or logcat")

        // Wake is consumed by the power manager, so the probe usually never sees it.
        // Sleep, then send WAKEUP, and read the result.
        _ = try shell(runner, ["svc", "power", "stayon", "false"])
        _ = try shell(runner, ["input", "keyevent", AndroidKey.sleep.rawValue])
        Thread.sleep(forTimeInterval: 1.5)
        let asleep = try shell(runner, ["dumpsys", "power"])
        XCTAssertTrue(
            asleep.contains("mWakefulness=Asleep") || asleep.contains("mWakefulness=Dozing"),
            "sleep keyevent left the display awake"
        )
        _ = try shell(runner, ["input", "keyevent", AndroidKey.wakeup.rawValue])
        Thread.sleep(forTimeInterval: 1.5)
        let awake = try shell(runner, ["dumpsys", "power"])
        _ = try? shell(runner, ["svc", "power", "stayon", "true"])
        XCTAssertTrue(awake.contains("mWakefulness=Awake"), "wakeup keyevent did not wake the display")

        let package = try launchablePackage(runner)
        try client.launchApp(packageName: package, serial: serial)
        Thread.sleep(forTimeInterval: 3.0)
        let focus = try shell(runner, ["dumpsys", "window"])
        XCTAssertTrue(focus.contains(package), "foreground did not become \(package):\n\(focus.suffix(800))")
    }

    func testSessionConnectsToTheEmulatorLocalhostPortOnly() throws {
        let runner = ShellRunner()
        _ = try runner.run(adb, arguments: ["-s", serial, "tcpip", "5555"], timeout: 15)
        Thread.sleep(forTimeInterval: 1.0)
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.port = 5555
        let session = RemoteSession(
            settings: settings,
            runner: runner,
            fileExists: { $0 == self.adb },
            pathEnvironment: "",
            homeDirectory: "/tmp"
        )
        // The locator only sees the explicit adb path when it is one of the candidates
        // or on PATH. Point the setting at the binary we already resolved.
        settings.adbPath = adb
        session.replaceSettings(settings)
        let status = session.refresh()
        guard case .connected(let connected) = status else {
            return XCTFail("expected the emulator at 127.0.0.1:5555, got \(status.title): \(status.detail)")
        }
        XCTAssertEqual(connected, "127.0.0.1:5555")
        let report = session.press(.dpadCenter)
        XCTAssertFalse(report.isError, report.detail)
        _ = try runner.run(adb, arguments: ["disconnect", "127.0.0.1:5555"], timeout: 10)
    }

    func testConnectionRefusedOnAClosedLocalPort() throws {
        let runner = ShellRunner()
        var settings = Settings.factoryDefaults()
        settings.host = "127.0.0.1"
        settings.port = 1
        settings.adbPath = adb
        let session = RemoteSession(settings: settings, runner: runner, homeDirectory: "/tmp")
        let status = session.refresh()
        guard case .refused(let serial, let detail) = status else {
            return XCTFail("expected refusal from 127.0.0.1:1, got \(status.title): \(status.detail)")
        }
        XCTAssertEqual(serial, "127.0.0.1:1")
        XCTAssertTrue(detail.contains("refused"))
        XCTAssertTrue(detail.contains("brew install android-platform-tools") == false)
    }

    private func resolveAdb(runner: ShellRunner) -> String? {
        if let override = ProcessInfo.processInfo.environment["POHSTEP_ADB"], FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let home = NSHomeDirectory()
        let candidates = [
            home + "/android-sdk/platform-tools/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func firstEmulator(in listing: String) -> String? {
        for raw in listing.split(whereSeparator: \.isNewline) {
            let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            if parts.count >= 2, parts[0].hasPrefix("emulator-"), parts[1] == "device" {
                return parts[0]
            }
        }
        return nil
    }

    private func assertNoForeignDevices(_ listing: String) throws {
        for raw in listing.split(whereSeparator: \.isNewline) {
            let parts = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2, parts[1] == "device" || parts[1] == "unauthorized" else { continue }
            let name = parts[0]
            let safe = name.hasPrefix("emulator-") || name.hasPrefix("127.0.0.1:")
            try XCTSkipUnless(safe, "Refusing to run while \(name) is attached")
        }
    }

    private func installProbe(runner: ShellRunner) throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = root.appendingPathComponent("emulator/build-probe.sh").path
        let built = try runner.run("/bin/bash", arguments: [script], timeout: 120)
        XCTAssertEqual(built.status, 0, built.combined)
        let apk = root.appendingPathComponent("emulator/input-probe/build/probe.apk").path
        let installed = try runner.run(adb, arguments: ["-s", serial, "install", "-r", "-t", apk], timeout: 60)
        XCTAssertEqual(installed.status, 0, installed.combined)
    }

    @discardableResult
    private func shell(_ runner: ShellRunner, _ arguments: [String]) throws -> String {
        let result = try runner.run(adb, arguments: ["-s", serial] + ["shell"] + arguments, timeout: 45)
        return result.combined
    }

    private func waitUntilProbeFocused(_ runner: ShellRunner) throws {
        let deadline = Date().addingTimeInterval(25)
        var last = ""
        while Date() < deadline {
            last = try shell(runner, ["dumpsys", "window"])
            let focused = last.split(whereSeparator: \.isNewline).contains { line in
                line.contains("mCurrentFocus=") && line.contains("inputprobe")
            }
            if focused {
                return
            }
            Thread.sleep(forTimeInterval: 0.6)
        }
        XCTFail("Input probe never took focus:\n\(last.suffix(500))")
    }

    /// The Android TV image's Latin IME rewrites injected text. Hardware keys
    /// land in the field once that IME is out of the way.
    private func disableInputMethods(_ runner: ShellRunner) throws {
        let listed = try shell(runner, ["ime", "list", "-s"])
        for raw in listed.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.contains("/") else { continue }
            _ = try? shell(runner, ["ime", "disable", line])
        }
    }

    private func waitForLog(_ runner: ShellRunner, needle: String) -> Bool {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if logSnippet(runner).contains(needle) { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return false
    }

    private func logSnippet(_ runner: ShellRunner) -> String {
        let result = try? runner.run(adb, arguments: ["-s", serial, "logcat", "-d", "-s", "InputProbe:I"], timeout: 25)
        return result?.combined ?? ""
    }

    private func launchablePackage(_ runner: ShellRunner) throws -> String {
        let listed = try shell(runner, ["pm", "list", "packages"])
        let preferred = ["com.android.tv.settings", "com.android.settings", "com.google.android.tungsten.setupwraith", "app.pohstep.inputprobe"]
        for name in preferred where listed.contains("package:\(name)") {
            return name
        }
        throw XCTSkip("No settings package on this image; probe launch is still covered if present")
    }
}
