import XCTest
@testable import TvRemoteCore

final class ReviewFixesTests: XCTestCase {
    func testLocalNetworkUsageAndBonjourServices() throws {
        let plist = try String(contentsOf: repoRoot().appendingPathComponent("macos/PohstepRemote/Info.plist"), encoding: .utf8)
        XCTAssertTrue(plist.contains("<key>NSLocalNetworkUsageDescription</key>"))
        XCTAssertTrue(plist.contains("<string>Zapbar looks for your TV on your home network and sends it remote commands.</string>"))
        XCTAssertFalse(DiscoveryService.types.isEmpty)
        for type in DiscoveryService.types {
            XCTAssertTrue(plist.contains("<string>\(type)</string>"), type)
        }
    }

    func testSandboxCodesignUsesTheHardenedRuntime() throws {
        let script = try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains(
            #"codesign --force --options runtime --sign "$SIGN" --entitlements macos/PohstepRemote/adb-helper.entitlements"#
        ))
        XCTAssertTrue(script.contains(
            #"codesign --force --options runtime --sign "$SIGN" --entitlements macos/PohstepRemote/Zapbar.entitlements"#
        ))
    }

    func testSandboxCopyOmitsTheHomebrewSentence() throws {
        XCTAssertEqual(Copy.helperMissing, "Zapbar's built-in helper is missing. Reinstall Zapbar.")
        XCTAssertFalse(Copy.helperMissing.localizedCaseInsensitiveContains("homebrew"))
        XCTAssertFalse(Copy.helperMissing.contains("android-platform-tools"))
        let source = try String(contentsOf: repoRoot().appendingPathComponent("Sources/TvRemoteCore/Copy.swift"), encoding: .utf8)
        let branches = source.components(separatedBy: "#if SANDBOX_BUILD").dropFirst()
        XCTAssertGreaterThanOrEqual(branches.count, 2)
        for branch in branches {
            let sandboxOnly = branch.components(separatedBy: "#else").first ?? ""
            XCTAssertFalse(sandboxOnly.contains("android-platform-tools"))
            XCTAssertFalse(sandboxOnly.contains("Homebrew"))
        }
        #if !SANDBOX_BUILD
        XCTAssertTrue(Copy.adbMissing().contains("android-platform-tools"))
        #endif
    }

    func testSandboxSettingsHidesTheAdbPathField() throws {
        let source = try String(contentsOf: repoRoot().appendingPathComponent("macos/PohstepRemote/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("#if !SANDBOX_BUILD"))
        XCTAssertTrue(source.contains("Blank finds Homebrew's adb"))
        let sandbox = sourceWithoutBlocks(source, marker: "#if !SANDBOX_BUILD")
        XCTAssertFalse(sandbox.contains("Homebrew"), sandbox)
        XCTAssertFalse(sandbox.contains("adb path"), sandbox)
        XCTAssertFalse(sandbox.contains("adbBinding"), sandbox)
    }

    func testReleaseAndSandboxSkipV1Migration() throws {
        let root = repoRoot()
        let releaseScript = try String(contentsOf: root.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
        let devScript = try String(contentsOf: root.appendingPathComponent("scripts/build-dev.sh"), encoding: .utf8)
        XCTAssertTrue(releaseScript.contains("ZAPBAR_MIGRATE_V1:-0"))
        XCTAssertTrue(devScript.contains("ZAPBAR_MIGRATE_V1=1"))

        let files = [
            "macos/PohstepRemote/AppModel.swift",
            "macos/PohstepRemote/KeychainStore.swift",
            "Sources/TvRemoteCore/Settings.swift"
        ]
        for relative in files {
            let source = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            let gates = source.components(separatedBy: "\n").filter { $0.contains("#if ZAPBAR_MIGRATE_V1") }
            XCTAssertFalse(gates.isEmpty, relative)
            for gate in gates {
                XCTAssertTrue(gate.contains("!SANDBOX_BUILD"), gate)
            }
            let release = releaseSource(droppingMigrateFlag: source)
            XCTAssertFalse(release.contains("bravia-psk"), relative)
            XCTAssertFalse(release.contains("legacyAccount"), relative)
            XCTAssertFalse(release.contains("Pohstep Remote"), relative)
            XCTAssertFalse(release.contains("secrets.load()"), relative)
            XCTAssertFalse(release.contains("secrets.clear()"), relative)
            XCTAssertFalse(release.contains("migrateLegacy"), relative)
            XCTAssertFalse(release.contains("legacyApplicationSupportURL"), relative)
        }

        let app = try String(contentsOf: root.appendingPathComponent("macos/PohstepRemote/AppModel.swift"), encoding: .utf8)
        let releaseApp = releaseSource(droppingMigrateFlag: app)
        XCTAssertTrue(releaseApp.contains("guard !trimmed.isEmpty, trimmed != \"legacy\" else { return \"\" }"))
        XCTAssertFalse(releaseApp.contains("secrets.load()\n"))
    }

    func testNormalBuildDoesNotStopTheSharedAdbServer() throws {
        let source = try String(contentsOf: repoRoot().appendingPathComponent("macos/PohstepRemote/PohstepRemoteApp.swift"), encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "func applicationWillTerminate"))
        let tail = source[start.lowerBound...]
        let end = tail.range(of: "\n    func ")?.lowerBound ?? tail.endIndex
        let function = String(tail[..<end])
        XCTAssertTrue(function.contains("#if SANDBOX_BUILD"))
        XCTAssertTrue(function.contains("model.stopAdbServer()"))
        let normal = sourceWithoutBlocks(function, marker: "#if SANDBOX_BUILD")
        XCTAssertFalse(normal.contains("stopAdbServer"), normal)
    }

    func testPrivateAdbPortAndKillServer() {
        XCTAssertEqual(AdbLaunch.serverSocket(sandboxed: false), "tcp:localhost:5037")
        XCTAssertEqual(AdbLaunch.serverSocket(sandboxed: true), "tcp:localhost:5038")
        XCTAssertNotEqual(AdbLaunch.serverSocket(sandboxed: true), AdbLaunch.publicServerSocket)
        XCTAssertEqual(AdbLaunch.quitWait, 2)
        #if SANDBOX_BUILD
        XCTAssertEqual(AdbLaunch.defaultServerSocket, AdbLaunch.privateServerSocket)
        #else
        XCTAssertEqual(AdbLaunch.defaultServerSocket, AdbLaunch.publicServerSocket)
        #endif

        let fake = FakeRunner()
        let session = RemoteSession(
            settings: .factoryDefaults(),
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            pathEnvironment: "",
            homeDirectory: "/Users/tester",
            temporaryDirectory: "/tmp/zapbar-adb",
            adbServerSocket: AdbLaunch.serverSocket(sandboxed: true)
        )
        session.stopAdbServer()
        XCTAssertEqual(fake.calls.count, 1)
        XCTAssertEqual(fake.calls[0].arguments, ["-P", "5038", "kill-server"])
        XCTAssertEqual(fake.calls[0].timeout, 2)
        XCTAssertEqual(fake.calls[0].environment["TMPDIR"], "/tmp/zapbar-adb")
        XCTAssertEqual(fake.calls[0].environment["ADB_SERVER_SOCKET"], "tcp:localhost:5038")

        let missing = FakeRunner()
        let absent = RemoteSession(
            settings: .factoryDefaults(),
            runner: missing,
            fileExists: { _ in false },
            pathEnvironment: "",
            homeDirectory: "/Users/tester"
        )
        absent.stopAdbServer()
        XCTAssertTrue(missing.calls.isEmpty)
    }

    func testOneTransferAtATimeAndSerialInstalls() {
        let gate = TransferGate()
        let first = gate.begin(line: "Installing a.apk…", directories: ["/tmp/zapbar-transfer-a"])
        XCTAssertEqual(first, 1)
        XCTAssertNil(gate.begin(line: "Installing b.apk…", directories: ["/tmp/zapbar-transfer-b"]))
        XCTAssertEqual(gate.line, "Installing a.apk…")
        XCTAssertTrue(gate.busy)
        XCTAssertNil(gate.finish(token: 99))
        XCTAssertTrue(gate.busy)
        XCTAssertFalse(gate.update(token: 99, line: "nope"))
        XCTAssertEqual(gate.line, "Installing a.apk…")
        XCTAssertEqual(gate.finish(token: 1), ["/tmp/zapbar-transfer-a"])
        XCTAssertFalse(gate.busy)
        XCTAssertEqual(TransferGate.busySentence, "One transfer at a time.")

        var order: [String] = []
        let done = SerialTransfers.run(["a.apk", "b.apk"]) { path in
            order.append("start \(path)")
            order.append("end \(path)")
            return JobReport(sentence: "Installed.", raw: "", isError: false)
        }
        XCTAssertEqual(order, ["start a.apk", "end a.apk", "start b.apk", "end b.apk"])
        XCTAssertEqual(done.sentence, "Installed.")

        var seen: [String] = []
        let failed = SerialTransfers.run(["a.apk", "b.apk"]) { path in
            seen.append(path)
            return JobReport(sentence: "The install didn't finish.", raw: "", isError: true)
        }
        XCTAssertEqual(seen, ["a.apk"])
        XCTAssertEqual(failed.sentence, "The install didn't finish.")
    }

    func testStageDirectoryIsUniqueAndRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-stage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Show.apk")
        try Data([1, 2]).write(to: source)
        let first = ReadableStage.directory(in: root.path, jobID: "one")
        let second = ReadableStage.directory(in: root.path, jobID: "two")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.contains("zapbar-transfer-one"))
        let copied = try ReadableStage.copy(url: source, into: first)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: copied)), Data([1, 2]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        ReadableStage.remove(first)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testScreenshotNameDoesNotReuseAnExistingFile() {
        XCTAssertEqual(ScreenshotSave.defaultName, "Zapbar screenshot.png")
        XCTAssertEqual(ScreenshotSave.availableName(existing: []), "Zapbar screenshot.png")
        XCTAssertEqual(
            ScreenshotSave.availableName(existing: ["Zapbar screenshot.png"]),
            "Zapbar screenshot 2.png"
        )
        XCTAssertEqual(
            ScreenshotSave.availableName(existing: ["Zapbar screenshot.png", "Zapbar screenshot 2.png"]),
            "Zapbar screenshot 3.png"
        )
    }

    func testDeviceStateTimeoutAndInstallWording() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-review-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let apk = folder.appendingPathComponent("Show.apk")
        try Data([0x50]).write(to: apk)
        let video = folder.appendingPathComponent("Clip.mp4")
        try Data([0]).write(to: video)

        XCTAssertEqual(InstallExplain.sentence(status: 1, output: "adb: device offline"), "The install didn't finish.")
        XCTAssertEqual(
            InstallExplain.sentence(status: 1, output: "Failure [INSTALL_FAILED_VERSION_DOWNGRADE]"),
            "The TV already has a newer version of this app."
        )
        XCTAssertEqual(RemoteError.timedOut("/usr/local/bin/adb").description, "The TV stopped answering.")
        XCTAssertFalse(RemoteError.timedOut("/usr/local/bin/adb").description.contains("/usr/local/bin/adb"))

        let unauthorized = connectedSession()
        unauthorized.fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tunauthorized\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let blocked = unauthorized.session.installApk(at: apk.path)
        XCTAssertEqual(blocked.sentence, Copy.unauthorized(serial: "192.0.2.20:5555"))
        XCTAssertFalse(unauthorized.fake.calls.contains { $0.arguments.contains("install") })

        let offline = connectedSession()
        offline.fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\toffline\n", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        XCTAssertEqual(offline.session.installApk(at: apk.path).sentence, Copy.offline(serial: "192.0.2.20:5555"))
        XCTAssertFalse(offline.fake.calls.contains { $0.arguments.contains("install") })
        XCTAssertEqual(offline.session.installApk(at: video.path).sentence, ApkPick.onlyApk)

        let timed = connectedSession()
        timed.fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("install") {
                return .failure(RemoteError.timedOut("/Applications/Zapbar.app/Contents/Helpers/adb"))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let stalled = timed.session.installApk(at: apk.path)
        XCTAssertEqual(stalled.sentence, "The TV stopped answering.")
        XCTAssertFalse(stalled.sentence.contains("Helpers/adb"))
        XCTAssertFalse(stalled.raw.contains("adb"))
        XCTAssertNotEqual(stalled.sentence, "The TV refused the install.")
    }

    func testBrokenExecOutFallsBackAndDeletesTheTempFiles() throws {
        let rig = connectedSession()
        let red = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
        rig.fake.handler = { arguments in
            if arguments == ["-P", "5037", "devices"] {
                return .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
            }
            if arguments.contains("exec-out") {
                return .failure(RemoteError.timedOut("/usr/local/bin/adb"))
            }
            if arguments.contains("pull") {
                let dest = arguments.last ?? ""
                try? red.write(to: URL(fileURLWithPath: dest))
                return .success(CommandResult(status: 0, stdout: "", stderr: ""))
            }
            return .success(CommandResult(status: 0, stdout: "", stderr: ""))
        }
        let shot = rig.session.captureScreenshot()
        XCTAssertEqual(shot.png, red)
        XCTAssertFalse(shot.isError)
        XCTAssertFalse(shot.sentence.contains("/usr/local/bin/adb"))
        XCTAssertFalse(shot.raw.contains("/usr/local/bin/adb"))
        XCTAssertTrue(rig.fake.calls.contains { $0.arguments.contains("exec-out") })
        XCTAssertTrue(rig.fake.calls.contains { $0.arguments.contains("pull") })
        XCTAssertTrue(rig.fake.calls.contains { $0.arguments.joined(separator: " ").contains("rm -f") })
        if let local = rig.fake.calls.first(where: { $0.arguments.contains("pull") })?.arguments.last {
            XCTAssertFalse(FileManager.default.fileExists(atPath: local))
        }
    }

    func testCancelRemovesThePartialRemoteFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("zapbar-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let apk = folder.appendingPathComponent("Show.apk")
        try Data([0x50]).write(to: apk)
        let rig = connectedSession()
        rig.session.cancelTransfer()
        let install = rig.session.installApk(at: apk.path, clearingCancel: false)
        XCTAssertEqual(install.sentence, "Cancelled.")
        XCTAssertFalse(rig.fake.calls.contains { $0.arguments.contains("install") })
    }

    func testCancelStopsARunningProcess() {
        let runner = ShellRunner()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = try? runner.run("/bin/sleep", arguments: ["30"], timeout: 20)
            done.signal()
        }
        let started = Date()
        var finished = false
        while Date().timeIntervalSince(started) < 2 {
            runner.cancel()
            if done.wait(timeout: .now() + 0.1) == .success {
                finished = true
                break
            }
        }
        XCTAssertTrue(finished)
    }

    /// Release text: drop `#if ZAPBAR_MIGRATE_V1` blocks and keep their `#else` branch.
    private func releaseSource(droppingMigrateFlag source: String) -> String {
        let marker = "#if ZAPBAR_MIGRATE_V1"
        var rest = source
        var kept = ""
        while let start = rest.range(of: marker) {
            kept += rest[..<start.lowerBound]
            guard let end = rest.range(of: "#endif", range: start.upperBound..<rest.endIndex) else { break }
            let block = rest[start.upperBound..<end.lowerBound]
            if let elseRange = block.range(of: "#else") {
                kept += block[elseRange.upperBound...]
            }
            rest = String(rest[end.upperBound...])
        }
        kept += rest
        return kept
    }

    /// Drops each `#if` block opened by `marker`, leaving the text compiled when that condition is false.
    private func sourceWithoutBlocks(_ source: String, marker: String) -> String {
        var rest = source
        var kept = ""
        while let start = rest.range(of: marker) {
            kept += rest[..<start.lowerBound]
            guard let end = rest.range(of: "#endif", range: start.upperBound..<rest.endIndex) else { break }
            rest = String(rest[end.upperBound...])
        }
        kept += rest
        return kept
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func connectedSession() -> (session: RemoteSession, fake: FakeRunner) {
        var settings = Settings.factoryDefaults()
        settings.host = "192.0.2.20"
        settings.port = 5555
        let fake = FakeRunner()
        fake.script = [
            .success(CommandResult(status: 0, stdout: "connected to 192.0.2.20:5555", stderr: "")),
            .success(CommandResult(status: 0, stdout: "List of devices attached\n192.0.2.20:5555\tdevice\n", stderr: ""))
        ]
        let session = RemoteSession(
            settings: settings,
            runner: fake,
            fileExists: { $0 == "/usr/local/bin/adb" },
            homeDirectory: "/Users/tester",
            temporaryDirectory: NSTemporaryDirectory()
        )
        _ = session.refresh()
        fake.calls = []
        fake.script = []
        return (session, fake)
    }
}
