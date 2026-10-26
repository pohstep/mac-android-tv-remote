import XCTest
@testable import TvRemoteCore

final class AdbLayerTests: XCTestCase {
    func testTextEncoding() {
        XCTAssertEqual(AdbText.shellPayloads("hi"), ["'hi'"])
        XCTAssertEqual(AdbText.shellPayloads("hello world"), ["'hello%sworld'"])
        XCTAssertEqual(AdbText.shellPayloads("it's"), ["'it'\\''s'"])
        XCTAssertEqual(AdbText.shellPayloads("100% sure"), ["'100'", "'%'", "'%ssure'"])
        XCTAssertEqual(AdbText.shellPayloads("%s"), ["'%'", "'s'"])
        XCTAssertEqual(AdbText.shellPayloads(""), [])
    }

    func testCommandLines() {
        XCTAssertEqual(AdbCommands.connect(host: "bravia.tail.ts.net", port: 5555), ["connect", "bravia.tail.ts.net:5555"])
        XCTAssertEqual(
            AdbCommands.keyEvent(serial: "emulator-5554", key: .dpadUp),
            ["-s", "emulator-5554", "shell", "input", "keyevent", "KEYCODE_DPAD_UP"]
        )
        XCTAssertEqual(
            AdbCommands.text(serial: "emulator-5554", payload: "'hello%sworld'"),
            ["-s", "emulator-5554", "shell", "input", "text", "'hello%sworld'"]
        )
        XCTAssertEqual(AndroidKey.wakeup.code, 224)
        XCTAssertEqual(AndroidKey.volumeMute.code, 164)
        XCTAssertEqual(AndroidKey.dpadCenter.code, 23)
    }

    func testParseConnectAndDevices() {
        XCTAssertEqual(AdbOutput.parseConnect("connected to 10.0.0.8:5555\n"), .connected)
        XCTAssertEqual(AdbOutput.parseConnect("already connected to 10.0.0.8:5555"), .alreadyConnected)
        let refused = "cannot connect to 10.0.0.8:5555: Connection refused"
        XCTAssertEqual(AdbOutput.parseConnect(refused), .failed(refused))
        XCTAssertTrue(AdbOutput.isRefusal(refused))
        XCTAssertTrue(AdbOutput.isRefusal("connection refused"))
        XCTAssertFalse(AdbOutput.isRefusal("failed to connect to 10.0.0.8:5555"))
        XCTAssertFalse(AdbOutput.isRefusal("cannot connect to 10.0.0.8:5555: No route to host"))
        XCTAssertFalse(AdbOutput.isRefusal("cannot connect to 10.0.0.8:5555"))
        XCTAssertFalse(AdbOutput.isRefusal(""))

        let listing = """
        List of devices attached
        emulator-5554\tdevice
        10.0.0.8:5555\tunauthorized
        10.0.0.9:5555\toffline
        """
        XCTAssertEqual(AdbOutput.parseDevices(listing, serial: "emulator-5554"), .device)
        XCTAssertEqual(AdbOutput.parseDevices(listing, serial: "10.0.0.8:5555"), .unauthorized)
        XCTAssertEqual(AdbOutput.parseDevices(listing, serial: "10.0.0.9:5555"), .offline)
        XCTAssertEqual(AdbOutput.parseDevices(listing, serial: "missing:5555"), .missing)
    }

    func testLaunchFailureDetection() {
        XCTAssertTrue(AdbOutput.outputIndicatesFailure("Error: Activity not started, unable to resolve Intent", status: 0))
        XCTAssertTrue(AdbOutput.outputIndicatesFailure("** No activities found to run, monkey aborted.", status: 0))
        XCTAssertFalse(AdbOutput.outputIndicatesFailure("Starting: Intent { cmp=com.android.tv.settings/.MainSettings }", status: 0))
        XCTAssertFalse(PackageName.isValid("not a package"))
        XCTAssertTrue(PackageName.isValid("org.smarttube.stable"))
    }

    func testLocatorPrefersIntelHomebrewThenPath() {
        let locator = AdbLocator(
            candidatePaths: AdbLocator.defaultCandidates(homeDirectory: "/Users/tester"),
            pathEnvironment: "/usr/bin:/opt/custom/bin",
            fileExists: { path in
                path == "/usr/local/bin/adb" || path == "/opt/custom/bin/adb"
            }
        )
        XCTAssertEqual(locator.resolve(customPath: nil), "/usr/local/bin/adb")
        XCTAssertEqual(locator.resolve(customPath: "/opt/custom/bin/adb"), "/opt/custom/bin/adb")
        XCTAssertNil(locator.resolve(customPath: "/missing/adb"))

        let pathOnly = AdbLocator(candidatePaths: [], pathEnvironment: "/opt/custom/bin", fileExists: { $0 == "/opt/custom/bin/adb" })
        XCTAssertEqual(pathOnly.resolve(customPath: "  "), "/opt/custom/bin/adb")
    }

    func testClientSendsEncodedTextAndFallsBackWhenLaunchFails() throws {
        let fake = FakeRunner()
        fake.script = [
            .success(CommandResult(status: 0, stdout: "", stderr: "")),
            .success(CommandResult(status: 0, stdout: "Error: unable to resolve Intent", stderr: "")),
            .success(CommandResult(status: 0, stdout: "Events injected: 1", stderr: ""))
        ]
        let client = AdbClient(runner: fake, adbPath: "/usr/local/bin/adb")
        try client.inputText("hi there", serial: "emulator-5554")
        try client.launchApp(packageName: "com.netflix.ninja", serial: "emulator-5554")

        XCTAssertEqual(fake.calls.map(\.arguments), [
            ["-s", "emulator-5554", "shell", "input", "text", "'hi%sthere'"],
            AdbCommands.launchLeanback(serial: "emulator-5554", packageName: "com.netflix.ninja"),
            AdbCommands.launchMonkey(serial: "emulator-5554", packageName: "com.netflix.ninja", category: "android.intent.category.LEANBACK_LAUNCHER")
        ])
    }

    func testBundledHelperWinsAndSandboxSkipsAUserInstall() {
        XCTAssertEqual(
            AdbLocator.helperPath(bundlePath: "/Applications/Zapbar.app"),
            "/Applications/Zapbar.app/Contents/Helpers/adb"
        )
        let bundled = AdbLocator(
            candidatePaths: ["/usr/local/bin/adb"],
            pathEnvironment: "/usr/local/bin",
            fileExists: { $0 == "/usr/local/bin/adb" || $0.hasSuffix("/Contents/Helpers/adb") },
            bundledHelperPath: "/Applications/Zapbar.app/Contents/Helpers/adb"
        )
        XCTAssertEqual(bundled.resolve(customPath: "/usr/local/bin/adb"), "/Applications/Zapbar.app/Contents/Helpers/adb")

        let sandbox = AdbLocator(
            candidatePaths: ["/usr/local/bin/adb"],
            pathEnvironment: "/usr/local/bin",
            fileExists: { $0 == "/usr/local/bin/adb" },
            bundledHelperPath: "/Applications/Zapbar.app/Contents/Helpers/adb",
            allowUserInstall: false
        )
        XCTAssertNil(sandbox.resolve(customPath: "/usr/local/bin/adb"))
    }

    func testLaunchEnvironmentAndPairCommand() throws {
        let env = AdbLaunch.environment(temporaryDirectory: "/var/folders/zapbar", serverSocket: "tcp:localhost:5037")
        XCTAssertEqual(env["TMPDIR"], "/var/folders/zapbar")
        XCTAssertEqual(env["ADB_SERVER_SOCKET"], "tcp:localhost:5037")
        XCTAssertEqual(AdbCommands.pair(host: "192.0.2.8", port: 37111, code: "123456"), ["pair", "192.0.2.8:37111", "123456"])
        XCTAssertTrue(AdbOutput.parsePair("Successfully paired to 192.0.2.8:37111"))
        XCTAssertFalse(AdbOutput.parsePair("Failed: invalid pairing code"))

        let fake = FakeRunner()
        fake.script = [.success(CommandResult(status: 0, stdout: "Successfully paired to 192.0.2.8:37111\n", stderr: ""))]
        let client = AdbClient(
            runner: fake,
            adbPath: "/Applications/Zapbar.app/Contents/Helpers/adb",
            temporaryDirectory: "/var/folders/zapbar",
            serverSocket: "tcp:localhost:5037"
        )
        XCTAssertTrue(try client.pair(host: "192.0.2.8", port: 37111, code: "123456"))
        XCTAssertEqual(fake.calls.first?.environment["TMPDIR"], "/var/folders/zapbar")
        XCTAssertEqual(fake.calls.first?.environment["ADB_SERVER_SOCKET"], "tcp:localhost:5037")
    }

    func testHostInputAcceptsTailscaleNamesAndPastedConnectLines() {
        XCTAssertEqual(HostInput.normalize("bravia.tailnet.ts.net").host, "bravia.tailnet.ts.net")
        XCTAssertNil(HostInput.normalize("bravia.tailnet.ts.net").port)
        XCTAssertEqual(HostInput.normalize("192.0.2.20:5555").host, "192.0.2.20")
        XCTAssertEqual(HostInput.normalize("192.0.2.20:5555").port, 5555)
        XCTAssertEqual(HostInput.normalize("adb connect 10.1.1.8:5555").host, "10.1.1.8")
        XCTAssertEqual(HostInput.normalize("http://living-room.local:5555/ignored").host, "living-room.local")
        XCTAssertTrue(HostInput.isValidHost("bravia.tailnet.ts.net"))
        XCTAssertFalse(HostInput.isValidHost("has a space"))
        XCTAssertFalse(HostInput.isValidHost(""))
    }
}
